//
//  MacRootView.swift
//  Ringet
//

import SwiftUI
import SwiftData

/// macOS main window (§7.2): a `NavigationSplitView` sidebar of trackers
/// with the same dashboard as iOS in the detail pane — the functional
/// structural piece the spec calls for, not a redesign of the dashboard
/// itself (that content is identical to `TrackerDetailView` on iOS).
struct MacRootView: View {
    @Environment(TrackerStore.self) private var store
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    @State private var selection: Tracker.ID?
    @State private var isPresentingAddTracker = false
    @State private var isPresentingSources = false

    var body: some View {
        NavigationSplitView {
            Group {
                if trackers.isEmpty {
                    ContentUnavailableView(
                        "No Trackers Yet",
                        systemImage: "circle.circle",
                        description: Text("Add a tracker to start tracking pace against a target.")
                    )
                } else {
                    List(trackers, selection: $selection) { tracker in
                        MacTrackerRow(tracker: tracker)
                            .tag(tracker.id)
                    }
                }
            }
            .navigationTitle("Trackers")
            .toolbar {
                ToolbarItem {
                    Button {
                        isPresentingSources = true
                    } label: {
                        Label("Connected Sources", systemImage: "gearshape")
                    }
                }
                ToolbarItem {
                    Button {
                        isPresentingAddTracker = true
                    } label: {
                        Label("Add Tracker", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selectedTracker = trackers.first(where: { $0.id == selection }) {
                TrackerDetailView(tracker: selectedTracker)
            } else {
                ContentUnavailableView(
                    "No Tracker Selected",
                    systemImage: "circle.circle",
                    description: Text("Choose a tracker from the sidebar.")
                )
            }
        }
        .sheet(isPresented: $isPresentingAddTracker) {
            AddTrackerView()
        }
        .sheet(isPresented: $isPresentingSources) {
            ConnectedSourcesView()
        }
        .onAppear {
            if selection == nil {
                selection = trackers.first?.id
            }
        }
    }
}

private struct MacTrackerRow: View {
    let tracker: Tracker

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
    }

    var body: some View {
        HStack(spacing: 10) {
            RingsView(tracker: tracker, now: .now, lineWidth: 4, showsCenterContent: false)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tracker.name)
                if tracker.latestReading != nil {
                    Text(pace.displayDifference(for: tracker))
                        .font(.caption)
                        .foregroundStyle(pace.status.color)
                } else {
                    Text("No data yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    MacRootView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
