//
//  ReadingHistoryView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Lists every reading logged for a tracker (§4.6 — full history, not just
/// the latest value), newest first. For a manual tracker, rows are
/// tap-to-edit (via `LogReadingView`'s edit mode) and swipe/context-menu to
/// delete; for a real auto-fetch source (Starling), the same list is
/// read-only — a provider's history should reflect what it actually
/// reported, not something the user hand-edits.
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
                    message: tracker.isManualEntry
                        ? "Updates you log will appear here."
                        : "Updates fetched from this source will appear here."
                )
            } else {
                List {
                    ForEach(readingsNewestFirst) { reading in
                        row(for: reading)
                        #if os(macOS)
                        // macOS `List` has no swipe-to-delete gesture and no
                        // `selection:` binding here to drive `EditButton`'s
                        // usual Delete-key path, so a per-row context menu is
                        // the affordance instead.
                        .contextMenu {
                            if tracker.isManualEntry {
                                Button(role: .destructive) {
                                    store.deleteReading(reading)
                                } label: {
                                    Label("Delete Update", systemImage: "trash")
                                }
                            }
                        }
                        #endif
                    }
                    .onDelete(perform: deleteAction)
                }
            }
        }
        .navigationTitle("Update History")
        .inlineNavigationBarIfAvailable()
        .toolbar {
            #if !os(macOS)
            if tracker.isManualEntry && !readingsNewestFirst.isEmpty {
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

    /// A manual tracker's row is tap-to-edit; a real auto-fetch source's
    /// reading is read-only (its provider is the source of truth for what
    /// it reported), so the row is plain text with no tap affordance.
    @ViewBuilder
    private func row(for reading: ValueSnapshot) -> some View {
        if tracker.isManualEntry {
            Button {
                editingReading = reading
            } label: {
                rowContent(for: reading)
            }
        } else {
            rowContent(for: reading)
        }
    }

    private func rowContent(for reading: ValueSnapshot) -> some View {
        HStack {
            Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.primary)
            Spacer()
            Text(tracker.formattedValue(reading.value))
                .foregroundStyle(.secondary)
                .font(.wiggleNumber(.body))
        }
    }

    /// `nil` for a real auto-fetch source — no swipe-to-delete affordance at
    /// all. Broken out as its own explicitly-typed property (rather than an
    /// inline ternary at the `.onDelete(perform:)` call site) since a
    /// ternary mixing a function reference and `nil` there is a known
    /// trigger for a Swift type-checker crash ("Failed to produce
    /// diagnostic for expression").
    private var deleteAction: ((IndexSet) -> Void)? {
        guard tracker.isManualEntry else { return nil }
        return deleteReadings
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
