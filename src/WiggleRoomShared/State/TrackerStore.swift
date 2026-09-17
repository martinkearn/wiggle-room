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
    let manualEntrySource: ConnectedSource

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
    /// call (cheap — it just wraps a Keychain lookup and shares the app-wide
    /// rate-limit budget, see `StarlingProvider.sharedBudget`), so this is
    /// safe to call as often as needed rather than something callers need
    /// to cache themselves.
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
    func refreshFromSource(_ tracker: Tracker) async throws {
        guard !tracker.isManualEntry,
              let sourceTargetId = tracker.sourceTargetId,
              let provider = provider(for: tracker)
        else { return }
        let target = SourceTarget(id: sourceTargetId, displayName: tracker.name)
        let value = try await provider.fetchCurrentValue(target: target)
        logReading(value: value, date: .now, for: tracker)
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
