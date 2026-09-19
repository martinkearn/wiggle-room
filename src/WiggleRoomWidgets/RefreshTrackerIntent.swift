//
//  RefreshTrackerIntent.swift
//  WiggleRoomWidgets
//

import AppIntents
import Foundation

/// The tap action behind the refresh button on a Home Screen widget
/// (interactive widget) for a connected-source tracker: fetches its current
/// value now instead of waiting for the next timeline reload, without opening
/// the app. Runs in the widget extension's own process.
struct RefreshTrackerIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Tracker"

    @Parameter(title: "Tracker ID")
    var trackerId: String

    init() {}

    init(trackerId: UUID) {
        self.trackerId = trackerId.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: trackerId),
              let tracker = try await WidgetDataStore.fetchTracker(id: id) else { return .result() }
        let store = TrackerStore(modelContext: try WidgetDataStore.makeContainer().mainContext)
        // A rate-limit/network failure just leaves the old value showing.
        _ = try? await store.refreshFromSource(tracker)
        return .result()
    }
}
