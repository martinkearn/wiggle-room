//
//  DeepLinkRouter.swift
//  WiggleRoom
//

import Foundation
import Observation

/// Holds a tracker id the app has just been asked to navigate straight to —
/// e.g. from `.onOpenURL` handling a widget tap's `wiggleroom://tracker/…`
/// link — until `TrackerListView` picks it up and pushes the matching
/// detail screen. A single pending value is enough: only one navigation
/// request can be "in flight" at a time.
@Observable
final class DeepLinkRouter {
    var pendingTrackerId: UUID?

    func handle(_ url: URL) {
        guard let id = WiggleRoomDeepLink.trackerId(from: url) else { return }
        pendingTrackerId = id
    }
}
