//
//  TrackerListView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Root screen listing all trackers. See spec §7.1.
struct TrackerListView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    @State private var isPresentingAddTracker = false
    @State private var isPresentingSources = false

    var body: some View {
        NavigationStack {
            Group {
                if trackers.isEmpty {
                    EmptyTrackersView(isPresentingAddTracker: $isPresentingAddTracker)
                } else {
                    List {
                        ForEach(trackers) { tracker in
                            NavigationLink {
                                TrackerDetailView(tracker: tracker)
                            } label: {
                                TrackerRow(tracker: tracker)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .onDelete(perform: deleteTrackers)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Trackers")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        isPresentingSources = true
                    } label: {
                        Label("Connected Sources", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddTracker = true
                    } label: {
                        Label("Add Tracker", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddTracker) {
                AddTrackerView()
            }
            .sheet(isPresented: $isPresentingSources) {
                ConnectedSourcesView()
            }
        }
    }

    private func deleteTrackers(at offsets: IndexSet) {
        for index in offsets {
            store.deleteTracker(trackers[index])
        }
    }
}

/// A single row: name plus a small ring-based pace indicator and the
/// difference from target — the key at-a-glance number (§3.2, §7.1). Styled
/// as its own soft card, tinted a whisper of the tracker's status color, so
/// the list reads as a stack of little dashboards rather than a plain table.
private struct TrackerRow: View {
    let tracker: Tracker

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: .now)
    }

    private var status: PaceStatus {
        pace.status
    }

    var body: some View {
        HStack(spacing: 14) {
            RingsView(tracker: tracker, now: .now, lineWidth: 6, showsCenterContent: false)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(18, weight: 650))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if tracker.latestReading != nil {
                    Text("\(pace.statusLine(for: tracker)) \(pace.displayDifference(for: tracker))")
                        .font(.wiggleNumber(.subheadline))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("No data yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(status.color.opacity(0.16), lineWidth: 1)
        )
    }
}

/// A hand-drawn-feeling empty state — three overlapping rings rather
/// than a single generic SF Symbol, echoing the app's own ring motif so
/// even the "nothing here yet" moment feels like Wiggle Room rather than a
/// stock `ContentUnavailableView`.
private struct EmptyTrackersView: View {
    @Binding var isPresentingAddTracker: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(WiggleRoomColors.brand.opacity(0.35), lineWidth: 10)
                    .frame(width: 132, height: 132)
                Circle()
                    .stroke(WiggleRoomColors.brandWarm.opacity(0.5), lineWidth: 10)
                    .frame(width: 92, height: 92)
                Circle()
                    .stroke(WiggleRoomColors.good.opacity(0.6), lineWidth: 8)
                    .frame(width: 52, height: 52)
            }
            .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text("No Trackers Yet")
                    .font(WiggleRoomFont.headline(26))
                Text("Wiggle Room only works once it has something to watch the pace of.")
                    .font(WiggleRoomFont.aside(16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                isPresentingAddTracker = true
            } label: {
                Label("Add a Tracker", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(WiggleRoomColors.brand)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    TrackerListView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
