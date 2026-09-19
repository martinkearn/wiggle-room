//
//  TrackerListView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// A tracker referenced by id in `TrackerListView`'s navigation path —
/// distinct from pushing the `Tracker` model object itself, since a plain
/// SwiftData model class isn't `Hashable`/`Codable` in a way `NavigationPath`
/// can work with directly.
private struct TrackerRoute: Hashable {
    let id: UUID
}

/// Root screen listing all trackers. See spec §7.1.
struct TrackerListView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Query(sort: \Tracker.startDate, order: .reverse) private var allTrackers: [Tracker]
    private var trackers: [Tracker] { TrackerOrdering.ordered(allTrackers) }

    @State private var isPresentingAddTracker = false
    @State private var isPresentingSettings = false
    @State private var navigationPath = NavigationPath()

    // Mirrors TrackerDetailView's own ticker (§7.1) — without this, a row's
    // ring only ever redraws when its underlying data changes, so it would
    // never show the same live-refresh re-cycle the dashboard does; every
    // ring in the app should visibly tick on the same schedule. Aligned to
    // the *earliest* upcoming end date among all listed trackers, so a
    // tracker close to completing still gets its final on-time tick even
    // while sitting in a list alongside trackers with much later end dates.
    private var now: Date { PaceClock.shared.now }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if trackers.isEmpty {
                    EmptyTrackersView(isPresentingAddTracker: $isPresentingAddTracker)
                } else {
                    List {
                        // Top of the list, not bottom — always visible
                        // without scrolling, and newly created trackers
                        // sort to the top anyway (`\Tracker.startDate,
                        // order: .reverse`), so this is exactly where a
                        // just-added tracker will actually appear. Replaces
                        // the old toolbar "+" button entirely, styled to
                        // match a real tracker row rather than as a plain
                        // list button.
                        AddTrackerRow {
                            isPresentingAddTracker = true
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        ForEach(trackers) { tracker in
                            NavigationLink {
                                TrackerDetailView(tracker: tracker)
                            } label: {
                                TrackerRow(tracker: tracker, now: now)
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
            .navigationDestination(for: TrackerRoute.self) { route in
                if let tracker = trackers.first(where: { $0.id == route.id }) {
                    TrackerDetailView(tracker: tracker)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        isPresentingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddTracker) {
                AddTrackerView()
            }
            .navigationDestination(isPresented: $isPresentingSettings) {
                // `SettingsView` is iOS-only (§7.1); this file still compiles
                // for macOS, where this destination is never reached.
                #if !os(macOS)
                SettingsView()
                #else
                EmptyView()
                #endif
            }
            .onAppear {
                navigateToPendingDeepLinkIfAny()
            }
            .onChange(of: deepLinkRouter.pendingTrackerId) { _, _ in
                navigateToPendingDeepLinkIfAny()
            }
        }
    }

    private func deleteTrackers(at offsets: IndexSet) {
        for index in offsets {
            store.deleteTracker(trackers[index])
        }
    }

    /// Consumes a pending widget-tap navigation request, if there is one.
    /// Checked both on appear (the URL arrived before this view existed —
    /// a cold launch straight from a widget tap) and on change (the app was
    /// already running and the URL arrives while this screen is visible) —
    /// a widget tap can land either way depending on whether the app was
    /// already open.
    ///
    /// **Replaces** the whole navigation path rather than appending to it —
    /// if the app was already open with some other screen pushed (e.g. a
    /// different tracker's own detail view), appending on top left that
    /// screen underneath the new one, so the back button had to be tapped
    /// twice to actually reach the tracker list (once to pop the newly
    /// pushed detail, a second time to pop whatever was already there). A
    /// widget tap should always land exactly one level deep from the list,
    /// discarding any pre-existing push stack.
    private func navigateToPendingDeepLinkIfAny() {
        guard let id = deepLinkRouter.pendingTrackerId else { return }
        deepLinkRouter.pendingTrackerId = nil
        guard trackers.contains(where: { $0.id == id }) else { return }
        navigationPath = NavigationPath([TrackerRoute(id: id)])
    }
}

/// A single row: name plus a small ring-based pace indicator and the
/// difference from target — the key at-a-glance number (§3.2, §7.1). Styled
/// as its own soft card, tinted a whisper of the tracker's status color, so
/// the list reads as a stack of little dashboards rather than a plain table.
private struct TrackerRow: View {
    let tracker: Tracker
    let now: Date

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    private var status: PaceStatus {
        pace.status
    }

    var body: some View {
        HStack(spacing: 12) {
            TrackerBadge(tracker: tracker, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(tracker.name)
                    .font(WiggleRoomFont.headline(18, weight: 650))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if tracker.isCompleted(asOf: now) {
                    CompletedBadge()
                } else {
                    Text(tracker.periodRemainingText(asOf: now))
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            RingsView(tracker: tracker, now: now, lineWidth: 6, showsCenterContent: false)
                .frame(width: 42, height: 42)

            if tracker.latestReading != nil {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(pace.statusLine(for: tracker))
                        .font(.wiggleText(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(pace.displayDifference(for: tracker))
                        .font(.wiggleNumber(.subheadline, weight: .bold))
                        .foregroundStyle(status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 76, alignment: .trailing)
            } else {
                Text("No data yet")
                    .font(.wiggleText(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .trackerCard(tracker)
        .overlay(
            WobblyCard.shape()
                .strokeBorder(tracker.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

/// The "Add Tracker" entry point, styled as its own card matching
/// `TrackerRow`'s exact shape/sizing (same padding, corner radius, ring
/// size) rather than a plain list button — reads as "one more thing you
/// could add to this stack," not chrome bolted onto the list. Dashed
/// rather than solid stroke, and a "+" in place of a ring, distinguish it
/// from a real tracker at a glance. Lives at the top of the list (see
/// `TrackerListView.body`) rather than the bottom or the toolbar.
private struct AddTrackerRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    IconRingShape(ring: .outer, fitsRect: true)
                        .stroke(WiggleRoomColors.brand.opacity(0.4), style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                        .padding(2.5/2)
                        .frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.wiggleText(size: 17, weight: .semibold))
                        .foregroundStyle(WiggleRoomColors.brand)
                }

                Text("Add Tracker")
                    .font(WiggleRoomFont.headline(18, weight: 650))
                    .foregroundStyle(WiggleRoomColors.brand)

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(WiggleRoomColors.brand.opacity(0.06), in: WobblyCard.shape(1))
            .overlay(
                WobblyCard.shape(1)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .foregroundStyle(WiggleRoomColors.brand.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

/// A hand-drawn-feeling empty state — the two-ring motif rather
/// than a single generic SF Symbol, echoing the app's own ring motif so
/// even the "nothing here yet" moment feels like Wiggle Room rather than a
/// stock `ContentUnavailableView`.
private struct EmptyTrackersView: View {
    @Binding var isPresentingAddTracker: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            EmptyRingsMark(size: 132)
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
                    .font(.wiggleText(.subheadline, weight: .semibold))
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
        .environment(DeepLinkRouter())
}
