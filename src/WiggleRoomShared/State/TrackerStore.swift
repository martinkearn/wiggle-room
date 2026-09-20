//
//  TrackerStore.swift
//  WiggleRoom
//

import Foundation
import Observation
import SwiftData
import WidgetKit

enum TrackerStoreError: Error, Equatable {
    /// `source.providerId` didn't resolve to any known provider (manual or
    /// Starling) — reachable only for a source with a provider id from a
    /// future/unsupported provider.
    case unresolvableProvider
}

/// App-wide actions and the fixed manual-entry source, backed by SwiftData
/// (§6) rather than in-memory storage. Tracker/source lists themselves are
/// read via `@Query` directly in views (the idiomatic, auto-updating
/// SwiftData pattern) — this type holds only what a `@Query` can't express:
/// the manual-entry singleton, and mutating actions.
///
/// `@MainActor`-isolated: `refreshFromSource(_:)` below is genuinely async
/// (a network fetch), and every other method here touches `ModelContext`
/// directly — pinning the whole type to the main actor is what keeps that
/// safe rather than relying on callers to always already be there.
@MainActor
@Observable
final class TrackerStore {
    private let modelContext: ModelContext

    let manualProvider: ManualEntryProvider

    /// The single, fixed "Manual Entry" pseudo-source. Picking it for a
    /// tracker means the user logs its readings themselves rather than the
    /// app reading them from anywhere — it isn't a real connection, just
    /// the provider-abstraction plumbing (§5.1) a tracker's connected
    /// source needs to point at. Unlike a real connected source it is never
    /// listed in Settings → Connected Sources (§5.2) and there is exactly
    /// one of it — never user-creatable, never duplicated. Fetched once at
    /// launch, created the first time only.
    private(set) var manualEntrySource: ConnectedSource
    private(set) var lastManualEntryHousekeepingDate: Date?
    private(set) var lastManualEntryHousekeepingRemovedCount = 0
    private(set) var manualEntryHousekeepingError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.manualProvider = ManualEntryProvider(modelContext: modelContext)
        self.manualEntrySource = Self.fetchOrCreateManualEntrySource(in: modelContext)
    }

    func addTracker(_ tracker: Tracker) {
        modelContext.insert(tracker)
        try? modelContext.save()
        ReminderScheduler.sync(tracker)
        reloadWidgets()
    }

    func deleteTracker(_ tracker: Tracker) {
        ReminderScheduler.cancel(tracker)
        modelContext.delete(tracker)
        try? modelContext.save()
        reloadWidgets()
    }

    /// Wipes every tracker (and, via its cascade delete rule, every
    /// reading), every real connected source, and every Starling request
    /// log entry — a full reset back to a blank app. Deliberately something
    /// the user has to explicitly trigger from Settings (§7.2/§12) rather
    /// than anything automatic, after a real 2026-09-18 incident where a
    /// schema mismatch across processes corrupted local test data badly
    /// enough that some records couldn't even be selected/deleted
    /// individually (see progress-notes.md) — this is the clean-slate
    /// escape hatch for exactly that kind of situation, not a routine
    /// feature. The fixed "Manual Entry" pseudo-source (`manualEntrySource`)
    /// is deliberately **not** deleted — it's required plumbing every
    /// tracker's source picker depends on existing, not user data, and
    /// `TrackerStore` doesn't currently support recreating it without a
    /// fresh `init`.
    func resetAllData() {
        let trackers = (try? modelContext.fetch(FetchDescriptor<Tracker>())) ?? []
        for tracker in trackers {
            ReminderScheduler.cancel(tracker)
            modelContext.delete(tracker)
        }
        let sources = (try? modelContext.fetch(FetchDescriptor<ConnectedSource>())) ?? []
        for source in sources where source.providerId != manualProvider.providerId {
            modelContext.delete(source)
        }
        let requestLog = (try? modelContext.fetch(FetchDescriptor<StarlingRequestLogEntry>())) ?? []
        for entry in requestLog {
            modelContext.delete(entry)
        }
        try? modelContext.save()
        reloadWidgets()
    }

    /// Collapses duplicate Manual Entry pseudo-sources created by devices
    /// before their first CloudKit import. The lexicographically-lowest UUID is
    /// selected so every device that sees the same records chooses the same
    /// canonical source. Trackers are reassigned before duplicates are deleted.
    @discardableResult
    func consolidateManualEntrySources() throws -> Int {
        let sources = try modelContext.fetch(FetchDescriptor<ConnectedSource>())
        let manualSources = sources.filter { $0.providerId == manualProvider.providerId }
        guard let canonicalSource = manualSources.min(by: {
            $0.id.uuidString < $1.id.uuidString
        }) else {
            return 0
        }

        manualEntrySource = canonicalSource
        let duplicates = manualSources.filter {
            $0.persistentModelID != canonicalSource.persistentModelID
        }
        guard !duplicates.isEmpty else { return 0 }

        let duplicateIDs = Set(duplicates.map(\.persistentModelID))
        let trackers = try modelContext.fetch(FetchDescriptor<Tracker>())
        for tracker in trackers {
            if let sourceID = tracker.connectedSource?.persistentModelID,
               duplicateIDs.contains(sourceID) {
                tracker.connectedSource = canonicalSource
            }
        }
        for duplicate in duplicates {
            modelContext.delete(duplicate)
        }

        try modelContext.save()
        reloadWidgets()
        return duplicates.count
    }

    /// Runs idempotent housekeeping after giving SwiftData's CloudKit store time
    /// to import records. It is safe to call at launch and on every activation.
    func performManualEntryHousekeeping(after delay: Duration = .zero) async {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        guard !Task.isCancelled else { return }

        do {
            lastManualEntryHousekeepingRemovedCount = try consolidateManualEntrySources()
            manualEntryHousekeepingError = nil
        } catch {
            lastManualEntryHousekeepingRemovedCount = 0
            manualEntryHousekeepingError = error.localizedDescription
        }
        lastManualEntryHousekeepingDate = .now
    }

    /// Persists in-place edits to an existing `@Model` object (e.g. from
    /// editing a tracker's details) — SwiftData tracks the mutation, this
    /// just flushes it. `reminderCadenceMinutes` may have changed as part of
    /// that edit, so the scheduled reminder (§5.5) is re-synced too.
    func saveChanges(reminderTracker: Tracker? = nil) {
        try? modelContext.save()
        if let reminderTracker {
            ReminderScheduler.sync(reminderTracker)
        }
        reloadWidgets()
    }

    /// Appends a manually-logged reading directly — the dashboard and log
    /// sheet already hold the `Tracker` reference, so this bypasses the
    /// target-id indirection `ManualEntryProvider` exists for.
    func logReading(value: Decimal, date: Date, for tracker: Tracker) {
        let reading = ValueSnapshot(value: value, date: date)
        reading.tracker = tracker
        modelContext.insert(reading)
        try? modelContext.save()
        reloadWidgets()
        #if os(iOS) && canImport(ActivityKit)
        TrackerLiveActivity.sync(tracker)
        #endif
    }

    /// Removes a single previously-logged reading (manual trackers only —
    /// see `Tracker.isManualEntry`).
    func deleteReading(_ reading: ValueSnapshot) {
        modelContext.delete(reading)
        try? modelContext.save()
        reloadWidgets()
    }

    /// The provider that owns `tracker`'s connected source, or `nil` for a
    /// manual tracker or one whose source doesn't resolve to a known
    /// provider. A fresh `StarlingProvider` instance is handed back on each
    /// call (cheap — it just reads `credentialToken` straight off the
    /// `ConnectedSource` record and shares the app-wide rate-limit budget,
    /// see `StarlingProvider.sharedBudget`), so this is safe to call as
    /// often as needed rather than something callers need to cache
    /// themselves.
    func provider(for tracker: Tracker) -> SourceProvider? {
        guard let source = tracker.connectedSource else { return nil }
        return resolvedProvider(for: source)
    }

    /// Lists the pickable targets (Starling accounts, etc.) within `source`
    /// — used by `AddTrackerView`'s target picker once a real (non-manual)
    /// source is selected, before any `Tracker` exists to resolve a
    /// provider from via `provider(for:)`.
    func listAvailableTargets(for source: ConnectedSource) async throws -> [SourceTarget] {
        guard let provider = resolvedProvider(for: source) else { return [] }
        return try await provider.listAvailableTargets(for: source)
    }

    /// Fetches `target`'s current value directly from `source`'s provider —
    /// used by `AddTrackerView` to prefill "Starting value" with the live
    /// balance once the user picks a Starling account (§5.3), before any
    /// `Tracker` exists yet to resolve a provider from via `provider(for:)`.
    func fetchCurrentValue(for target: SourceTarget, from source: ConnectedSource) async throws -> Decimal {
        guard let provider = resolvedProvider(for: source) else {
            throw TrackerStoreError.unresolvableProvider
        }
        return try await provider.fetchCurrentValue(target: target)
    }

    private func resolvedProvider(for source: ConnectedSource) -> SourceProvider? {
        switch source.providerId {
        case manualProvider.providerId:
            return manualProvider
        case "starling":
            return StarlingProvider(connection: source)
        default:
            return nil
        }
    }

    /// Fetches a fresh value from `tracker`'s connected source (Starling,
    /// and any future auto-fetch provider) and logs it as a new timestamped
    /// reading (§6) — the same shape as a manual log, so trend-chart history
    /// works identically regardless of where a reading came from. No-ops
    /// for a manual-entry tracker (nothing to fetch) or one with no
    /// resolvable provider/target.
    ///
    /// Only logs a new reading when the fetched value actually differs from
    /// the latest one already on record — the 30s foreground poll (§5.3)
    /// would otherwise write a near-duplicate, same-value reading on every
    /// single tick regardless of whether anything changed, flooding the
    /// trend chart with so many overlapping same-value points that
    /// individual readings become visually indistinguishable from the line
    /// connecting them, and needlessly bloating the synced reading history.
    /// A poll that finds nothing changed still counts as a successful
    /// refresh (clears any stale error state) — it just doesn't need its
    /// own row. Returns whether the value actually changed (a new reading
    /// was logged), so callers can back off their own poll interval when a
    /// tracker's value has been static for a while (§5.3) — freshness only
    /// matters when something's actually moving, and every no-op poll
    /// still spends a real Starling request either way.
    @discardableResult
    func refreshFromSource(_ tracker: Tracker, force: Bool = false) async throws -> Bool {
        guard !tracker.isManualEntry,
              let sourceTargetId = tracker.sourceTargetId,
              let provider = provider(for: tracker)
        else { return false }
        let target = SourceTarget(id: sourceTargetId, displayName: tracker.name)
        let value = try await provider.fetchCurrentValue(target: target)
        tracker.lastCheckedDate = .now
        guard force || value != tracker.latestReading?.value else {
            try? modelContext.save()
            return false
        }
        logReading(value: value, date: .now, for: tracker)
        return true
    }

    /// Every mutation flows through this store (the app, and Shortcuts/Siri
    /// via `IntentDataStore.store()`), so this is the one place that needs
    /// to tell WidgetKit a tracker's figures may have changed — without it,
    /// a Home Screen/Lock Screen widget only picks up new data on its own
    /// refresh schedule (up to an hour away, see `TrackerTimelineProvider`),
    /// showing stale numbers even though the app itself is current.
    /// watchOS complications reuse the same mechanism once one exists; the
    /// widget extension itself also links WidgetKit (compiled from this
    /// same shared file) but never calls this — reloading its own timeline
    /// from inside itself would be pointless.
    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func fetchOrCreateManualEntrySource(in context: ModelContext) -> ConnectedSource {
        let manualProviderId = "manual"
        let all = (try? context.fetch(FetchDescriptor<ConnectedSource>())) ?? []
        if let existing = all.first(where: { $0.providerId == manualProviderId }) {
            return existing
        }
        let source = ConnectedSource(providerId: manualProviderId, displayName: "Manual Entry")
        context.insert(source)
        try? context.save()
        return source
    }
}
