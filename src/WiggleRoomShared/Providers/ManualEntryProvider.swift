//
//  ManualEntryProvider.swift
//  WiggleRoom
//

import Foundation
import SwiftData

enum ManualEntryProviderError: Error, Equatable {
    /// `fetchCurrentValue` was called for a target that has never had a
    /// reading logged against it.
    case noReadingsLogged(targetId: String)
    /// The target's id didn't resolve to a persisted tracker.
    case trackerNotFound(targetId: String)
}

/// The manual-entry source provider (§5.5) — used for anything without an
/// API. `actualValue` is always the most recently logged reading; there is
/// no automatic refresh.
///
/// Each manual tracker owns its own dedicated reading log (see
/// `AddTrackerView`'s doc comment) rather than picking from a shared list of
/// named logs, so a target's id is simply the owning `Tracker`'s own id —
/// readings live on `Tracker.readings` directly, persisted via SwiftData
/// (§6) rather than the in-memory store this provider used before.
///
/// In practice, app code that already holds a `Tracker` reference (the
/// dashboard, the log-reading sheet) reads/writes `tracker.readings`
/// directly rather than going through this provider — it exists so the
/// generic `SourceProvider` abstraction has a real manual implementation to
/// swap alongside a future Starling/Tesla provider, and so provider-shaped
/// code (tests included) has something to call against target ids alone.
@MainActor
final class ManualEntryProvider: SourceProvider {
    nonisolated let providerId = "manual"
    nonisolated let displayName = "Manual entry"
    nonisolated let requiresConnection = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Manual entry has no shared list of targets to pick from — each
    /// tracker gets its own dedicated log created at save time (see
    /// `AddTrackerView.save()`), so this always returns empty.
    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget] {
        []
    }

    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal {
        guard let tracker = try fetchTracker(id: target.id) else {
            throw ManualEntryProviderError.trackerNotFound(targetId: target.id)
        }
        guard let latest = tracker.latestReading else {
            throw ManualEntryProviderError.noReadingsLogged(targetId: target.id)
        }
        return latest.value
    }

    func logManualReading(target: SourceTarget, value: Decimal, date: Date) async throws {
        guard let tracker = try fetchTracker(id: target.id) else {
            throw ManualEntryProviderError.trackerNotFound(targetId: target.id)
        }
        let reading = ValueSnapshot(value: value, date: date)
        reading.tracker = tracker
        modelContext.insert(reading)
        try modelContext.save()
    }

    private func fetchTracker(id: String) throws -> Tracker? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<Tracker>(predicate: #Predicate { $0.id == uuid })
        return try modelContext.fetch(descriptor).first
    }
}
