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
                Text("Drag to reorder. Your order syncs across your devices, and new trackers land at the top.")
            }

            Section {
                ForEach(TrackerOrdering.ordered(allTrackers)) { tracker in
                    HStack(spacing: 10) {
                        TrackerBadge(tracker: tracker, size: 28)
                        Text(tracker.name)
                            .font(WiggleRoomFont.headline(16, weight: 650))
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("Order")
                    .font(WiggleRoomFont.headline(15, weight: 650))
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
