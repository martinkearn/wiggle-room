//
//  ViewTrackerStatusIntent.swift
//  WiggleRoom
//

import AppIntents
import Foundation

/// A quick, spoken/read status check via Siri/Shortcuts — "how am I doing
/// on my mileage tracker?" — without opening the app. Read-only, unlike
/// `LogReadingIntent`.
struct ViewTrackerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check a Tracker"
    static var description = IntentDescription("Reports a tracker's current pace against its target.")

    @Parameter(title: "Tracker")
    var tracker: TrackerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let liveTracker = try IntentDataStore.fetchTracker(id: tracker.id) else {
            return .result(dialog: "I couldn't find that tracker.")
        }
        let pace = liveTracker.pace(actualValue: liveTracker.latestReading?.value ?? liveTracker.startingValue)
        let dialog = "\(liveTracker.name): \(pace.statusLine(for: liveTracker)) \(pace.displayDifference(for: liveTracker))."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
