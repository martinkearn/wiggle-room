//
//  TrackerStore.swift
//  Ringet
//

import Foundation
import Observation
import SwiftData

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
    }

    func deleteTracker(_ tracker: Tracker) {
        modelContext.delete(tracker)
        try? modelContext.save()
    }

    /// Persists in-place edits to an existing `@Model` object (e.g. from
    /// editing a tracker's details) — SwiftData tracks the mutation, this
    /// just flushes it.
    func saveChanges() {
        try? modelContext.save()
    }

    /// Appends a manually-logged reading directly — the dashboard and log
    /// sheet already hold the `Tracker` reference, so this bypasses the
    /// target-id indirection `ManualEntryProvider` exists for.
    func logReading(value: Decimal, date: Date, for tracker: Tracker) {
        let reading = ValueSnapshot(value: value, date: date)
        reading.tracker = tracker
        modelContext.insert(reading)
        try? modelContext.save()
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
