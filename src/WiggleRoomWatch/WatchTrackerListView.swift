//
//  WatchTrackerListView.swift
//  WiggleRoomWatch
//

import SwiftUI
import SwiftData

/// Root watch screen — what someone would actually want at a glance on
/// their wrist: each tracker's name and its ahead/behind figure, in a plain
/// list (no rings here — they belong to the detail view; a list of rings
/// at watch width would be too small to read).
struct WatchTrackerListView: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var allTrackers: [Tracker]
    private var trackers: [Tracker] { TrackerOrdering.ordered(allTrackers) }

    var body: some View {
        NavigationStack {
            Group {
                if trackers.isEmpty {
                    VStack(spacing: 8) {
                        EmptyRingsMark(size: 64)
                        Text("No Trackers")
                            .font(WiggleRoomFont.headline(17, weight: 650))
                        Text("Add a tracker on your iPhone.")
                            .font(.wiggleText(.footnote))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            Text("Trackers")
                                .font(WiggleRoomFont.headline(24, weight: 700))
                                .foregroundStyle(WiggleRoomColors.brand)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                            ForEach(trackers) { tracker in
                                NavigationLink {
                                    WatchTrackerDetailView(tracker: tracker)
                                } label: {
                                    WatchTrackerRow(tracker: tracker)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            WobblyCard.shape(0, scale: 0.7)
                                                .fill(tracker.accentColor.opacity(0.24))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
        }
    }
}

private struct WatchTrackerRow: View {
    let tracker: Tracker

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
    }

    var body: some View {
        HStack(spacing: 8) {
            TrackerBadge(tracker: tracker, size: 32)
            rowText
        }
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(17, weight: 650))
                    .lineLimit(1)
                if tracker.isCompleted() {
                    CompletedBadge()
                }
            }
            if tracker.latestReading != nil {
                Text(pace.displayDifference(for: tracker))
                    .font(.wiggleText(.subheadline, weight: .semibold))
                    .foregroundStyle(pace.status.color)
            } else {
                Text("No data yet")
                    .font(.wiggleText(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SharedPreviewData.makeSampleTracker()
    return WatchTrackerListView()
        .modelContainer(SharedPreviewData.container)
}
