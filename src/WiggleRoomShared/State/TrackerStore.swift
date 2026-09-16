//
//  TrackerStore.swift
//  WiggleRoom
//

import Foundation
import Observation
import SwiftData
import WidgetKit

/// App-wide actions and the fixed manual-entry source, backed by SwiftData
/// (§6) rather than in-memory storage. Tracker/source lists themselves are
/// read via `@Query` directly in views (the idiomatic, auto-updating
/// SwiftData pattern) — this type holds only what a `@Query` can't express:
/// the manual-entry singleton, and mutating actions.
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
    /// just flushes it. `reminderCadenceDays` may have changed as part of
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
