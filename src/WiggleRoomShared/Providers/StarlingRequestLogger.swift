//
//  StarlingRequestLogger.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// Bridges `StarlingRequestBudget`'s plain-actor `onRequestLogged` hook
/// (fired once per real Starling request, from whatever thread that
/// actor's own executor happens to run on) into a CloudKit-synced
/// `StarlingRequestLogEntry` insert — see that model's own doc comment for
/// why a per-request insert, not a shared counter, is what actually merges
/// safely across the user's devices.
///
/// Configured once at launch (`configure(container:)`, mirroring
/// `BackgroundRefreshScheduler.register(container:)`) so the rest of the
/// app doesn't need to thread a `ModelContext` through every Starling call
/// site. `record(at:)` opens its own fresh `ModelContext` per call rather
/// than reusing `container.mainContext` — `mainContext` is main-actor
/// bound, and this can be called from `StarlingRequestBudget`'s own
/// (non-main) actor executor; a short-lived context created, used, and
/// discarded within one synchronous call needs no thread coordination of
/// its own.
enum StarlingRequestLogger {
    private static var container: ModelContainer?

    /// How long a log entry is kept before `prune()` removes it — generous
    /// enough to always cover "today" regardless of which timezone the
    /// user is in relative to UTC, without keeping every request ever made
    /// forever (each one is a small but real synced CloudKit record).
    private static let retention: TimeInterval = 3 * 24 * 3600

    static func configure(container: ModelContainer) {
        Self.container = container
        prune()
    }

    static func record(at date: Date) {
        guard let container else { return }
        let context = ModelContext(container)
        context.insert(StarlingRequestLogEntry(date: date))
        try? context.save()
    }

    /// Best-effort, run once at launch rather than on every insert — no
    /// need to be exact; this is purely about bounding long-run CloudKit
    /// storage, not correctness of the displayed count, which always
    /// queries "today" fresh via `@Query` wherever it's shown.
    private static func prune() {
        guard let container else { return }
        let context = ModelContext(container)
        let cutoff = Date.now.addingTimeInterval(-retention)
        let descriptor = FetchDescriptor<StarlingRequestLogEntry>(predicate: #Predicate { $0.date < cutoff })
        guard let stale = try? context.fetch(descriptor) else { return }
        for entry in stale {
            context.delete(entry)
        }
        try? context.save()
    }
}
