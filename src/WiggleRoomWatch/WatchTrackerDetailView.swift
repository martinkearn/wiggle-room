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

    private var now: Date { ticker.now }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if tracker.isCompleted(asOf: now) {
                    CompletedBadge()
                }

                RingsView(tracker: tracker, now: now, lineWidth: 8)
                    .frame(width: 120, height: 120)

                if tracker.isManualEntry && !tracker.isCompleted(asOf: now) {
                    Button {
                        isPresentingLogReading = true
                    } label: {
                        Label("Log", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(tracker.name)
        .onAppear {
            ticker.endDatesProvider = { [tracker.endDate] }
            ticker.start()
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
