//
//  TrackerDetailView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Tracker detail / dashboard (§7.1): the two-ring visual as the primary
/// visual (with the difference-from-target as its centerpiece — that's the
/// key number, per §3.2), current value, live target, days remaining, and a
/// trend chart once at least one reading exists. Once the tracker's period
/// has actually ended, the dashboard switches into a completed presentation
/// (see `isCompleted`) — the live projection and update controls no longer
/// apply, so they're replaced with a final summary instead.
///
/// On iOS/iPadOS, updating is a pull-to-refresh gesture on the whole screen
/// (`.refreshable`, see `handleUpdateGesture()`) rather than a dedicated
/// button — today that opens the manual "log a reading" sheet, but the same
/// gesture is meant to double as the eventual refresh action for a real
/// auto-fetching connected source (Starling, Tesla), so there's exactly one
/// gesture to learn for "bring this tracker's figures up to date" no matter
/// where its data comes from. macOS has no pull gesture, so it keeps an
/// explicit "Update Current Balance" button instead.
struct TrackerDetailView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker

    @State private var isPresentingLogReading = false
    @State private var isPresentingEditTracker = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var isPresentingReadingHistory = false
    /// The zoom-level lens (§4.5) the dashboard is currently scoped to —
    /// re-scopes the rings, figures, and trend chart together. Only shown
    /// as a picker when `tracker.availableZoomLevels` offers more than just
    /// `.overall` (i.e. the tracker runs longer than a week — see
    /// `Tracker.availableZoomLevels`). Defaults to `.thisWeek` whenever
    /// that's on offer, set in `init` below rather than here so it's
    /// correct on the very first render rather than flipping a beat after
    /// appearing — "how am I doing lately" is a more useful first look than
    /// the whole, possibly multi-year, period for a tracker long enough to
    /// zoom at all.
    @State private var zoomLevel: ZoomLevel

    init(tracker: Tracker) {
        self.tracker = tracker
        let defaultZoom: ZoomLevel = tracker.availableZoomLevels.contains(.thisWeek) ? .thisWeek : .overall
        _zoomLevel = State(initialValue: defaultZoom)
    }

    /// Drives `now` forward on a schedule aligned to this tracker's own end
    /// date (see `AutoUpdateTicker`/`TrackerUpdateScheduling`) instead of a
    /// flat 60-second cadence — the last automatic update before the
    /// tracker completes always lands exactly on `tracker.endDate`.
    @State private var ticker = AutoUpdateTicker()

    /// Ever-incrementing rather than a toggled `Bool` — each increment
    /// always spins a fresh full turn forward from wherever the last one
    /// left off, so back-to-back updates never fight over rotation
    /// direction the way flipping true/false/true would.
    @State private var targetFlipCount = 0

    /// Shown once, the first time this dashboard is viewed after the
    /// tracker's period has actually ended still under budget/on track — see
    /// `checkForCompletionCelebration()`.
    @State private var isShowingCelebration = false

    private var now: Date { ticker.now }

    private var isCompleted: Bool {
        tracker.isCompleted(asOf: now)
    }

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now, zoomLevel: zoomLevel)
    }

    /// The tracker's pace pinned to its own end date, using the last reading
    /// actually logged — the stable, final figure shown once completed,
    /// rather than the ever-moving live `pace` above.
    private var finalPace: TrackerPace? {
        guard let latest = tracker.latestReading else { return nil }
        return tracker.pace(actualValue: latest.value, asOf: tracker.endDate)
    }

    private var availableZoomLevels: [ZoomLevel] {
        tracker.availableZoomLevels
    }

    /// The zoomed window's own end — the days-remaining caption and the
    /// trend chart's readings should both scope to the sub-period, not the
    /// tracker's full period, once zoomed in.
    private var zoomWindowEnd: Date {
        tracker.subPeriod(for: zoomLevel, asOf: now)?.end ?? tracker.endDate
    }

    private var windowedReadingCount: Int {
        guard let subPeriod = tracker.subPeriod(for: zoomLevel, asOf: now) else {
            return tracker.sortedReadings.count
        }
        return tracker.sortedReadings.filter { $0.date >= subPeriod.start && $0.date <= subPeriod.end }.count
    }

    var body: some View {
        ZStack {
            dashboardScrollView

            if isShowingCelebration, let finalStatus = tracker.finalPaceStatus(asOf: now) {
                CelebrationView(tracker: tracker, status: finalStatus) {
                    isShowingCelebration = false
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private var dashboardScrollView: some View {
        ScrollView {
            VStack(spacing: 28) {
                // The whole screen's figures update on this cadence (Target
                // Right Now, the ring, the difference) — not just one card —
                // so the countdown lives up top rather than tucked under a
                // single figure.
                if let screenUpdateCaption {
                    Text(screenUpdateCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }

                if isCompleted {
                    CompletedBadge()
                }

                if availableZoomLevels.count > 1 && !isCompleted {
                    zoomLevelPicker
                }

                RingsView(tracker: tracker, now: now, zoomLevel: zoomLevel)
                    .frame(width: 260, height: 260)

                if isCompleted {
                    completedSummary
                } else {
                    figuresRow
                    if tracker.isManualEntry {
                        #if os(macOS)
                        updateBalanceButton
                        #else
                        pullToUpdateHint
                        #endif
                    }
                }

                VStack(spacing: 2) {
                    Text(periodRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(periodRemainingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if tracker.latestReading == nil {
                    Text("No readings logged yet — log one to see your pace.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if windowedReadingCount > 1 {
                    TrendChartView(tracker: tracker, zoomLevel: zoomLevel, now: now)
                        .frame(height: 240)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 32)
        }
        #if !os(macOS)
        .refreshable {
            await handleUpdateGesture()
        }
        #endif
        .navigationTitle(tracker.name)
        .inlineNavigationBarIfAvailable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isPresentingEditTracker = true
                    } label: {
                        Label("Edit Tracker", systemImage: "pencil")
                    }
                    if tracker.isManualEntry {
                        Button {
                            isPresentingReadingHistory = true
                        } label: {
                            Label("Update History", systemImage: "clock")
                        }
                    }
                    Button(role: .destructive) {
                        isPresentingDeleteConfirmation = true
                    } label: {
                        Label("Delete Tracker", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPresentingLogReading) {
            LogReadingView(tracker: tracker)
        }
        .sheet(isPresented: $isPresentingEditTracker) {
            AddTrackerView(existingTracker: tracker)
        }
        .sheet(isPresented: $isPresentingReadingHistory) {
            NavigationStack {
                ReadingHistoryView(tracker: tracker)
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(tracker.name)\u{201D}?",
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Tracker", role: .destructive) {
                store.deleteTracker(tracker)
                dismiss()
            }
        } message: {
            Text("This removes the tracker and all its logged readings. This can't be undone.")
        }
        .onAppear {
            let appearedAt = Date.now
            ticker.endDatesProvider = { [tracker.endDate] }
            ticker.onUpdate = { date in
                // The minute rollover is exactly when Target Right Now's
                // value actually moves (it's a live function of `now`), so
                // the card's flip should register here too — previously the
                // flip only fired from a newly logged reading, so the "live"
                // side of this card never visibly updated at all, only the
                // "Update Current Value" side did.
                withAnimation(.easeInOut(duration: 0.7)) {
                    targetFlipCount += 1
                }
                // Catches a tracker whose period ends while its dashboard
                // happens to already be open, not just on a fresh appear.
                checkForCompletionCelebration(asOf: date)
            }
            ticker.start(now: appearedAt)
            checkForCompletionCelebration(asOf: appearedAt)
        }
        // Keyed on the reading's own id, not its value — logging a reading
        // that happens to match the previous one is still a genuine update
        // and should still visibly register, not silently no-op.
        .onChange(of: tracker.latestReading?.id) { _, _ in
            withAnimation(.easeInOut(duration: 0.7)) {
                targetFlipCount += 1
            }
            // A final reading logged after the period's already ended (a
            // late "closing out" update) can be what actually puts the
            // tracker under budget — worth checking here too, not just on
            // appear/minute-tick.
            checkForCompletionCelebration(asOf: now)
        }
    }

    /// The video-game-style completion celebration (see `CelebrationView`)
    /// fires once, the first time this dashboard sees the tracker's period
    /// has genuinely ended (`asOf >= tracker.endDate`) with a final status
    /// of `.good` — under budget for a budget tracker, on/under pace
    /// otherwise. `Tracker.hasCelebratedCompletion` makes this a one-shot:
    /// re-opening a long-finished tracker never replays it.
    private func checkForCompletionCelebration(asOf date: Date) {
        guard !tracker.hasCelebratedCompletion,
              let finalStatus = tracker.finalPaceStatus(asOf: date),
              finalStatus == .good
        else { return }
        tracker.hasCelebratedCompletion = true
        store.saveChanges()
        withAnimation(.easeIn(duration: 0.2)) {
            isShowingCelebration = true
        }
    }

    /// Two visually separate cards, not one shared row — Current Balance
    /// and Target Right Now are different things updated in different ways
    /// (one by logging a reading, one automatically by the clock) — but
    /// otherwise identical in shape/weight, since the update action now
    /// lives outside both of them (a pull-to-refresh gesture on iOS, an
    /// explicit button on macOS — see `handleUpdateGesture()`/
    /// `updateBalanceButton`).
    private var figuresRow: some View {
        HStack(alignment: .top, spacing: 12) {
            card(tint: pace.status.color) {
                figureContent(title: tracker.currentValueLabel, value: pace.currentValue, caption: remainingInAllowanceCaption)
            }

            card(tint: WiggleRoomColors.paceRing) {
                figureContent(title: "Target Right Now", value: pace.targetValueToday, caption: finalBalanceCaption)
            }
            // A little "just updated" flourish when a new reading lands —
            // a full turn rather than a half-flip so the card never rests
            // mirror-reversed mid-animation if interrupted by a second
            // rapid update.
            .rotation3DEffect(
                .degrees(Double(targetFlipCount) * 360),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.35
            )
        }
        .padding(.horizontal)
    }

    /// Final-state replacement for `figuresRow` once the tracker has
    /// completed — "Target Right Now" is a live projection that's no longer
    /// meaningful, so it's replaced with the stable final figure and status
    /// instead, pinned to `endDate` (see `finalPace`).
    private var completedSummary: some View {
        card(tint: (finalPace?.status ?? .warning).color) {
            figureContent(
                title: "Final \(tracker.currentValueLabel)",
                value: finalPace?.currentValue ?? tracker.startingValue,
                caption: finalSummaryCaption
            )
        }
        .padding(.horizontal)
    }

    private var finalSummaryCaption: String? {
        guard let finalPace else { return nil }
        return "\(finalPace.statusLine(for: tracker)) \(finalPace.displayDifference(for: tracker))"
    }

    #if !os(macOS)
    /// The system pull-to-refresh gesture's action (`.refreshable` above) —
    /// today the only "source" is manual entry, so this just opens the log
    /// sheet, but the gesture itself is meant to be source-agnostic: once a
    /// real auto-fetching connected source exists, the same pull-down
    /// re-fetches from it instead, with no new gesture or control to learn.
    /// A short pause before returning gives the refresh control a beat to
    /// visibly settle before the sheet takes over, rather than the sheet
    /// snapping up mid-pull.
    private func handleUpdateGesture() async {
        guard !isCompleted else { return }
        guard tracker.isManualEntry else {
            // No auto-fetching provider exists yet (§9) — nothing to
            // refresh from until one does.
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        isPresentingLogReading = true
    }

    /// A persistent affordance for the pull-to-refresh gesture — unlike a
    /// button, `.refreshable`'s own control only appears once a pull is
    /// already underway, so without this there'd be nothing on screen
    /// hinting the gesture exists at all.
    private var pullToUpdateHint: some View {
        Label("Pull down to update", systemImage: "arrow.down")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    #else
    /// macOS has no pull-to-refresh gesture, so it keeps an explicit button
    /// instead — moved out from inside the Current Balance card so both
    /// figure cards share identical visual weight.
    private var updateBalanceButton: some View {
        Button {
            isPresentingLogReading = true
        } label: {
            Label("Update Current Balance", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WiggleRoomColors.brand)
        .padding(.horizontal)
    }
    #endif

    private func card(tint: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }

    /// The whole screen's live figures (the ring, the difference, Target
    /// Right Now) recompute on this cadence — not just one card — so this
    /// sits at the very top of the screen rather than under a single figure.
    private var screenUpdateCaption: String? {
        guard now < tracker.endDate else { return nil }
        return "Updates in \(ticker.secondsUntilNextUpdate)s"
    }

    private var remainingInAllowanceCaption: String? {
        pace.remainingInAllowanceCaption(for: tracker)
    }

    /// The small, subtle line under Target Right Now's own number — same
    /// weight/position as Current Balance's "£X left in this budget" — but
    /// stating the tracker's projected final balance instead: where the
    /// number above is landing right now, this is where it's designed to
    /// land by the very end of the period.
    private var finalBalanceCaption: String {
        "Final balance will be \(tracker.formattedValue(tracker.projectedFinalValue))"
    }

    private func figureContent(title: String, value: Decimal, caption: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(tracker.formattedValue(value))
                .font(.wiggleNumber(size: 24, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static let periodRangeFormatter: Date.FormatStyle = .init()
        .month(.abbreviated)
        .day()
        .hour()
        .minute()

    /// "12 Jan, 9:00 AM – 19 Jan, 9:00 AM" — the tracker's own bounds,
    /// distinct from `periodRemainingText`'s live countdown below it.
    private var periodRangeText: String {
        "\(tracker.startDate.formatted(Self.periodRangeFormatter)) \u{2013} \(tracker.endDate.formatted(Self.periodRangeFormatter))"
    }

    private var periodRemainingText: String {
        tracker.periodRemainingText(asOf: now, until: zoomWindowEnd)
    }

    /// Segmented zoom-level control (§4.5, §7.1) sitting above the rings —
    /// re-scopes the whole dashboard (rings, figures, chart) to the selected
    /// sub-period. Only shown when the tracker's own length actually offers
    /// more than `.overall` (see `Tracker.availableZoomLevels`), and not
    /// once completed — zooming into a sub-period of a finished tracker
    /// doesn't apply once there's only a final summary to show.
    private var zoomLevelPicker: some View {
        Picker("Zoom", selection: $zoomLevel) {
            ForEach(availableZoomLevels) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        TrackerDetailView(tracker: PreviewData.makeSampleTracker())
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
}
