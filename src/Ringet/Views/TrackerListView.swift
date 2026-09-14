//
//  TrackerListView.swift
//  Ringet
//

import SwiftUI
import SwiftData

/// Root screen listing all trackers. See spec §7.1.
struct TrackerListView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    @State private var isPresentingAddTracker = false
    @State private var isPresentingSources = false

    var body: some View {
        NavigationStack {
            Group {
                if trackers.isEmpty {
                    ContentUnavailableView(
                        "No Trackers Yet",
                        systemImage: "circle.circle",
                        description: Text("Add a tracker to start tracking pace against a target.")
                    )
                } else {
                    List {
                        ForEach(trackers) { tracker in
                            NavigationLink {
                                TrackerDetailView(tracker: tracker)
                            } label: {
                                TrackerRow(tracker: tracker)
                            }
                        }
                        .onDelete(perform: deleteTrackers)
                    }
                }
            }
            .navigationTitle("Trackers")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        isPresentingSources = true
                    } label: {
                        Label("Connected Sources", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddTracker = true
                    } label: {
                        Label("Add Tracker", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddTracker) {
                AddTrackerView()
            }
            .sheet(isPresented: $isPresentingSources) {
                ConnectedSourcesView()
            }
        }
    }

    private func deleteTrackers(at offsets: IndexSet) {
        for index in offsets {
            store.deleteTracker(trackers[index])
        }
    }
}

/// A single row: name plus a small ring-based pace indicator and the
/// difference from target — the key at-a-glance number (§3.2, §7.1).
private struct TrackerRow: View {
    let tracker: Tracker

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: .now)
    }

    private var status: PaceStatus {
        pace.status
    }

    var body: some View {
        HStack(spacing: 12) {
            RingsView(tracker: tracker, now: .now, lineWidth: 5, showsCenterContent: false)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.name)
                    .font(.headline)
                if tracker.latestReading != nil {
                    Text(tracker.formattedValue(pace.difference, signed: true))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.color)
                } else {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TrackerListView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
