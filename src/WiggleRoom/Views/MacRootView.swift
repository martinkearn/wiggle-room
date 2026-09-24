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
    @Query(sort: \Tracker.startDate, order: .reverse) private var allTrackers: [Tracker]
    private var trackers: [Tracker] { TrackerOrdering.ordered(allTrackers) }

    @State private var selection: Tracker.ID?
    @State private var isPresentingAddTracker = false

    var body: some View {
        NavigationSplitView {
            Group {
                if trackers.isEmpty {
                    WiggleEmptyState(
                        symbol: "plus",
                        title: "No Trackers Yet",
                        message: "Add a tracker to see how you're pacing against its target.",
                        actionTitle: "Add a Tracker",
                        action: { isPresentingAddTracker = true }
                    )
                } else {
                    // Explicit `List(selection:) { ... }` content rather
                    // than `List(trackers, selection:)` — needed to prepend
                    // the "Add Tracker" row below, which isn't a `Tracker`
                    // and (deliberately) carries no `.tag`, so it never
                    // participates in `selection` at all.
                    List(selection: $selection) {
                        // Top of the sidebar, not the toolbar — always
                        // visible without scrolling, and newly created
                        // trackers sort to the top anyway (`\Tracker
                        // .startDate, order: .reverse`), so this is exactly
                        // where a just-added tracker will actually appear.
                        AddTrackerRow {
                            isPresentingAddTracker = true
                        }

                        ForEach(trackers) { tracker in
                            MacTrackerRow(tracker: tracker)
                                .tag(tracker.id)
                                // A delete path that doesn't depend on
                                // `selection` at all — operates directly on
                                // this row's own `tracker` reference from the
                                // `trackers` array, not on whatever `selection`
                                // currently holds. Exists specifically for the
                                // case `List(selection:)`'s own tap-to-select
                                // silently fails to register (seen in practice
                                // after a store-level data issue left two rows
                                // with ambiguous identity — selection could
                                // never be confirmed for either, so there was
                                // no other way to remove them from the UI).
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.deleteTracker(tracker)
                                    } label: {
                                        Label("Delete Tracker", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Trackers")
            .toolbar(removing: .title)
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Trackers")
                    .font(WiggleRoomFont.headline(22, weight: 700))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        } detail: {
            if let selectedTracker = trackers.first(where: { $0.id == selection }) {
                TrackerDetailView(tracker: selectedTracker)
            } else {
                WiggleEmptyState(
                    symbol: "sidebar.left",
                    title: "No Tracker Selected",
                    message: "Choose a tracker from the sidebar."
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
            refreshPaceDrivenState()
        }
        .onChange(of: PaceClock.shared.tickCount) { _, _ in
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

/// The "Add Tracker" entry point, styled to echo `MacTrackerRow`'s shape
/// (same ring size/spacing) rather than a plain row — replaces the old
/// toolbar "+" button entirely. A dashed ring with a "+" in place of a
/// real pace ring, and brand-tinted text, distinguish it from an actual
/// tracker row at a glance. Deliberately not selectable — no `.tag`, so it
/// never becomes a `NavigationSplitView` selection.
private struct AddTrackerRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    IconRingShape(ring: .outer, fitsRect: true)
                        .stroke(WiggleRoomColors.brand.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
                        .padding(2/2)
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.wiggleText(size: 11, weight: .semibold))
                        .foregroundStyle(WiggleRoomColors.brand)
                }
                Text("Add Tracker")
                    .foregroundStyle(WiggleRoomColors.brand)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct MacTrackerRow: View {
    let tracker: Tracker
    private var now: Date { PaceClock.shared.now }

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    var body: some View {
        HStack(spacing: 10) {
            TrackerBadge(tracker: tracker, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tracker.name)
                        .font(WiggleRoomFont.headline(15, weight: 650))
                    if tracker.isCompleted(asOf: now) {
                        CompletedBadge()
                    }
                }
                if tracker.latestReading != nil {
                    Text("\(pace.statusLine(for: tracker)) \(pace.displayDifference(for: tracker))")
                        .font(.wiggleText(.caption))
                        .foregroundStyle(pace.status.color)
                        .lineLimit(1)
                } else {
                    Text("No data yet")
                        .font(.wiggleText(.caption))
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
