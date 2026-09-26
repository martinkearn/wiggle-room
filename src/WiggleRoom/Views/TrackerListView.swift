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
            .navigationTitle("Wiggle Room")
            .inlineNavigationBarIfAvailable()
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
                // Adding a tracker is the conventional top-right "+", not a
                // card at the top of the list: the list is for trackers, and
                // a row that wasn't one had to be styled to look like one and
                // then styled again to look unlike one. The empty state keeps
                // its own prominent button, since there is no list to put a
                // "+" above yet.
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

/// A single row, laid out as the tracker's own dashboard in miniature
/// (§3.2, §7.1): an identity band carrying the badge, the full name and how
/// much of the period is left, above a data band carrying the rings, the
/// status line and the two figures the dashboard itself leads with. Styled
/// as its own soft card, tinted a whisper of the tracker's colour, so the
/// list reads as a stack of little dashboards rather than a plain table.
///
/// The row is deliberately tall enough for two lines of name and two lines
/// of figures. It used to be a single 70pt line, which forced the name to
/// truncate — the one thing on the row the user chose themselves — and left
/// room for only the ahead/behind figure, so the two numbers that figure is
/// the *difference between* were invisible until the tracker was opened.
private struct TrackerRow: View {
    let tracker: Tracker
    let now: Date

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    private var status: PaceStatus {
        pace.status
    }

    /// The leading gutter shared by both bands: the badge sits in it at the
    /// top, the rings at the bottom, and every line of text starts to the
    /// right of it. One width for both keeps the two circles concentric
    /// down the card and gives the text a single left edge, and because the
    /// rings are now anchored to the *leading* edge rather than floating
    /// after a variable-width text column, they line up down the whole list
    /// without a fixed-width status column to hold them in place.
    private static let gutterWidth: CGFloat = 44

    /// The height held for a row whose tracker has gone — close enough to a
    /// real row that the list doesn't visibly jump while `@Query` catches up.
    private static let placeholderHeight: CGFloat = 124

    var body: some View {
        // Same guard as `TrackerDetailView`'s own top-level check, for the
        // same reason: this `@Query`-sourced row can still be mid-render
        // with a `Tracker` whose backing data was just detached (deleted
        // locally, or merged out by CloudKit) — the `@Query` array hasn't
        // republished yet to drop this row. Reading any property on it
        // then is a hard SwiftData crash, not a catchable error; a real
        // TestFlight crash report caught exactly this, one level down in
        // `RingsView` (which carries its own identical guard).
        if tracker.modelContext == nil {
            Color.clear
                .frame(height: Self.placeholderHeight)
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityBand
            dataBand
        }
        .padding(14)
        .trackerCard(tracker)
        .overlay(
            WobblyCard.shape()
                .strokeBorder(tracker.accentColor.opacity(0.18), lineWidth: 1)
        )
        // One spoken sentence rather than eight separate fragments — the
        // row now carries enough text that VoiceOver reading each piece as
        // its own element would be slower than opening the tracker. Says
        // everything colour and ring geometry say (§3.4).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Badge, name and period — who this tracker is, across the full width
    /// of the card, so a long name wraps to a second line instead of being
    /// truncated to make room for figures.
    private var identityBand: some View {
        HStack(alignment: .top, spacing: 12) {
            TrackerBadge(tracker: tracker, size: 40)
                .frame(width: Self.gutterWidth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(tracker.name)
                        .font(WiggleRoomFont.headline(18, weight: 650))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    ZoomIndicator(tracker: tracker, now: now, size: 12)
                }
                periodLine
            }

            Spacer(minLength: 0)
        }
    }

    /// How long is left and when it ends — the second half answers "left
    /// until when?", which a countdown on its own never does.
    @ViewBuilder
    private var periodLine: some View {
        if tracker.isCompleted(asOf: now) {
            HStack(spacing: 6) {
                CompletedBadge()
                Text(endDateText)
                    .font(.wiggleText(.caption))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("\(tracker.periodRemainingText(asOf: now)) \u{00B7} \(endDateText)")
                .font(.wiggleText(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Rings, status and figures — how this tracker is doing.
    private var dataBand: some View {
        HStack(alignment: .center, spacing: 12) {
            RingsView(tracker: tracker, now: now, lineWidth: 6, showsCenterContent: false)
                .frame(width: Self.gutterWidth, height: Self.gutterWidth)

            VStack(alignment: .leading, spacing: 5) {
                statusLine
                figuresLine
            }

            Spacer(minLength: 0)
        }
    }

    /// The headline: the type's own status wording and the ahead/behind
    /// figure, in the status colour. Same wording as the dashboard's ring
    /// centre, from `TrackerPace`, so the two never drift apart.
    @ViewBuilder
    private var statusLine: some View {
        if tracker.latestReading != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(pace.statusLine(for: tracker))
                    .font(WiggleRoomFont.cardLabel)
                    .foregroundStyle(.secondary)
                Text(pace.displayDifference(for: tracker))
                    .font(.wiggleNumber(.title3, weight: .bold))
                    .foregroundStyle(status.color)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Text("No readings yet")
                .font(.wiggleText(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The two figures the status figure is the difference *between*: what
    /// the tracker reads now, and what it would read to be exactly on pace
    /// today. Both are named with the type's own nouns ("Balance",
    /// "Budget today"; "Weight", "Target today").
    private var figuresLine: some View {
        HStack(spacing: 8) {
            figure(label: tracker.terminology.currentFigure, value: currentValueText)
            Text("\u{00B7}")
                .font(.wiggleText(.caption2))
                .foregroundStyle(.tertiary)
            figure(label: tracker.terminology.paceFigure, value: tracker.formattedValue(pace.targetValueToday))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func figure(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.wiggleText(.caption2))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.wiggleNumber(.caption, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    /// An em dash rather than the starting value when nothing has been
    /// logged yet: the pace figure beside it is real, and printing a figure
    /// the user never entered next to it would read as a reading.
    private var currentValueText: String {
        guard tracker.latestReading != nil else { return "\u{2014}" }
        return tracker.formattedValue(pace.currentValue)
    }

    /// "ends 12 Oct", or "ends 12 Oct 2027" when the period ends in another
    /// year, where a bare day and month would be ambiguous. Capitalised
    /// once completed, where it follows the Completed pill rather than the
    /// days-remaining phrase.
    private var endDateText: String {
        let calendar = Calendar.current
        let endsThisYear = calendar.component(.year, from: tracker.endDate) == calendar.component(.year, from: now)
        let style: Date.FormatStyle = endsThisYear
            ? .dateTime.day().month(.abbreviated)
            : .dateTime.day().month(.abbreviated).year()
        let formatted = tracker.endDate.formatted(style)
        return tracker.isCompleted(asOf: now) ? "Ended \(formatted)" : "ends \(formatted)"
    }

    private var accessibilityDescription: String {
        var parts = [tracker.name]
        if tracker.isCompleted(asOf: now) {
            parts.append("Completed")
        }
        parts.append(tracker.periodRemainingText(asOf: now))
        if tracker.latestReading != nil {
            parts.append("\(pace.statusLine(for: tracker)) \(pace.displayDifference(for: tracker))")
            parts.append("\(tracker.terminology.currentFigure) \(tracker.formattedValue(pace.currentValue))")
        } else {
            parts.append("No readings yet")
        }
        parts.append("\(tracker.terminology.paceFigure) \(tracker.formattedValue(pace.targetValueToday))")
        if let window = tracker.zoomWindow(asOf: now) {
            parts.append("Zoomed to \(Tracker.zoomRangeText(window))")
        }
        return parts.joined(separator: ", ")
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
