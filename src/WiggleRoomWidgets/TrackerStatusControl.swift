//
//  TrackerStatusControl.swift
//  WiggleRoomWidgets
//

#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

struct SelectTrackerControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a Tracker"
    static var description = IntentDescription("Choose which tracker this control shows.")

    @Parameter(title: "Tracker", default: TrackerEntity.placeholder)
    var tracker: TrackerEntity?

}

/// A Control Center / Lock Screen control: the tracker's name with its
/// under/over figure in the label; tapping opens its dashboard.
struct TrackerStatusControl: ControlWidget {
    struct Value {
        var url: URL
        var name: String
        var status: String
        var glyph: String = "chart.line.uptrend.xyaxis"
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectTrackerControlIntent) -> Value {
            Value(url: URL(string: "wiggleroom://")!, name: "Tracker", status: "On pace")
        }

        @MainActor
        func currentValue(configuration: SelectTrackerControlIntent) async throws -> Value {
            let trackers = (try? WidgetDataStore.fetchAllTrackersImmediately()) ?? []
            let tracker = TrackerEntity.selectedId(configuration.tracker).flatMap { id in trackers.first { $0.id == id } } ?? trackers.first
            guard let tracker else { return previewValue(configuration: configuration) }
            let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
            return Value(
                url: WiggleRoomDeepLink.url(forTrackerId: tracker.id),
                name: tracker.name,
                status: pace.displayDifference(for: tracker),
                glyph: tracker.glyphSymbol
            )
        }
    }

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "TrackerStatusControl", provider: Provider()) { value in
            ControlWidgetButton(action: OpenURLIntent(value.url)) {
                Label("\(value.name): \(value.status)", systemImage: value.glyph)
            }
        }
        .displayName("Tracker Status")
        .description("Shows how far over or under budget a tracker is. Tap it to open that tracker in Wiggle Room.")
    }
}
#endif
