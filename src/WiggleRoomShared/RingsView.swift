//
//  RingsView.swift
//  WiggleRoom
//

import SwiftUI
import Foundation

/// The primary two-ring visualization (§3.4), functionally accurate rather
/// than decorative:
/// - **Outer ring ("elapsed")** fills according to elapsed time within the
///   period. Always neutral graphite — it's a clock, not a status indicator.
/// - **Inner ring ("progress")** fills according to how much of the total
///   budget has actually been consumed so far. Colored traffic-light style
///   per `PaceStatus` (§3.2): green on track, amber near target, red needs
///   attention.
///
/// There are only ever these two rings — no more are added for additional
/// trackers or metrics. `showsCenterContent` hides the difference/status
/// overlay and legend for small indicator-sized uses (e.g. list rows),
/// where there isn't room for them to be legible.
///
/// Both rings spring in on first appearance, and fully **re-cycle** — drain
/// back to empty and refill, with a little overshoot bounce at the end —
/// any time their fraction changes afterwards (a live auto-refresh tick or a
/// newly logged/edited balance). Motion is where the personality lives; the
/// rings themselves are precise circles and the numbers are never anything
/// but exact (§3.4).
struct RingsView: View {
    let tracker: Tracker
    let now: Date
    var lineWidth: CGFloat = 20
    var showsCenterContent: Bool = true

    /// The fractions actually drawn on screen — deliberately separate from
    /// `paceFraction`/`actualFraction` (the real, current values) so the
    /// re-cycle animation can drive them through 0 and back up rather than
    /// just interpolating from old value to new.
    @State private var displayedPaceFraction: Double = 0
    @State private var displayedActualFraction: Double = 0

    /// True once the initial spring-in has run — guards against treating
    /// that first fill as a "change" that triggers a drain/refill cycle.
    @State private var hasAppeared = false

    /// Identifies the most recent recycle animation kicked off, so a second
    /// change arriving mid-drain doesn't leave a stale, now-outdated refill
    /// still scheduled to run after this one.
    @State private var recycleToken = UUID()

    /// A single value combining both real fractions, so one `onChange`
    /// handles "either changed" without risking two overlapping recycle
    /// animations firing for the same underlying update.
    private struct FractionKey: Equatable {
        let pace: Double
        let actual: Double
    }

    private var fractionKey: FractionKey {
        FractionKey(pace: paceFraction, actual: actualFraction)
    }

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    private var status: PaceStatus {
        pace.status
    }

    private var statusColor: Color { status.color }

    private var paceFraction: Double {
        guard pace.periodHours > 0 else { return 0 }
        return min(max(pace.hoursElapsed / pace.periodHours, 0), 1)
    }

    private var actualFraction: Double {
        guard tracker.totalAllowance != 0 else { return 0 }
        let ratio = pace.consumedSoFar / tracker.totalAllowance
        return min(max((ratio as NSDecimalNumber).doubleValue, 0), 1)
    }

    /// The gap between the outer and inner ring, scaled to `lineWidth`
    /// rather than a flat constant — a flat gap (previously `lineWidth +
    /// 10`) is barely noticeable on the 260pt dashboard but swallows nearly
    /// the whole inner ring at list-row/widget sizes (e.g. a 36pt row with
    /// `lineWidth: 5` was left with a 30pt total inset, shrinking the inner
    /// ring to an unreadable blob). Proportional to `lineWidth` keeps the
    /// same visual relationship at every size this view is used at.
    private var ringGap: CGFloat { lineWidth }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    ring(fraction: displayedPaceFraction, color: WiggleRoomColors.paceRing, showsCap: false)
                    ring(fraction: displayedActualFraction, color: statusColor, showsCap: lineWidth >= 12)
                        .padding(ringGap)

