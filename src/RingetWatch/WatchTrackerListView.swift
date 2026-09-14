//
//  WatchTrackerListView.swift
//  RingetWatch
//

import SwiftUI
import SwiftData

/// Root watch screen — what someone would actually want at a glance on
/// their wrist: each tracker's name and its ahead/behind figure, in a plain
/// list (no rings here — they belong to the detail view; a list of rings
/// at watch width would be too small to read).
struct WatchTrackerListView: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    var body: some View {
        NavigationStack {
            Group {
                if trackers.isEmpty {
                    ContentUnavailableView(
                        "No Trackers",
                        systemImage: "circle.circle",
                        description: Text("Add a tracker on your iPhone.")
                    )
                } else {
                    List(trackers) { tracker in
                        NavigationLink {
                            WatchTrackerDetailView(tracker: tracker)
                        } label: {
                            WatchTrackerRow(tracker: tracker)
                        }
                    }
                }
            }
            .navigationTitle("Trackers")
        }
    }
}

private struct WatchTrackerRow: View {
    let tracker: Tracker

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tracker.name)
                .font(.headline)
                .lineLimit(1)
            if tracker.latestReading != nil {
                Text(pace.displayDifference(for: tracker))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pace.status.color)
            } else {
                Text("No data yet")
                    .font(.subheadline)
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
