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
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

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
    @State private var ticker = AutoUpdateTicker()
    private var now: Date { ticker.now }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if trackers.isEmpty {
                    EmptyTrackersView(isPresentingAddTracker: $isPresentingAddTracker)
                } else {
                    List {
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
            .sheet(isPresented: $isPresentingSettings) {
                // `TrackerListView` itself is iOS/iPadOS-only at runtime
                // (`ContentView` routes macOS to `MacRootView` instead,
                // §7.2), but this file still compiles for macOS since it
                // isn't `#if os`-gated at the file level — `SettingsView`
                // is iOS-only (§7.1), so this branch only exists to keep
                // the macOS compile happy; it's never actually reached.
                #if !os(macOS)
                SettingsView()
                #else
                EmptyView()
                #endif
            }
            .onAppear {
                ticker.endDatesProvider = { trackers.map(\.endDate) }
                ticker.start()
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
        HStack(spacing: 14) {
            RingsView(tracker: tracker, now: now, lineWidth: 6, showsCenterContent: false)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tracker.name)
                        .font(WiggleRoomFont.headline(18, weight: 650))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if tracker.isCompleted(asOf: now) {
                        CompletedBadge()
                    }
                }
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
        .environment(DeepLinkRouter())
}
