//
//  MacRootView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// macOS main window (§7.2): a `NavigationSplitView` sidebar of trackers
/// with the same dashboard as iOS in the detail pane — the functional
/// structural piece the spec calls for, not a redesign of the dashboard
/// itself (that content is identical to `TrackerDetailView` on iOS).
struct MacRootView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(AppCommands.self) private var appCommands
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    @State private var selection: Tracker.ID?
    @State private var isPresentingAddTracker = false
    #if os(macOS)
    @State private var ticker = AutoUpdateTicker()
    #endif

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
                // Connected Sources moved to the native Settings scene (⌘,,
                // §7.2) — the standard macOS home for this kind of
                // configuration, rather than a bespoke sheet duplicating it.
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
        .onAppear {
            if selection == nil {
                selection = trackers.first?.id
            }
        }
        .onChange(of: appCommands.newTrackerRequestCount) { _, _ in
            isPresentingAddTracker = true
        }
        #if os(macOS)
        .task {
            PaceCrossingNotifier.shared.requestAuthorizationIfNeeded()
        }
        .onAppear {
            ticker.endDatesProvider = { trackers.map(\.endDate) }
            ticker.onUpdate = { _ in refreshPaceDrivenState() }
            ticker.start()
            refreshPaceDrivenState()
        }
        .onChange(of: trackers) { _, _ in
            refreshPaceDrivenState()
        }
        #endif
    }

    #if os(macOS)
    private func refreshPaceDrivenState() {
        PaceCrossingNotifier.shared.checkForCrossings(in: trackers)
        let anyBehindPace = trackers.contains { tracker in
            guard let reading = tracker.latestReading else { return false }
            return tracker.pace(actualValue: reading.value).status != .good
        }
        NSApplication.shared.dockTile.badgeLabel = anyBehindPace ? "!" : nil
    }
    #endif
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
                HStack(spacing: 6) {
                    Text(tracker.name)
                    if tracker.isCompleted() {
                        CompletedBadge()
                    }
                }
                if tracker.latestReading != nil {
                    Text("\(pace.statusLine(for: tracker)) \(pace.displayDifference(for: tracker))")
                        .font(.caption)
                        .foregroundStyle(pace.status.color)
                        .lineLimit(1)
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
