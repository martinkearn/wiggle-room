//
//  TrackerComplicationEntryView.swift
//  WiggleRoomComplication
//

import SwiftUI
import WidgetKit

/// Renders one tracker's pace as a watch face complication (§7.3) — the
/// same three accessory families already proven out for the iOS Lock
/// Screen in `WiggleRoomWidgets` (`.accessoryCircular` is literally the
/// same family shown on both surfaces), styled identically here so a
/// tracker reads the same way whether it's on the wrist or the Lock Screen.
struct TrackerComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrackerComplicationEntry

    var body: some View {
        bodyContent
            .font(.wiggleText(.body))
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let tracker = entry.tracker {
            content(for: tracker)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(for tracker: Tracker) -> some View {
        switch family {
        case .accessoryRectangular:
            rectangular(tracker)
        case .accessoryInline:
            inline(tracker)
        default:
            circular(tracker)
        }
    }

    private var emptyState: some View {
        EmptyRingsMark(size: 32)
            .containerBackground(for: .widget) { Color.clear }
    }

    private func pace(for tracker: Tracker) -> TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: entry.date)
    }

    private func circular(_ tracker: Tracker) -> some View {
        let p = pace(for: tracker)
        let fraction = p.periodHours > 0 ? min(max(p.hoursElapsed / p.periodHours, 0), 1) : 0
        return WobblyGauge(fraction: fraction, color: p.status.color) {
            Text(p.displayDifference(for: tracker))
                .font(.wiggleNumber(.caption2))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func rectangular(_ tracker: Tracker) -> some View {
        let p = pace(for: tracker)
        return HStack(spacing: 8) {
            RingsView(tracker: tracker, now: entry.date, lineWidth: 5, showsCenterContent: false, isAnimated: false)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(12, weight: 650))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(p.displayDifference(for: tracker))
                    .font(.wiggleNumber(.title3))
                    .foregroundStyle(p.status.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func inline(_ tracker: Tracker) -> some View {
        Text("\(tracker.name): \(pace(for: tracker).displayDifference(for: tracker))")
            .containerBackground(for: .widget) { Color.clear }
    }
}
