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

    @Parameter(title: "Choose a tracker")
    var tracker: TrackerEntity?

    /// Renders the picker row as "Tracker: <name>" — or "Tracker: Choose a
    /// tracker" while nothing's selected (the parameter's own title is what
    /// the system shows as the unset placeholder).
    static var parameterSummary: some ParameterSummary {
        Summary("Tracker: \(\.$tracker)")
    }
}

/// A Control Center / Lock Screen control: the tracker's name with its
/// under/over figure in the label; tapping opens its dashboard.
struct TrackerStatusControl: ControlWidget {
    struct Value {
        var url: URL
        var name: String
        var status: String
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectTrackerControlIntent) -> Value {
            Value(url: URL(string: "wiggleroom://")!, name: "Tracker", status: "On pace")
        }

        @MainActor
        func currentValue(configuration: SelectTrackerControlIntent) async throws -> Value {
            let trackers = (try? WidgetDataStore.fetchAllTrackersImmediately()) ?? []
            let tracker = configuration.tracker.flatMap { entity in trackers.first { $0.id == entity.id } } ?? trackers.first
            guard let tracker else { return previewValue(configuration: configuration) }
            let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
            return Value(
                url: WiggleRoomDeepLink.url(forTrackerId: tracker.id),
                name: tracker.name,
                status: pace.displayDifference(for: tracker)
            )
        }
    }

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "TrackerStatusControl", provider: Provider()) { value in
            ControlWidgetButton(action: OpenURLIntent(value.url)) {
                Label("\(value.name): \(value.status)", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .displayName("Tracker Status")
        .description("Shows how far over or under target a tracker is. Tap it to open that tracker in Wiggle Room.")
    }
}
#endif
