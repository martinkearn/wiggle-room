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
    @State private var isPresentingReadingHistory = false

    /// **Fully manual as of 2026-09-18** — this screen no longer ticks or
    /// auto-refreshes on any timer while open. Multiple devices each
    /// running their own independent foreground ticker (previously a flat
    /// 45s auto-fetch) turned out to be a real, avoidable source of extra
    /// Starling requests — every open detail screen on every device was
    /// polling on its own schedule, uncoordinated with any other. `now` is
    /// set once when the screen appears (and again after any refresh
    /// completes) rather than continuously advancing — figures are exact
    /// as of the last time this tracker was actually opened or refreshed,
    /// not live-ticking in between. The user updates it deliberately, via
    /// pull-to-refresh (iOS) or the Refresh/Update Current Balance button
    /// (macOS) — see `handleUpdateGesture()`/`updateBalanceButton`.
    /// Background refresh (`BackgroundRefreshScheduler`, §5.3) is
    /// unaffected — its own time-of-day-banded cadence continues exactly
    /// as before regardless of whether any detail screen is open anywhere.
    @State private var now: Date = .now

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
    /// fails — from opening this screen or a manual pull-to-refresh/button
    /// press — and shown as a distinct error line (§8.4) rather than
    /// silently leaving the last-known figure looking current. Cleared on
    /// the next successful refresh.
    @State private var refreshErrorMessage: String?

    /// Guards against overlapping fetches — the on-appear refresh and a
    /// manual pull-to-refresh could otherwise both be in flight at once for
    /// the same tracker.
    @State private var isRefreshingFromSource = false

    /// The bound account's display name for a real, non-manual source —
    /// `Tracker` only stores `sourceTargetId` (a bare id), not a
    /// human-readable label, so this is resolved live once on appear
    /// (`resolveAccountNameIfNeeded()`), never re-fetched afterward, to
    /// avoid spending a Starling request on something that never changes
    /// for a given tracker. Falls back to the raw id if unresolved.
    @State private var resolvedAccountName: String?

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
        // `tracker` is a direct object reference, not resolved fresh from
        // a `@Query` on every render — SwiftData's own fine-grained
        // Observation still re-invokes this body whenever a property of
        // `tracker` that was previously read changes, *including* when the
        // tracker is deleted from somewhere else entirely (e.g. Settings'
        // Reset App Data, §12, running in a separate window from this
        // detail view). Reading any property on a model whose backing data
        // has been detached from its context is a hard SwiftData crash
        // ("This backing data was detached from a context without
        // resolving attributes"), not a recoverable error — so this checks
        // `modelContext` (`nil` once deleted) *before* touching anything
        // else on `tracker`, rather than after. Found via a real crash
        // report: resetting all data while this screen was open elsewhere.
        if tracker.modelContext == nil {
            ContentUnavailableView(
                "Tracker Deleted",
                systemImage: "trash",
                description: Text("This tracker no longer exists.")
            )
        } else {
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
    }

    private var dashboardScrollView: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let sourceCaption {
                    Text(sourceCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }

                // No more live countdown here — figures are fully manual
                // now (see `now`'s own doc comment) — just the pull-gesture
                // hint on iOS, above the rings alongside everything else
                // that's static context for this screen.
                #if !os(macOS)
                pullToUpdateHint
                    .padding(.top, sourceCaption == nil ? 4 : 0)
                #endif

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

                    if !isCompleted, let estimatedFinalValue = tracker.estimatedFinalValue {
                        estimatedFinalBalanceCard(estimatedFinalValue)
                    }
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
                    if !tracker.sortedReadings.isEmpty {
                        Button {
                            isPresentingReadingHistory = true
                        } label: {
                            Label("Update History", systemImage: "clock")
                        }
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
            // Delete now lives at the bottom of the Edit Tracker screen
            // itself, with a clear visual gap from the fields above (§7.1) —
            // moved out of this "…" menu, where it used to sit directly
            // under Edit Tracker with no separation, an easy mis-tap on
            // iOS. `onDelete` dismisses this dashboard too, since the
            // tracker it was showing no longer exists once the sheet closes.
            AddTrackerView(existingTracker: tracker, onDelete: { dismiss() })
        }
        .sheet(isPresented: $isPresentingReadingHistory) {
            NavigationStack {
                ReadingHistoryView(tracker: tracker)
            }
        }
        .onAppear {
            now = Date.now
            checkForCompletionCelebration(asOf: now)
            // Always refresh once when a tracker is first opened, even
            // though there's no ongoing ticker anymore — opening the
            // screen is itself the signal "I want current data," same as
            // a manual pull-to-refresh would be.
            if !tracker.isManualEntry && !isCompleted {
                Task { await refreshFromSourceIfNeeded() }
            }
            if !tracker.isManualEntry && resolvedAccountName == nil {
                Task { await resolveAccountNameIfNeeded() }
            }
        }
        // Keyed on the reading's own id, not its value — logging a reading
        // that happens to match the previous one is still a genuine update
        // and should still visibly register, not silently no-op. Also
        // refreshes `now` — for a manual tracker this is the only place
        // that happens outside of appear, since logging a reading (not
        // `refreshFromSourceIfNeeded`) is that tracker's own "update" path.
        .onChange(of: tracker.latestReading?.id) { _, _ in
            now = Date.now
            withAnimation(.easeInOut(duration: 0.7)) {
                targetFlipCount += 1
            }
            // A final reading logged after the period's already ended (a
            // late "closing out" update) can be what actually puts the
            // tracker under budget — worth checking here too, not just on
            // appear/refresh.
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
    /// (§5.3) — called on appear and from a manual pull-to-refresh/macOS
    /// button alike, now that this screen has no ongoing ticker of its own.
    /// `force` skips the already-in-flight guard, since a user's own manual
    /// pull should always go through even if the on-appear fetch happens to
    /// still be in flight.
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
        // `now` only otherwise moves on appear — refresh it here too so
        // Target Right Now/the ring reflect the actual moment this fetch
        // completed, not whenever the screen happened to be opened.
        now = Date.now
        checkForCompletionCelebration(asOf: now)
        withAnimation(.easeInOut(duration: 0.7)) {
            targetFlipCount += 1
        }
    }

    /// Read-only resolution of the bound account's display name — fetches
    /// the source's current account list (the same call the target picker
    /// makes) and finds the one matching `tracker.sourceTargetId`. Never
    /// re-fetched on a tick, only once per appearance (guarded by the
    /// `resolvedAccountName == nil` check at the call site) — a tracker's
    /// bound account never changes after creation (§7.1), so there's
    /// nothing to keep polling for here. Falls back to the raw id (still
    /// shown via `sourceCaption`) if the fetch fails or the account is no
    /// longer listed.
    private func resolveAccountNameIfNeeded() async {
        guard let source = tracker.connectedSource, let targetId = tracker.sourceTargetId,
              let provider = store.provider(for: tracker)
        else { return }
        guard let targets = try? await provider.listAvailableTargets(for: source) else { return }
        resolvedAccountName = targets.first(where: { $0.id == targetId })?.displayName
    }

    /// "My Starling Account · Personal" — shown for a real, non-manual
    /// source so it's clear at a glance which connection/account this
    /// tracker's figures actually come from, without needing to open Edit
    /// Tracker. `nil` for a manual tracker (nothing to name).
    private var sourceCaption: String? {
        guard !tracker.isManualEntry, let source = tracker.connectedSource else { return nil }
        let account = resolvedAccountName ?? tracker.sourceTargetId ?? ""
        return account.isEmpty ? source.displayName : "\(source.displayName) \u{00B7} \(account)"
    }

    /// "3:45 PM" — same-day retry times are the common case, so no date
    /// component; a rate-limit cooldown is always at most a day out anyway.
    private static let retryTimeFormatter: Date.FormatStyle = .init().hour().minute()

    /// A short, distinct-from-stale-data error line (§8.4) — never leaves a
    /// failed refresh looking like a current, successful one.
    private static func errorMessage(for error: Error) -> String {
        switch error {
        case StarlingProviderError.notConnected:
            return "Not connected — reconnect this source in Settings."
        case StarlingAPIError.invalidToken:
            return "Connection expired — reconnect this source in Settings."
        case StarlingAPIError.rateLimited(let retryAfter):
            let resumeText = retryAfter.map { " Resumes at \(Date.now.addingTimeInterval($0).formatted(Self.retryTimeFormatter))." } ?? ""
            return "Refresh paused — Starling rate limit reached.\(resumeText)"
        case StarlingAPIError.budgetExceeded(let resetsAt):
            return "Refresh paused — daily request limit reached. Resumes at \(resetsAt.formatted(Self.retryTimeFormatter))."
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

    /// Where the trend line (§3.5) says this tracker is actually headed,
    /// as its own labeled figure — detail-screen only, not added to the
    /// chart itself, which already draws the same trend visually. Colored
    /// green/red by whether that projection is trending toward or away
    /// from the tracker's real target, not the three-state amber/red
    /// `PaceStatus` split used elsewhere — this is a single "which way is
    /// it leaning" signal, not the live pace-vs-elapsed-time status.
    private func estimatedFinalBalanceCard(_ estimatedFinalValue: Decimal) -> some View {
        let difference = tracker.estimatedFinalDifference ?? 0
        let tint = difference >= 0 ? WiggleRoomColors.good : WiggleRoomColors.bad
        return card(tint: tint) {
            figureContent(
                title: "Estimated Final Balance",
                value: estimatedFinalValue,
                caption: estimatedFinalBalanceCaption(difference: difference)
            )
        }
        .padding(.horizontal)
    }

    private func estimatedFinalBalanceCaption(difference: Decimal) -> String {
        guard difference != 0 else { return "Right on target" }
        let verb = difference > 0 ? "under" : "over"
        return "Trending \(verb) target by \(tracker.formattedValue(abs(difference)))"
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
