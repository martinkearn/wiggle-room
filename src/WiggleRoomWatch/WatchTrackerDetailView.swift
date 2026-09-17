//
//  WatchTrackerDetailView.swift
//  WiggleRoomWatch
//

import SwiftUI

/// The glanceable detail screen — reuses `RingsView` (identical to the
/// phone) since the two-ring encoding (§3.4) is exactly as useful at watch
/// size as it is on the phone, plus a "Log" action for manual trackers
/// (§7.3's stretch goal, promoted to a real feature since manual entry is
/// the only provider in scope tonight).
struct WatchTrackerDetailView: View {
    @Environment(TrackerStore.self) private var store
    let tracker: Tracker

    @State private var isPresentingLogReading = false
    @State private var ticker = AutoUpdateTicker()
    @State private var isRefreshingFromSource = false

    private var now: Date { ticker.now }

    private func refreshFromSourceIfNeeded() async {
        guard !tracker.isManualEntry, !tracker.isCompleted(asOf: now), !isRefreshingFromSource else { return }
        isRefreshingFromSource = true
        defer { isRefreshingFromSource = false }
        try? await store.refreshFromSource(tracker)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if tracker.isCompleted(asOf: now) {
                    CompletedBadge()
                }

                RingsView(tracker: tracker, now: now, lineWidth: 8)
                    .frame(width: 120, height: 120)

                if !tracker.isCompleted(asOf: now) {
                    if tracker.isManualEntry {
                        Button {
                            isPresentingLogReading = true
                        } label: {
                            Label("Log", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Task { await refreshFromSourceIfNeeded() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRefreshingFromSource)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(tracker.name)
        .onAppear {
            // 30s while this detail screen is on-screen (§5.3) — same
            // cadence and mechanism as the phone/Mac dashboard.
            ticker.interval = 30
            ticker.endDatesProvider = { [tracker.endDate] }
            ticker.onUpdate = { _ in
                Task { await refreshFromSourceIfNeeded() }
            }
            ticker.start()
            Task { await refreshFromSourceIfNeeded() }
        }
        .sheet(isPresented: $isPresentingLogReading) {
            WatchLogReadingView(tracker: tracker)
        }
    }
}

#Preview {
    let tracker = SharedPreviewData.makeSampleTracker()
    return NavigationStack {
        WatchTrackerDetailView(tracker: tracker)
    }
    .modelContainer(SharedPreviewData.container)
    .environment(TrackerStore(modelContext: SharedPreviewData.container.mainContext))
}
