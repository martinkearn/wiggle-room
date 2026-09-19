//
//  ViewTrackerStatusIntent.swift
//  WiggleRoom
//

import AppIntents
import Foundation

/// A quick, spoken/read status check via Siri/Shortcuts — "what's my Wiggle
/// Room?" — without opening the app. Read-only, unlike `LogReadingIntent`.
/// With no tracker named it summarises every active tracker (or just the one,
/// if there's only one); naming one ("how's Groceries in Wiggle Room") checks
/// just that.
struct ViewTrackerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check a Tracker"
    static var description = IntentDescription("Reports how a tracker — or all of them — is doing against its target.")

    @Parameter(title: "Tracker")
    var tracker: TrackerEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trackers: [Tracker]
        if let tracker {
            trackers = try IntentDataStore.fetchTracker(id: tracker.id).map { [$0] } ?? []
        } else {
            let all = try IntentDataStore.fetchAllTrackers()
            let active = all.filter { !$0.isCompleted() }
            trackers = active.isEmpty ? all : active
        }
        guard !trackers.isEmpty else {
            return .result(dialog: "You don't have any trackers yet.")
        }
        let lines = trackers.map { tracker -> String in
            let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
            return "\(tracker.name): \(pace.statusLine(for: tracker)) \(pace.displayDifference(for: tracker))."
        }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: " ")))
    }
}
