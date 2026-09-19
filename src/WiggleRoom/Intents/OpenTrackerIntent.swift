//
//  OpenTrackerIntent.swift
//  WiggleRoom
//

import AppIntents

/// Opens a tracker's dashboard — what tapping a tracker's Spotlight result
/// runs, and usable from Shortcuts / the Action Button. Reuses the widget
/// deep link so there's one navigation path into a tracker.
struct OpenTrackerIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Tracker"

    @Parameter(title: "Tracker")
    var target: TrackerEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WiggleRoomDeepLink.url(forTrackerId: target.id)))
    }
}
