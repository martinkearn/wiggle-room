//
//  CloudSyncWidgetRefresher.swift
//  WiggleRoomShared
//

import CoreData
import Foundation
import SwiftData
import WidgetKit

/// Watches for CloudKit importing remote changes into the local SwiftData
/// store — e.g. a reading logged on another device — and reloads widget/
/// complication timelines when that happens. `TrackerStore`'s own actions
/// already trigger a reload for changes made *in this app*, but a change
/// that arrives via CloudKit sync while the app is simply open doesn't go
/// through any `TrackerStore` method at all; without this, a widget would
/// only pick it up on its own refresh schedule (up to an hour away per
/// `TrackerTimelineProvider`), showing stale figures even though the app,
/// freshly opened, is already current. Also refreshes `TrackerListCache` for
/// the same reason: a tracker created on another device syncing in here
/// should update the shared picker cache too, not just widget content.
enum CloudSyncWidgetRefresher {
    private static var observer: NSObjectProtocol?

    /// Call once per app process (the main app and the watch app each start
    /// their own), passing that process's own `ModelContainer`. Safe to call
    /// more than once — only the first call actually registers the
    /// observer.
    @MainActor
    static func start(modelContainer: ModelContainer) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            // Deferred to a later run-loop turn via `Task`, not run inline
            // here: CoreData's own remote-change delivery
            // (`_postStoreRemoteChangeNotificationsForStore:andState:`)
            // waits for this observer to return before it continues, so
            // doing the fetch/save/widget-reload synchronously in this same
            // call frame serialized it behind whatever else the main thread
            // was doing — confirmed via a crash report (2026-09-22) where
            // tapping into a freshly-created Starling source (CloudKit
            // reflecting the just-created record back at the same moment as
            // the NavigationLink push) stalled the main thread past the
            // OS's 10-second scene-update watchdog and got the app killed.
            Task { @MainActor in
                if let trackers = try? modelContainer.mainContext.fetch(FetchDescriptor<Tracker>()) {
                    TrackerListCache.save(trackers)
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
