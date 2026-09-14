//
//  TrackerWidgetEntryView.swift
//  RingetWidgets
//

import SwiftUI
import WidgetKit

/// Renders one tracker's pace across every supported widget family, reusing
/// `RingsView` (shared with the main app) rather than a bespoke widget-only
/// visual — the two-ring encoding (§3.4) is the whole point of an at-a-glance
/// surface like this.
struct TrackerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerTimelineEntry

    var body: some View {
        if let tracker = entry.tracker {
            content(for: tracker)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(for tracker: Tracker) -> some View {
        switch family {
        case .systemMedium:
            mediumHomeScreen(tracker)
        case .systemLarge:
            largeHomeScreen(tracker)
        #if !os(macOS)
        case .accessoryCircular:
            circularLockScreen(tracker)
        case .accessoryRectangular:
            rectangularLockScreen(tracker)
        case .accessoryInline:
            inlineLockScreen(tracker)
        #endif
        default:
            smallHomeScreen(tracker)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
            Text("No Tracker")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func pace(for tracker: Tracker) -> TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: entry.date)
    }

    private func smallHomeScreen(_ tracker: Tracker) -> some View {
        VStack(spacing: 6) {
            RingsView(tracker: tracker, now: entry.date, lineWidth: 10, showsCenterContent: false)
                .frame(width: 60, height: 60)
            Text(tracker.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(pace(for: tracker).displayDifference(for: tracker))
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(pace(for: tracker).status.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    private func mediumHomeScreen(_ tracker: Tracker) -> some View {
        HStack(spacing: 16) {
            RingsView(tracker: tracker, now: entry.date, lineWidth: 10, showsCenterContent: false)
                .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(pace(for: tracker).status.label(for: tracker))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pace(for: tracker).displayDifference(for: tracker))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(pace(for: tracker).status.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    private func largeHomeScreen(_ tracker: Tracker) -> some View {
        VStack(spacing: 12) {
            Text(tracker.name)
                .font(.headline)
                .lineLimit(1)
            RingsView(tracker: tracker, now: entry.date)
                .frame(width: 160, height: 160)
        }
        .padding()
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    #if !os(macOS)
    private func circularLockScreen(_ tracker: Tracker) -> some View {
        let p = pace(for: tracker)
        let fraction = p.periodHours > 0 ? min(max(p.hoursElapsed / p.periodHours, 0), 1) : 0
        return Gauge(value: fraction) {
            Text(tracker.name.prefix(1))
        } currentValueLabel: {
            Text(tracker.name.prefix(3))
                .font(.system(size: 10))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func rectangularLockScreen(_ tracker: Tracker) -> some View {
        let p = pace(for: tracker)
        return VStack(alignment: .leading, spacing: 2) {
            Text(tracker.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(p.displayDifference(for: tracker))
                .font(.caption.monospacedDigit())
            Text(p.status.label(for: tracker))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func inlineLockScreen(_ tracker: Tracker) -> some View {
        Text("\(tracker.name): \(pace(for: tracker).displayDifference(for: tracker))")
            .containerBackground(for: .widget) { Color.clear }
    }
    #endif
}
