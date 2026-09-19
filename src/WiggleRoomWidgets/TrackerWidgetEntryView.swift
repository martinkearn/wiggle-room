//
//  TrackerWidgetEntryView.swift
//  WiggleRoomWidgets
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
                .widgetURL(WiggleRoomDeepLink.url(forTrackerId: tracker.id))
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
        case .systemExtraLarge:
            extraLargeHomeScreen(tracker)
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

    /// A subtle corner mark — a stand-in for a proper transparent-background
    /// logo (none exists yet) using the existing tinted app icon at reduced
    /// opacity/size, so it reads as a quiet brand touch rather than
    /// competing with the tracker's own figures.
    private var brandMark: some View {
        Image("WiggleRoomMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(Circle())
            .opacity(0.4)
    }

    private func smallHomeScreen(_ tracker: Tracker) -> some View {
        VStack(spacing: 6) {
            RingsView(tracker: tracker, now: entry.date, lineWidth: 10, showsCenterContent: false, isAnimated: false)
                .frame(width: 60, height: 60)
            HStack(spacing: 4) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(12, weight: 650))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if tracker.isCompleted(asOf: entry.date) {
                    CompletedBadge()
                }
            }
            .frame(maxWidth: .infinity)
            Text(pace(for: tracker).displayDifference(for: tracker))
                .font(.wiggleNumber(.caption, weight: .bold))
                .foregroundStyle(pace(for: tracker).status.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    private func mediumHomeScreen(_ tracker: Tracker) -> some View {
        HStack(spacing: 16) {
            RingsView(tracker: tracker, now: entry.date, lineWidth: 10, showsCenterContent: false, isAnimated: false)
                .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tracker.name)
                        .font(WiggleRoomFont.headline(16, weight: 650))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if tracker.isCompleted(asOf: entry.date) {
                        CompletedBadge()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(pace(for: tracker).statusLine(for: tracker))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pace(for: tracker).displayDifference(for: tracker))
                    .font(.wiggleNumber(.title3, weight: .bold))
                    .foregroundStyle(pace(for: tracker).status.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding()
        .overlay(alignment: .topTrailing) {
            brandMark.frame(width: 18, height: 18).padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            // Interactive widget: fetch a connected tracker's value now,
            // without opening the app. Manual trackers have no source to
            // fetch from, so they get no button.
            if !tracker.isManualEntry, !tracker.isCompleted(asOf: entry.date) {
                Button(intent: RefreshTrackerIntent(trackerId: tracker.id)) {
                    Image(systemName: "arrow.clockwise").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(10)
            }
        }
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    /// The large widget has real room to work with, but `RingsView`'s
    /// default center content/legend are sized for the ~260pt phone
    /// dashboard — reused verbatim here they overflowed and overlapped at
    /// this size. Instead: a bare ring (`showsCenterContent: false`) stays
    /// the primary visual, with the status/difference and the Current
    /// Balance/Target figures laid out as their own rows below/beside it,
    /// mirroring the phone dashboard's own card layout rather than trying
    /// to squeeze everything inside the ring itself.
    private func largeHomeScreen(_ tracker: Tracker) -> some View {
        let p = pace(for: tracker)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(20, weight: 650))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if tracker.isCompleted(asOf: entry.date) {
                    CompletedBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                RingsView(tracker: tracker, now: entry.date, lineWidth: 14, showsCenterContent: false, isAnimated: false)
                    .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 4) {
                    Text(p.statusLine(for: tracker).uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(p.status.color)
                    Text(p.displayDifference(for: tracker))
                        .font(.wiggleNumber(size: 30, weight: .bold))
                        .foregroundStyle(p.status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("difference from target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                widgetFigure(title: tracker.currentValueLabel, value: tracker.formattedValue(p.currentValue), color: p.status.color)
                widgetFigure(title: "Target Right Now", value: tracker.formattedValue(p.targetValueToday), color: .primary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            brandMark.frame(width: 20, height: 20).padding(12)
        }
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    private func widgetFigure(title: String, value: String, color: Color, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.wiggleNumber(.subheadline))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The extra-large family (iOS/iPadOS/macOS 27) has enough room to
    /// mirror the phone dashboard (`TrackerDetailView`) almost directly,
    /// rather than the large widget's more compact reinterpretation above —
    /// full-size rings with their own center content/legend, both figure
    /// cards with their captions, and the days-remaining line.
    private func extraLargeHomeScreen(_ tracker: Tracker) -> some View {
        let p = pace(for: tracker)
        let isCompleted = tracker.isCompleted(asOf: entry.date)
        return VStack(spacing: 20) {
            HStack(spacing: 8) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(24, weight: 650))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isCompleted {
                    CompletedBadge()
                }
            }
            .frame(maxWidth: .infinity)

            RingsView(tracker: tracker, now: entry.date, lineWidth: 20, isAnimated: false)
                .frame(width: 220, height: 220)

            if isCompleted {
                widgetFigure(
                    title: "Final \(tracker.currentValueLabel)",
                    value: tracker.formattedValue(p.currentValue),
                    color: p.status.color,
                    caption: "\(p.statusLine(for: tracker)) \(p.displayDifference(for: tracker))"
                )
            } else {
                HStack(spacing: 16) {
                    widgetFigure(
                        title: tracker.currentValueLabel,
                        value: tracker.formattedValue(p.currentValue),
                        color: p.status.color,
                        caption: p.remainingInAllowanceCaption(for: tracker)
                    )
                    widgetFigure(
                        title: "Target Right Now",
                        value: tracker.formattedValue(p.targetValueToday),
                        color: .primary,
                        caption: "Final target will be \(tracker.formattedValue(tracker.projectedFinalValue))"
                    )
                }
            }

            Text(tracker.periodRemainingText(asOf: entry.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            brandMark.frame(width: 24, height: 24).padding(14)
        }
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
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(p.displayDifference(for: tracker))
                .font(.wiggleNumber(.caption))
            Text(tracker.isCompleted(asOf: entry.date) ? "Completed" : p.statusLine(for: tracker))
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
