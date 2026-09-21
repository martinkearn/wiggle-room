//
//  BackgroundRefreshScheduler.swift
//  WiggleRoom
//

#if os(iOS)
import BackgroundTasks
import SwiftData

/// Background refresh for auto-fetch connected sources (Starling, and any
/// future provider) — via `BGAppRefreshTask`. iOS treats the requested
/// interval as a minimum, not a guarantee — actual firing cadence is
/// entirely up to the system, and can be much less frequent in practice
/// (low battery, Low Power Mode, app rarely opened, …).
///
/// Cadence is per-tracker, not a single flat interval (§5.3): each
/// tracker is due again once `TrackerUpdateScheduling.RefreshBand`'s
/// interval has passed since its own `lastAutoFetchAttempt` — peak
/// (08:00–17:00) every 5 minutes, standard every 15, off-peak
/// (00:00–06:00) every 60 — or, independent of the clock, every 5 minutes
/// while that specific tracker is in an active burst (`isBursting`). A
/// wake-up still refreshes the whole process at once (`BGAppRefreshTask`
/// has no per-tracker scheduling of its own — only one earliest-begin-date
/// can be requested for the whole app), but which trackers actually get a
/// real Starling request during that wake-up, and when the *next*
/// wake-up is requested for, are both computed per-tracker: a burst on
/// one tracker pulls the next wake-up in for everyone, but a
/// not-yet-due, non-bursting tracker is still skipped on that earlier
/// wake-up rather than getting checked more often than its own band
/// calls for.
enum BackgroundRefreshScheduler {
    static let taskIdentifier = "martinkearn.WiggleRoom.starlingRefresh"

    /// Set by `register(container:)` so `scheduleNext()` can compute a
    /// real, data-aware next-due interval without every call site needing
    /// to thread a container through.
    private static var container: ModelContainer?

    /// Registers the background task handler. Must happen before the app
    /// finishes launching — call this from `WiggleRoomApp.init()`, not from
    /// anywhere later in the app's lifecycle.
    static func register(container: ModelContainer) {
        Self.container = container
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, container: container)
        }
    }

    /// Requests the next background run, timed to whichever tracker is due
    /// soonest (falling back to a plain standard-band interval if there's
    /// no container yet, or no auto-fetch trackers at all). A fired or
    /// expired task doesn't reschedule itself, so this needs calling again
    /// after each one — from launch, and every time the app is backgrounded
    /// (see `WiggleRoomApp`'s `scenePhase` observer).
    @MainActor
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: nextInterval())
        // Submission can fail harmlessly in the Simulator or when Background
        // App Refresh is unavailable, so scheduling remains best-effort.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        // Always request the next run immediately, regardless of how this
        // one goes — otherwise a single failure/expiry would silently end
        // background refresh for good.
        scheduleNext()

        let refreshWork = Task {
            await refreshDueAutoFetchTrackers(container: container)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshWork.cancel()
        }
    }

    /// How much longer until the soonest-due auto-fetch tracker needs
    /// checking again — 0 if one is already overdue right now.
    @MainActor
    private static func nextInterval() -> TimeInterval {
        guard let container, let trackers = try? container.mainContext.fetch(FetchDescriptor<Tracker>()) else {
            return TrackerUpdateScheduling.RefreshBand.standard.interval
        }
        let now = Date.now
        let dueTrackers = trackers.filter { !$0.isManualEntry && !$0.isCompleted() }
        guard !dueTrackers.isEmpty else { return TrackerUpdateScheduling.RefreshBand.standard.interval }
        return dueTrackers.map { timeUntilDue($0, asOf: now) }.min() ?? TrackerUpdateScheduling.RefreshBand.standard.interval
    }

    /// This tracker's own effective band right now — `peak`'s cadence
    /// while it's individually bursting, regardless of the actual time of
    /// day, otherwise whatever the clock says.
    @MainActor
    private static func effectiveBand(for tracker: Tracker, asOf now: Date) -> TrackerUpdateScheduling.RefreshBand {
        TrackerUpdateScheduling.isBursting(readings: tracker.sortedReadings, asOf: now)
            ? .peak
            : TrackerUpdateScheduling.refreshBand(at: now)
    }

    /// Seconds until `tracker` is next due for a background check, 0 if
    /// it's already overdue. Never attempted before (`lastAutoFetchAttempt`
    /// is `nil`) counts as maximally overdue.
    @MainActor
    private static func timeUntilDue(_ tracker: Tracker, asOf now: Date) -> TimeInterval {
        let interval = effectiveBand(for: tracker, asOf: now).interval
        let sinceLastAttempt = now.timeIntervalSince(tracker.lastAutoFetchAttempt ?? .distantPast)
        return max(0, interval - sinceLastAttempt)
    }

    @MainActor
    private static func refreshDueAutoFetchTrackers(container: ModelContainer) async {
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        guard let trackers = try? context.fetch(FetchDescriptor<Tracker>()) else { return }
        let now = Date.now
        for tracker in trackers where !tracker.isManualEntry && !tracker.isCompleted() {
            guard !Task.isCancelled else { return }
            guard timeUntilDue(tracker, asOf: now) <= 0 else { continue }
            // Recorded regardless of outcome — a no-change poll or a
            // failure still counts as "checked," so a persistently-failing
            // source doesn't get retried every single wake-up instead of
            // waiting out its own band like everything else.
            tracker.lastAutoFetchAttempt = now
            _ = try? await store.refreshFromSource(tracker)
        }
        try? context.save()
    }
}
#endif
