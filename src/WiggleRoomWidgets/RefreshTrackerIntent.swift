//
//  RefreshTrackerIntent.swift
//  WiggleRoomWidgets
//

import AppIntents
import Foundation
import WidgetKit

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
              let tracker = try WidgetDataStore.fetchAllTrackersImmediately().first(where: { $0.id == id })
        else {
            RefreshOutcome.record(.failed, for: trackerId)
            return .result()
        }
        let store = TrackerStore(modelContext: try WidgetDataStore.makeContainer().mainContext)
        do {
            let changed = try await store.refreshFromSource(tracker)
            RefreshOutcome.record(changed ? .updated : .unchanged, for: trackerId)
        } catch {
            RefreshOutcome.record(.failed, for: trackerId)
        }
        return .result()
    }
}

/// The last result of a widget refresh tap, kept in the App Group so the
/// widget can show it — a refresh that finds the balance unchanged (or fails)
/// otherwise looks exactly like a button that did nothing.
enum RefreshOutcome: String {
    case updated, unchanged, failed

    private static let defaults = UserDefaults(suiteName: AppGroup.identifier)

    static func record(_ outcome: RefreshOutcome, for trackerId: String) {
        defaults?.set([outcome.rawValue, String(Date.now.timeIntervalSince1970)], forKey: "widgetRefresh.\(trackerId)")
    }

    /// Caption for the widget, or nil if the button hasn't been tapped
    /// recently enough to be worth showing.
    static func caption(for trackerId: UUID, asOf now: Date) -> String? {
        guard let stored = defaults?.stringArray(forKey: "widgetRefresh.\(trackerId.uuidString)"),
              stored.count == 2, let outcome = RefreshOutcome(rawValue: stored[0]),
              let seconds = TimeInterval(stored[1]) else { return nil }
        let when = Date(timeIntervalSince1970: seconds)
        guard now.timeIntervalSince(when) < 3600 else { return nil }
        let time = when.formatted(date: .omitted, time: .shortened)
        switch outcome {
        case .updated: return "Updated \(time)"
        case .unchanged: return "Checked \(time)"
        case .failed: return "Refresh failed"
        }
    }
}
