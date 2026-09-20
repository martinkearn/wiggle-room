//
//  WiggleRoomComplicationBundle.swift
//  WiggleRoomComplication
//

import SwiftUI
import WidgetKit

@main
struct WiggleRoomComplicationBundle: WidgetBundle {
    var body: some Widget {
        TrackerComplication()
    }
}

/// The watch face complication called for by §7.3 — shows the ahead/behind
/// figure for a chosen (or default) tracker directly on the watch face.
/// The companion app (`WiggleRoomWatch`) already exists; this is the
/// "second WidgetKit extension embedded inside the watch app target" the
/// build spec notes as the missing piece.
struct TrackerComplication: Widget {
    let kind: String = "TrackerComplication"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectTrackerIntent.self, provider: TrackerComplicationProvider()) { entry in
            TrackerComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Tracker")
        .description("Shows a tracker at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
