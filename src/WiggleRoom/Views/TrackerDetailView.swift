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

    /// Set whenever a Starling (or future auto-fetch provider) refresh
    /// fails — either from the pull-to-refresh gesture or the ticker's own
    /// 30s background fetch — and shown as a distinct error line (§8.4)
    /// rather than silently leaving the last-known figure looking current.
    /// Cleared on the next successful refresh.
    @State private var refreshErrorMessage: String?

    /// Guards against overlapping fetches — the 30s ticker tick and a
    /// manual pull-to-refresh could otherwise both be in flight at once for
    /// the same tracker.
    @State private var isRefreshingFromSource = false

    private var now: Date { ticker.now }

    private var isCompleted: Bool {
        tracker.isCompleted(asOf: now)
    }

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    /// The tracker's pace pinned to its own end date, using the last reading
    /// actually logged — the stable, final figure shown once completed,
    /// rather than the ever-moving live `pace` above.
    private var finalPace: TrackerPace? {
        guard let latest = tracker.latestReading else { return nil }
        return tracker.pace(actualValue: latest.value, asOf: tracker.endDate)
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
                // single figure. The pull-gesture hint sits right next to it
                // on the same line, above the rings, rather than lower on
                // the screen — this is the one spot on the dashboard already
                // telling you your figures are about to move on their own,
                // so it's the natural place to also say how to make that
                // happen right now instead of waiting.
                if let screenUpdateCaption {
                    HStack(spacing: 6) {
                        Text(screenUpdateCaption)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        #if !os(macOS)
                        Text("\u{00B7}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        pullToUpdateHint
                        #endif
                    }
                    .padding(.top, 4)
                }

                if isCompleted {
                    CompletedBadge()
                }

                RingsView(tracker: tracker, now: now)
                    .frame(width: 260, height: 260)

                if isCompleted {
                    completedSummary
                } else {
                    figuresRow
                    #if os(macOS)
                    updateBalanceButton
                    #endif
                }

                if let refreshErrorMessage {
                    Text(refreshErrorMessage)
                        .font(.caption)
                        .foregroundStyle(WiggleRoomColors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text(periodRemainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if tracker.latestReading == nil {
                    Text("No readings logged yet — log one to see your pace.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if tracker.sortedReadings.count > 1 {
                    TrendChartView(tracker: tracker, now: now)
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
        .navigationSubtitle(periodRangeText)
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
            // 30s while this detail screen is on-screen (§5.3's decided
            // foreground poll cadence) — down from the 60s display-only
            // default, since this ticker also drives a real Starling fetch
            // on every tick now, not just a display recompute.
            ticker.interval = 30
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
                if !tracker.isManualEntry && !isCompleted {
                    Task { await refreshFromSourceIfNeeded() }
                }
            }
            ticker.start(now: appearedAt)
            checkForCompletionCelebration(asOf: appearedAt)
            if !tracker.isManualEntry && !isCompleted {
                Task { await refreshFromSourceIfNeeded() }
            }
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
    /// for a manual tracker this opens the log sheet; for a real
    /// auto-fetching connected source (Starling) it re-fetches instead, with
    /// no new gesture or control to learn. A short pause before opening the
    /// log sheet gives the refresh control a beat to visibly settle before
    /// the sheet takes over, rather than the sheet snapping up mid-pull.
    private func handleUpdateGesture() async {
        guard !isCompleted else { return }
        guard tracker.isManualEntry else {
            await refreshFromSourceIfNeeded(force: true)
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        isPresentingLogReading = true
    }
    #endif

    /// Fetches a fresh value from the tracker's connected source and logs it
    /// (§5.3) — called from the 30s ticker tick and from a manual
    /// pull-to-refresh/macOS button alike. `force` skips the
    /// already-in-flight guard, since a user's own manual pull should always
    /// go through even if a background tick happens to be mid-fetch.
    private func refreshFromSourceIfNeeded(force: Bool = false) async {
        guard !tracker.isManualEntry, !isCompleted else { return }
        guard force || !isRefreshingFromSource else { return }
        isRefreshingFromSource = true
        defer { isRefreshingFromSource = false }
        do {
            try await store.refreshFromSource(tracker)
            refreshErrorMessage = nil
        } catch {
            refreshErrorMessage = Self.errorMessage(for: error)
        }
    }

    /// A short, distinct-from-stale-data error line (§8.4) — never leaves a
    /// failed refresh looking like a current, successful one.
    private static func errorMessage(for error: Error) -> String {
        switch error {
        case StarlingProviderError.notConnected:
            return "Not connected — reconnect this source in Settings."
        case StarlingAPIError.invalidToken:
            return "Connection expired — reconnect this source in Settings."
        case StarlingAPIError.rateLimited, StarlingAPIError.budgetExceeded:
            return "Refresh paused — rate limit reached, try again shortly."
        case StarlingAPIError.network:
            return "Couldn't reach Starling — check your connection."
        default:
            return "Couldn't refresh — will try again shortly."
        }
    }

    #if !os(macOS)

    /// A persistent affordance for the pull-to-refresh gesture — unlike a
    /// button, `.refreshable`'s own control only appears once a pull is
    /// already underway, so without this there'd be nothing on screen
    /// hinting the gesture exists at all. Worded per source: "update" for a
    /// manual tracker (it opens the log sheet), "refresh" for a connected
    /// one (it re-fetches) — same gesture, described as whichever action it
    /// actually performs for this tracker.
    private var pullToUpdateHint: some View {
        Label("Pull down to \(tracker.isManualEntry ? "update" : "refresh")", systemImage: "arrow.down")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
    #else
    /// macOS has no pull-to-refresh gesture, so it keeps an explicit button
    /// instead — moved out from inside the Current Balance card so both
    /// figure cards share identical visual weight. For a manual tracker
    /// this opens the log sheet; for an auto-fetch source (Starling) it
    /// re-fetches directly, same as iOS's pull-to-refresh.
    private var updateBalanceButton: some View {
        Button {
            if tracker.isManualEntry {
                isPresentingLogReading = true
            } else {
                Task { await refreshFromSourceIfNeeded(force: true) }
            }
        } label: {
            Label(
                tracker.isManualEntry ? "Update Current Balance" : "Refresh",
                systemImage: tracker.isManualEntry ? "plus.circle.fill" : "arrow.clockwise"
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WiggleRoomColors.brand)
        .padding(.horizontal)
        .disabled(isRefreshingFromSource && !tracker.isManualEntry)
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
        return "Refreshes in \(ticker.secondsUntilNextUpdate)s"
    }

    private var remainingInAllowanceCaption: String? {
        pace.remainingInAllowanceCaption(for: tracker)
    }

    /// The small, subtle line under Target Right Now's own number — same
    /// weight/position as Current Balance's "£X left in this budget" — but
    /// stating the tracker's projected final target instead: where the
    /// number above is landing right now, this is where it's designed to
    /// land by the very end of the period.
    private var finalBalanceCaption: String {
        "Final target will be \(tracker.formattedValue(tracker.projectedFinalValue))"
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

    private static let periodRangeWithTimeFormatter: Date.FormatStyle = .init()
        .month(.abbreviated)
        .day()
        .hour()
        .minute()

    /// "12 Jan – 19 Jan", or "12 Jan, 9:00 AM – 19 Jan, 9:00 AM" only once
    /// the tracker actually has a set time of day (`hasExplicitTimes`) —
    /// otherwise both bounds sit at an implicit midnight, and printing that
    /// out as "12:00 AM" reads as a real, deliberately-chosen time rather
    /// than the meaningless default it actually is.
    private var periodRangeText: String {
        let formatter = tracker.hasExplicitTimes ? Self.periodRangeWithTimeFormatter : Self.periodRangeFormatter
        return "\(tracker.startDate.formatted(formatter)) \u{2013} \(tracker.endDate.formatted(formatter))"
    }

    private var periodRemainingText: String {
        tracker.periodRemainingText(asOf: now)
    }
}

#Preview {
    NavigationStack {
        TrackerDetailView(tracker: PreviewData.makeSampleTracker())
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
}
