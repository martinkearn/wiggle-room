//
//  ReadingHistoryView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Lists every reading logged for a manual tracker (§4.6 — full history, not
/// just the latest value), newest first, with swipe-to-delete and tap-to-edit
/// via `LogReadingView`'s edit mode. Only reachable for manual trackers
/// (`Tracker.isManualEntry`) — a real provider's history should reflect what
/// it actually reported, not something the user hand-edits.
struct ReadingHistoryView: View {
    @Environment(TrackerStore.self) private var store
    let tracker: Tracker

    @State private var editingReading: ValueSnapshot?

    private var readingsNewestFirst: [ValueSnapshot] {
        tracker.sortedReadings.reversed()
    }

    var body: some View {
        Group {
            if readingsNewestFirst.isEmpty {
                WiggleEmptyState(
                    symbol: "clock",
                    title: "No Updates Yet",
                    message: "Updates you log will appear here."
                )
            } else {
                List {
                    ForEach(readingsNewestFirst) { reading in
                        Button {
                            editingReading = reading
                        } label: {
                            HStack {
                                Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(tracker.formattedValue(reading.value))
                                    .foregroundStyle(.secondary)
                                    .font(.wiggleNumber(.body))
                            }
                        }
                    }
                    .onDelete(perform: deleteReadings)
                }
            }
        }
        .navigationTitle("Update History")
        .inlineNavigationBarIfAvailable()
        .toolbar {
            #if !os(macOS)
            if !readingsNewestFirst.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            #endif
        }
        .sheet(item: $editingReading) { reading in
            LogReadingView(tracker: tracker, existingReading: reading)
        }
    }

    private func deleteReadings(at offsets: IndexSet) {
        for index in offsets {
            store.deleteReading(readingsNewestFirst[index])
        }
    }
}

#Preview {
    NavigationStack {
        ReadingHistoryView(tracker: PreviewData.makeSampleTracker())
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
}
