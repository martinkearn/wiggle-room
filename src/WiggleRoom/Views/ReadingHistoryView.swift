//
//  ReadingHistoryView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Lists every reading logged for a tracker (§4.6 — full history, not just
/// the latest value), newest first. Every tracker supports adding manual
/// updates and editing or deleting existing updates, including values fetched
/// from a connected source.
struct ReadingHistoryView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker

    @State private var isPresentingNewReading = false
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
                        : "Updates fetched from this source will show up here."
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
                            Button(role: .destructive) {
                                store.deleteReading(reading)
                            } label: {
                                Label("Delete Update", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                    .onDelete(perform: deleteReadings)
                }
                .listStyle(.plain)
                #if os(macOS)
                // Line the rows up with the sheet's left-aligned title
                // (`leadingSheetTitle`'s 30pt inset) rather than sitting
                // almost flush with the sheet edge.
                .padding(.horizontal, 22)
                #endif
            }
        }
        // Explicit minimum size — this sheet has no other view establishing
        // one (unlike, say, `SettingsRootView`'s fixed window size), and
        // `WiggleEmptyState`'s Spacer-driven layout has no intrinsic height
        // of its own to propose; on macOS specifically, a `Group`/`if-else`
        // with no size hint at all can size a sheet down to something that
        // renders its content invisibly small rather than visibly empty.
        .frame(minWidth: 360, minHeight: 320)
        .navigationTitle("Balance History")
        .leadingSheetTitle("Balance History")
        .inlineNavigationBarIfAvailable()
        .toolbar {
            // This sheet's only other dismissal was swipe-down — not
            // obvious, per Apple's own HIG ("provide a visible way to
            // dismiss a sheet, don't rely on the swipe gesture alone"),
            // and macOS had no equivalent gesture at all. A trailing
            // "Done" matches how a plain browsable list (not a form with
            // its own Save) is conventionally dismissed on both platforms.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isPresentingNewReading = true
                } label: {
                    Label("Add Manual Update", systemImage: "plus")
                }
                #if !os(macOS)
                if !readingsNewestFirst.isEmpty {
                    EditButton()
                }
                #endif
            }
        }
        .sheet(isPresented: $isPresentingNewReading) {
            LogReadingView(tracker: tracker)
        }
        .sheet(item: $editingReading) { reading in
            LogReadingView(tracker: tracker, existingReading: reading)
        }
    }

    private func row(for reading: ValueSnapshot) -> some View {
        Button {
            editingReading = reading
        } label: {
            rowContent(for: reading)
        }
    }

    private func rowContent(for reading: ValueSnapshot) -> some View {
        HStack(spacing: 10) {
            BlobShape(seed: Double(tracker.resolvedColorIndex))
                .fill(tracker.accentColor)
                .frame(width: 10, height: 10)
            Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.primary)
            Spacer()
            Text(tracker.formattedValue(reading.value))
                .foregroundStyle(.secondary)
                .font(.wiggleNumber(.body))
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
