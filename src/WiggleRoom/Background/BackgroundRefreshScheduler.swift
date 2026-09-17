//
//  BackgroundRefreshScheduler.swift
//  WiggleRoom
//

#if os(iOS)
import BackgroundTasks
import SwiftData

/// Background refresh for auto-fetch connected sources (Starling, and any
/// future provider) — §5.3's 5-minute background cadence, via
/// `BGAppRefreshTask`. iOS treats the requested interval as a minimum, not
/// a guarantee — actual firing cadence is entirely up to the system, and
/// can be much less frequent in practice (low battery, Low Power Mode, app
/// rarely opened, …).
enum BackgroundRefreshScheduler {
    static let taskIdentifier = "martinkearn.WiggleRoom.starlingRefresh"
    private static let minimumInterval: TimeInterval = 5 * 60

    /// Registers the background task handler. Must happen before the app
    /// finishes launching — call this from `WiggleRoomApp.init()`, not from
    /// anywhere later in the app's lifecycle.
    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, container: container)
        }
    }

    /// Requests the next background run. A fired or expired task doesn't
    /// reschedule itself, so this needs calling again after each one — from
    /// launch, and every time the app is backgrounded (see
    /// `WiggleRoomApp`'s `scenePhase` observer).
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected (and harmless) in the Simulator or a build without
            // the Background App Refresh capability actually granted by the
            // user — not fatal either way.
        }
    }

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        // Always request the next run immediately, regardless of how this
        // one goes — otherwise a single failure/expiry would silently end
        // background refresh for good.
        scheduleNext()

        let refreshWork = Task {
            await refreshAllAutoFetchTrackers(container: container)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshWork.cancel()
        }
    }

    @MainActor
    private static func refreshAllAutoFetchTrackers(container: ModelContainer) async {
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        guard let trackers = try? context.fetch(FetchDescriptor<Tracker>()) else { return }
        for tracker in trackers where !tracker.isManualEntry && !tracker.isCompleted() {
            guard !Task.isCancelled else { return }
            try? await store.refreshFromSource(tracker)
        }
    }
}
#endif
