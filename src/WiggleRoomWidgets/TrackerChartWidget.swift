//
//  TrackerChartWidget.swift
//  WiggleRoomWidgets
//

import SwiftUI
import WidgetKit

/// The trend chart (§3.5) as a widget: actual readings against the pace
/// line, for one configurable tracker — same picker and timeline as
/// `TrackerWidget`, different presentation.
struct TrackerChartWidget: Widget {
    let kind = "TrackerChartWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectTrackerIntent.self, provider: TrackerTimelineProvider()) { entry in
            TrackerChartEntryView(entry: entry)
        }
        .configurationDisplayName("Trend Chart")
        .description("A tracker's readings against its pace line.")
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular])
        #endif
    }
}

struct TrackerChartEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerTimelineEntry

    var body: some View {
        if let tracker = entry.tracker {
            content(for: tracker)
                .widgetURL(WiggleRoomDeepLink.url(forTrackerId: tracker.id))
        } else if entry.isLoading {
            VStack(spacing: 6) {
                EmptyRingsMark(size: 56)
                if !family.isLockScreen { Text("Loading data…").font(.caption).foregroundStyle(.secondary) }
            }
            .unredacted()
            .containerBackground(for: .widget) { Color.widgetBackground }
        } else {
            Text("No Tracker")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    private func pace(_ tracker: Tracker) -> TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: entry.date)
    }

    @ViewBuilder
    private func content(for tracker: Tracker) -> some View {
        switch family {
        #if !os(macOS)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tracker.name)  \(pace(tracker).displayDifference(for: tracker))")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                TrendChartView(tracker: tracker, now: entry.date, showsLegend: false, showsAxes: false)
            }
            .containerBackground(for: .widget) { Color.clear }
        #endif
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header(tracker, nameSize: 12, figure: .caption)
                TrendChartView(tracker: tracker, now: entry.date, showsLegend: false, showsAxes: false)
            }
            .padding()
            .containerBackground(for: .widget) { Color.widgetBackground }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                header(tracker, nameSize: 16, figure: .title3)
                TrendChartView(tracker: tracker, now: entry.date, showsLegend: false, showsAxes: false)
            }
            .padding()
            .containerBackground(for: .widget) { Color.widgetBackground }
        default:
            VStack(alignment: .leading, spacing: 12) {
                header(tracker, nameSize: 20, figure: .title2)
                Text(pace(tracker).statusLine(for: tracker))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TrendChartView(tracker: tracker, now: entry.date)
            }
            .padding()
            .containerBackground(for: .widget) { Color.widgetBackground }
        }
    }

    private func header(_ tracker: Tracker, nameSize: CGFloat, figure: Font.TextStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(tracker.name)
                .font(WiggleRoomFont.headline(nameSize, weight: 650))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if tracker.isCompleted(asOf: entry.date) { CompletedBadge() }
            Spacer(minLength: 4)
            Text(pace(tracker).displayDifference(for: tracker))
                .font(.wiggleNumber(figure, weight: .bold))
                .foregroundStyle(pace(tracker).status.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
