//
//  AllTrackersWidget.swift
//  WiggleRoomWidgets
//

import SwiftUI
import WidgetKit

struct AllTrackersEntry: TimelineEntry {
    let date: Date
    let trackers: [Tracker]
    var isLoading = false
}

/// No configuration: every tracker, active ones first (then the list's own
/// newest-first order), so the widget always reflects whatever trackers exist.
struct AllTrackersProvider: TimelineProvider {
    @MainActor
    func placeholder(in context: Context) -> AllTrackersEntry {
        AllTrackersEntry(date: .now, trackers: [], isLoading: true)
    }

    @MainActor
    func getSnapshot(in context: Context, completion: @escaping (AllTrackersEntry) -> Void) {
        let trackers = (try? WidgetDataStore.fetchAllTrackersImmediately()) ?? []
        completion(AllTrackersEntry(date: .now, trackers: Self.ordered(trackers), isLoading: trackers.isEmpty))
    }

    @MainActor
    func getTimeline(in context: Context, completion: @escaping (Timeline<AllTrackersEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let trackers = Self.ordered((try? await WidgetDataStore.fetchAllTrackers()) ?? [])
            let soonestEnd = trackers.filter { !$0.isCompleted(asOf: now) }.map(\.endDate).min()
            let next = soonestEnd.map { TrackerUpdateScheduling.nextWidgetReloadDate(after: now, until: $0) }
                ?? now.addingTimeInterval(TrackerUpdateScheduling.defaultWidgetFarInterval)
            completion(Timeline(entries: [AllTrackersEntry(date: now, trackers: trackers)], policy: .after(next)))
        }
    }

    private static func ordered(_ trackers: [Tracker]) -> [Tracker] {
        let now = Date.now
        return trackers.sorted {
            let a = $0.isCompleted(asOf: now), b = $1.isCompleted(asOf: now)
            return a == b ? $0.startDate > $1.startDate : !a
        }
    }
}

struct AllTrackersWidget: Widget {
    let kind = "AllTrackersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AllTrackersProvider()) { entry in
            AllTrackersEntryView(entry: entry)
        }
        .configurationDisplayName("All Trackers")
        .description("Every tracker's rings and ahead/behind figure at a glance.")
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular])
        #endif
    }
}

struct AllTrackersEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AllTrackersEntry

    var body: some View {
        if entry.trackers.isEmpty {
            VStack(spacing: 6) {
                EmptyRingsMark(size: 56)
                if !(entry.isLoading && family.isLockScreen) {
                    Text(entry.isLoading ? "Loading data…" : "No Trackers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .unredacted()
            .containerBackground(for: .widget) { Color.widgetBackground }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        #if !os(macOS)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.trackers.prefix(3)) { tracker in
                    HStack {
                        Text(tracker.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(pace(tracker).displayDifference(for: tracker))
                    }
                    .font(.caption)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        #endif
        case .systemSmall:
            // A small widget takes a single tap target, so no per-tracker links.
            grid(columns: 2, maxCount: 4, ringSize: 44, showsName: false, linksEach: false)
        case .systemMedium:
            grid(columns: 4, maxCount: 4, ringSize: 56, showsName: true, linksEach: true)
        case .systemLarge:
            grid(columns: 3, maxCount: 9, ringSize: 70, showsName: true, linksEach: true)
        default:
            grid(columns: 6, maxCount: 12, ringSize: 80, showsName: true, linksEach: true)
        }
    }

    private func pace(_ tracker: Tracker) -> TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: entry.date)
    }

    private func grid(columns: Int, maxCount: Int, ringSize: CGFloat, showsName: Bool, linksEach: Bool) -> some View {
        let shown = Array(entry.trackers.prefix(maxCount))
        let overflow = entry.trackers.count - shown.count
        return VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 10) {
                ForEach(shown) { tracker in
                    if linksEach {
                        Link(destination: WiggleRoomDeepLink.url(forTrackerId: tracker.id)) {
                            cell(tracker, ringSize: ringSize, showsName: showsName)
                        }
                    } else {
                        cell(tracker, ringSize: ringSize, showsName: showsName)
                    }
                }
            }
            if overflow > 0 {
                Text("+\(overflow) more").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) { Color.widgetBackground }
    }

    private func cell(_ tracker: Tracker, ringSize: CGFloat, showsName: Bool) -> some View {
        let p = pace(tracker)
        return VStack(spacing: 3) {
            RingsView(tracker: tracker, now: entry.date, lineWidth: ringSize / 6, showsCenterContent: false, isAnimated: false)
                .frame(width: ringSize, height: ringSize)
            if showsName {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(11, weight: 600))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
            }
            Text(p.displayDifference(for: tracker))
                .font(.wiggleNumber(.caption2, weight: .bold))
                .foregroundStyle(p.status.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}
