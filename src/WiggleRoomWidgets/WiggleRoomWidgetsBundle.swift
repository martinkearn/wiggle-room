//
//  WiggleRoomWidgetsBundle.swift
//  WiggleRoomWidgets
//

import SwiftUI
import WidgetKit

@main
struct WiggleRoomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrackerWidget()
        TrackerChartWidget()
        AllTrackersWidget()
        #if os(iOS)
        TrackerStatusControl()
        TrackerLiveActivityWidget()
        #endif
    }
}

/// One configurable widget definition covering every family we support —
/// Home Screen small/medium/large and Lock Screen circular/rectangular/
/// inline (§8.1, §8.2) — rather than a separate `Widget` per family, since
/// they all share the same configuration (which tracker) and entry data.
struct TrackerWidget: Widget {
    let kind: String = "TrackerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectTrackerIntent.self, provider: TrackerTimelineProvider()) { entry in
            TrackerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tracker")
        .description("Shows a tracker's pace at a glance.")
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        #else
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
        #endif
    }
}
