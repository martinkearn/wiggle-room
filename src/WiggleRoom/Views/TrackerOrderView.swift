//
//  TrackerOrderView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Settings → Tracker Order: arrange the All Trackers list with a preset
/// and/or by dragging. The order is stored on each tracker
/// (`Tracker.sortOrder`) so it syncs to every device.
struct TrackerOrderView: View {
    @Environment(TrackerStore.self) private var store
    @Query(sort: \Tracker.startDate, order: .reverse) private var allTrackers: [Tracker]

    var body: some View {
        List {
            Section {
                Menu("Arrange By…") {
                    ForEach(TrackerArrangement.allCases) { arrangement in
                        Button(arrangement.label) { apply(arrangement.sorted(allTrackers)) }
                    }
                }
            } footer: {
                Text("Drag trackers to set your own order. It syncs to all your devices. New trackers appear at the top.")
            }

            Section("Order") {
                ForEach(TrackerOrdering.ordered(allTrackers)) { tracker in
                    Text(tracker.name)
                }
                .onMove(perform: move)
            }
        }
        #if os(macOS)
        .frame(minHeight: 300)
        #endif
        .navigationTitle("Tracker Order")
        .inlineNavigationBarIfAvailable()
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = TrackerOrdering.ordered(allTrackers)
        ordered.move(fromOffsets: source, toOffset: destination)
        apply(ordered)
    }

    private func apply(_ ordered: [Tracker]) {
        for (index, tracker) in ordered.enumerated() { tracker.sortOrder = index }
        store.saveChanges()
    }
}