                    if showsCenterContent {
                        // Constrained to the ring's own inner diameter so long
                        // values shrink to fit instead of overflowing past it.
                        centerContent
                            .frame(width: side - ringGap * 2 - 24)
                    }
                }
                .frame(width: side, height: side)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .aspectRatio(1, contentMode: .fit)

            if showsCenterContent {
                legend
            }
        }
        .onAppear {
            // Deferred by a beat rather than animating immediately: a plain
            // `withAnimation` called from `onAppear` during a cold launch or
            // a programmatic push (e.g. opening straight into this screen
            // from a widget/Home Screen tap) can land inside the system's
            // own launch/transition transaction, which silently swallows
            // it — the rings would just appear already full with no
            // animation at all. Pushing the state change a fraction of a
            // second later, after that transaction has settled, makes the
            // very first fill-in animate reliably no matter how the screen
            // was opened.
            let paceTarget = paceFraction
            let actualTarget = actualFraction
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.68)) {
                    displayedPaceFraction = paceTarget
                    displayedActualFraction = actualTarget
                }
                hasAppeared = true
            }
        }
        .onChange(of: fractionKey) { _, newValue in
            guard hasAppeared else { return }
            recycle(paceTarget: newValue.pace, actualTarget: newValue.actual)
        }
    }

    /// Drains both rings back to empty, then refills them to the given
    /// targets with a spring that overshoots slightly before settling — a
    /// full "re-cycle" rather than a plain interpolation from old value to
    /// new, so a live refresh or a newly logged balance reads as a clear,
    /// deliberate moment rather than a subtle nudge. Takes a little over two
    /// seconds end to end.
    private func recycle(paceTarget: Double, actualTarget: Double) {
        let token = UUID()
        recycleToken = token
        withAnimation(.easeIn(duration: 0.4)) {
            displayedPaceFraction = 0
            displayedActualFraction = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // A newer change may have arrived and scheduled its own refill
            // while this one's drain was still playing — don't stomp on it.
            guard recycleToken == token else { return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.62)) {
                displayedPaceFraction = paceTarget
                displayedActualFraction = actualTarget
            }
        }
    }

    /// Below this fraction, a round-capped trimmed stroke's two end-caps
    /// overlap enough to render as a solid dot rather than a recognizable
    /// sliver of arc — exactly the range the recycle animation sweeps
    /// through on every drain and every refill. Fading the stroke (and the
    /// leading-edge cap) out across this range means the ring visibly
    /// empties and refills rather than shrinking to a stray dot and
    /// reappearing as one.
    private let dotFadeThreshold = 0.035

    private func progressOpacity(for fraction: Double) -> Double {
        guard fraction > 0 else { return 0 }
        return min(fraction / dotFadeThreshold, 1)
    }

    @ViewBuilder
    private var centerContent: some View {
        if tracker.latestReading != nil {
            VStack(spacing: 4) {
                Text(centerStatusLine.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
                Text(centerAmountText)
                    .font(.wiggleNumber(size: 32, weight: .bold))
                    .foregroundStyle(statusColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !tracker.usesBudgetLanguage || status == .warning {
                    Text("difference from target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No data yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var centerStatusLine: String {
        pace.statusLine(for: tracker)
    }

    private var centerAmountText: String {
        pace.displayDifference(for: tracker)
    }

    /// Uses the exact same wording as the figure cards below (§7.1's
    /// Current Balance/Target Right Now), in the same left-to-right order,
    /// so it's unambiguous which ring is which — not a separately-worded
    /// "Progress"/"Time elapsed" pair a reader has to map onto the figures
    /// themselves.
    private var legend: some View {
        HStack(spacing: 20) {
            legendItem(color: statusColor, label: tracker.currentValueLabel)
            legendItem(color: WiggleRoomColors.paceRing, label: "Target Right Now")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    /// Builds one ring: a full faint track plus a trimmed, colored progress
    /// stroke. `showsCap` adds a small solid dot at the progress stroke's
    /// leading edge (as Apple's own Activity rings do) — only at sizes where
    /// it reads as a deliberate detail rather than clutter.
    private func ring(fraction: Double, color: Color, showsCap: Bool) -> some View {
        let opacity = progressOpacity(for: fraction)
        return ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(opacity)
            if showsCap, fraction > dotFadeThreshold {
                GeometryReader { geo in
                    let radius = min(geo.size.width, geo.size.height) / 2
                    let angle = fraction * 2 * .pi
                    let point = CGPoint(
                        x: geo.size.width / 2 + radius * CGFloat(cos(angle)),
                        y: geo.size.height / 2 + radius * CGFloat(sin(angle))
                    )
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 0.86, height: lineWidth * 0.86)
                        .shadow(color: color.opacity(0.4), radius: 2, y: 1)
                        .position(point)
                        .opacity(opacity)
                }
            }
        }
        .rotationEffect(.degrees(-90))
    }
}

#Preview {
    RingsView(tracker: SharedPreviewData.makeSampleTracker(), now: .now)
        .frame(width: 260, height: 260)
        .padding()
}
