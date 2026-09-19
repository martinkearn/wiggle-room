//
//  TrackerOrderView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Settings → Tracker Order: choose how the All Trackers list is sorted,
/// or pick Custom and drag trackers into the order you want.
struct TrackerOrderView: View {
    @Environment(TrackerStore.self) private var store
    @Query(sort: \Tracker.startDate, order: .reverse) private var allTrackers: [Tracker]
    @AppStorage(trackerSortOptionKey) private var sortOption = TrackerSortOption.newestFirst.rawValue

    private var option: TrackerSortOption { TrackerSortOption(rawValue: sortOption) ?? .newestFirst }

    var body: some View {
        List {
            Section {
                Picker("Sort By", selection: $sortOption) {
                    ForEach(TrackerSortOption.allCases) { Text($0.label).tag($0.rawValue) }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
            } footer: {
                Text(option == .custom ? "Drag trackers to reorder them. New trackers appear at the top." : "Choose Custom to arrange trackers yourself.")
            }

            if option == .custom {
                Section("Order") {
                    ForEach(option.sorted(allTrackers)) { tracker in
                        Text(tracker.name)
                    }
                    .onMove(perform: move)
                }
            }
        }
        #if os(macOS)
        .frame(minHeight: 300)
        #endif
        .navigationTitle("Tracker Order")
        .inlineNavigationBarIfAvailable()
        #if os(iOS)
        .toolbar { if option == .custom { EditButton() } }
        #endif
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = option.sorted(allTrackers)
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, tracker) in ordered.enumerated() { tracker.sortOrder = index }
        store.saveChanges()
    }
}
