//
//  TrackerListView.swift
//  Ringet
//

import SwiftUI

/// Root screen listing all trackers. See spec §7.1.
struct TrackerListView: View {
    @Environment(TrackerStore.self) private var store
    @State private var isPresentingAddTracker = false
    @State private var isPresentingSources = false

    var body: some View {
        NavigationStack {
            Group {
                if store.trackers.isEmpty {
                    ContentUnavailableView(
                        "No Trackers Yet",
                        systemImage: "circle.circle",
                        description: Text("Add a tracker to start tracking pace against a target.")
                    )
                } else {
                    List(store.trackers) { tracker in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tracker.name)
                                .font(.headline)
                            Text("\(tracker.unit) · \(tracker.direction == .decreasing ? "Decreasing" : "Increasing")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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
}

#Preview {
    TrackerListView()
        .environment(TrackerStore())
}
