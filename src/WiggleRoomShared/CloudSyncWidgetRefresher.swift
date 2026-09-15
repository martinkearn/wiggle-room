//
//  CloudSyncWidgetRefresher.swift
//  WiggleRoomShared
//

import CoreData
import Foundation
import WidgetKit

/// Watches for CloudKit importing remote changes into the local SwiftData
/// store — e.g. a reading logged on another device — and reloads widget/
/// complication timelines when that happens. `TrackerStore`'s own actions
/// already trigger a reload for changes made *in this app*, but a change
/// that arrives via CloudKit sync while the app is simply open doesn't go
/// through any `TrackerStore` method at all; without this, a widget would
/// only pick it up on its own refresh schedule (up to an hour away per
/// `TrackerTimelineProvider`), showing stale figures even though the app,
/// freshly opened, is already current.
enum CloudSyncWidgetRefresher {
    private static var observer: NSObjectProtocol?

    /// Call once per app process (the main app and the watch app each start
    /// their own). Safe to call more than once — only the first call
    /// actually registers the observer.
    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
