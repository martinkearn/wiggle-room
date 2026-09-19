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
/// overlay for small indicator-sized uses (e.g. list rows), where there
/// isn't room for it to be legible. No separate color key is drawn below
/// the rings — the figure cards elsewhere on screen (Current Balance,
/// Current Budget) already use these exact same two colors, so a legend
/// here would just be repeating what's already unambiguous at a glance.
///
/// Both rings spring in on first appearance, and fully **re-cycle** — drain
/// back to empty and refill, with a little overshoot bounce at the end —
/// any time their fraction changes afterwards (a live auto-refresh tick or a
/// newly logged/edited balance). Motion is where the personality lives; the
/// rings are hand-wobbled outlines (the app icon's own, `IconRingShape`),
/// trimmed by arc length so their fill is still exact, and the numbers are
/// never anything but exact (§3.4).
struct RingsView: View {
    let tracker: Tracker
    let now: Date
    var lineWidth: CGFloat = 20
    var showsCenterContent: Bool = true

    /// Whether the center content's status-word line ("JUST OVER BUDGET")
    /// and its "difference from budget" caption are shown alongside the
    /// number. The number itself (`centerAmountText`) always shows
    /// whenever `showsCenterContent` is true — this only controls the
    /// surrounding label text. `false` for the macOS menu bar dropdown
    /// (`MenuBarStatusView`), where the same status word and figure
    /// already appear in the rows directly below the ring, so repeating
    /// the word specifically (not the number, which isn't repeated
    /// elsewhere in that compact context) would be pure duplication.
    var showsStatusLabel: Bool = true

    /// Widgets render from a static `TimelineEntry` snapshot rather than a
    /// live SwiftUI runloop — WidgetKit captures the view's appearance
    /// essentially immediately, well before a deferred `onAppear` animation
    /// would ever get a chance to run, so the rings would render frozen at
    /// their starting fraction of 0 (empty) rather than the real value.
    /// Pass `false` there to skip all of the appear/recycle machinery below
    /// and just show the real fraction immediately, at full opacity, with no
    /// animation — a plain, correct ring rather than a blank one.
    var isAnimated: Bool = true

    /// Whether the rings spring in from empty when the view first appears.
    /// The tracker detail screen turns this off: it refreshes itself on open,
    /// and that refresh's own drain-and-refill animation is the one intended
    /// "arrival" effect, so also animating the initial draw played it twice.
    var animatesOnAppear: Bool = true

    /// The fractions actually drawn on screen — deliberately separate from
    /// `paceFraction`/`actualFraction` (the real, current values) so the
    /// re-cycle animation can drive them through 0 and back up rather than
    /// just interpolating from old value to new.
    @State private var displayedPaceFractionState: Double?
    @State private var displayedActualFractionState: Double?

    /// Until the first appear-animation runs these fall back to empty (when
    /// animating in) or straight to the real value (when not).
    private var displayedPaceFraction: Double {
        displayedPaceFractionState ?? (animatesOnAppear ? 0 : paceFraction)
    }
    private var displayedActualFraction: Double {
        displayedActualFractionState ?? (animatesOnAppear ? 0 : actualFraction)
    }

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

    /// How far the inner ring is inset from the outer one (applied as
    /// `.padding`, which shrinks the inner ring's *radius* by this amount).
    /// Each ring's stroke extends `lineWidth / 2` to either side of its own
    /// center-line radius, so the two rings' painted bands only actually
    /// stay clear of each other once this inset exceeds a full `lineWidth`
    /// — anything less and the inner ring's outer edge is drawn underneath
    /// the outer ring's band, not next to it. `bandGap` below is the real,
    /// visible gap between the two bands once that's accounted for: a thin
    /// sliver proportional to `lineWidth`, matching how close together
    /// Apple's own Fitness rings sit, rather than the flat `lineWidth` of
    /// dead space a naive equal inset leaves behind.
    private var bandGap: CGFloat { lineWidth * 0.25 }
    private var ringGap: CGFloat { lineWidth + bandGap }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    ring(.outer, fraction: isAnimated ? displayedPaceFraction : paceFraction, color: WiggleRoomColors.paceRing)
                    ring(.inner, fraction: isAnimated ? displayedActualFraction : actualFraction, color: statusColor)
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
        }
        .onAppear {
            guard isAnimated else { return }
            guard animatesOnAppear else {
                hasAppeared = true
                return
            }
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
                    displayedPaceFractionState = paceTarget
                    displayedActualFractionState = actualTarget
                }
                hasAppeared = true
            }
        }
        .onChange(of: fractionKey) { _, newValue in
            guard isAnimated, hasAppeared else { return }
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
            displayedPaceFractionState = 0
            displayedActualFractionState = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            // A newer change may have arrived and scheduled its own refill
            // while this one's drain was still playing — don't stomp on it.
            guard recycleToken == token else { return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.62)) {
                displayedPaceFractionState = paceTarget
                displayedActualFractionState = actualTarget
            }
        }
    }

    /// Below this fraction, a round-capped trimmed stroke's two end-caps
    /// overlap enough to render as a solid dot rather than a recognizable
    /// sliver of arc — exactly the range the recycle animation sweeps
    /// through on every drain and every refill. Fading the stroke out across
    /// this range means the ring visibly empties and refills rather than
    /// shrinking to a stray dot and reappearing as one.
    private let dotFadeThreshold = 0.035

    private func progressOpacity(for fraction: Double) -> Double {
        // The fade only exists to hide a transient rendering artifact during
        // the animated drain/refill — a static (widget) rendering shows
        // whatever the real fraction is, faithfully, even if that's small.
        guard isAnimated else { return fraction > 0 ? 1 : 0 }
        guard fraction > 0 else { return 0 }
        return min(fraction / dotFadeThreshold, 1)
    }

    @ViewBuilder
    private var centerContent: some View {
        if tracker.latestReading != nil {
            VStack(spacing: 4) {
                if showsStatusLabel {
                    Text(centerStatusLine.uppercased())
                        .font(.wiggleText(.caption, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.center)
                }
                Text(centerAmountText)
                    .font(.wiggleNumber(size: 32, weight: .bold))
                    .foregroundStyle(statusColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if showsStatusLabel && (!tracker.usesBudgetLanguage || status == .warning) {
                    Text("difference from budget")
                        .font(.wiggleText(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No data yet")
                .font(.wiggleText(.subheadline))
                .foregroundStyle(.secondary)
        }
    }

    private var centerStatusLine: String {
        pace.statusLine(for: tracker)
    }

    private var centerAmountText: String {
        pace.displayDifference(for: tracker)
    }

    /// Builds one ring: a full faint track plus a trimmed, colored progress
    /// stroke, round-capped for a soft leading edge (as Apple's own Activity
    /// rings have). Deliberately *not* a separate dot layered on top at the
    /// stroke's tip — a plain view positioned via trigonometry off of
    /// `fraction` doesn't interpolate in lockstep with the trimmed shape's
    /// own animation (`Shape.trim` is animated natively by SwiftUI; a
    /// `.position()` computed in a `GeometryReader` is not, in practice, kept
    /// perfectly in sync with it), so during the recycle animation the two
    /// visibly drifted apart — a floating dot detached from the arc's actual
    /// tip. The round line cap alone gives the same soft-tip look with no
    /// second, separately-animated element that can desync.
    /// A ring that's essentially closed gets a short extra arc laid on top
    /// of its own start, overlapping itself by this fraction — matching how
    /// Apple's own Fitness rings visibly lap their starting point once a
    /// ring closes, rather than the two round caps just meeting edge-to-edge.
    /// This is purely a per-ring, self-overlap effect — it has nothing to do
    /// with (and shouldn't be confused with) the outer/inner ring's own
    /// separation, which `ringGap`/`bandGap` above control.
    private let closureOverlapFraction = 0.025

    /// Shown from just shy of 100% rather than only at an exact 1.0 —
    /// Fitness's own rings reveal their closing overlap slightly before the
    /// ring is mathematically complete, and waiting for an exact match here
    /// would also risk never firing at all given `fraction`'s Decimal →
    /// Double conversion.
    private let closureThreshold = 0.98

    private func ring(_ kind: IconRingShape.Ring, fraction: Double, color: Color) -> some View {
        let opacity = progressOpacity(for: fraction)
        let isClosed = fraction >= closureThreshold
        let shape = IconRingShape(ring: kind, fitsRect: true)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        return ZStack {
            shape
                // The empty part of each ring wears the tracker's own colour;
                // the filled arc keeps its clock/status colour.
                .stroke(tracker.accentColor.opacity(0.24), style: style)
            shape
                .trim(from: 0, to: fraction)
                .stroke(color, style: style)
                .opacity(opacity)
            if isClosed {
                shape
                    .trim(from: 0, to: closureOverlapFraction)
                    .stroke(color, style: style)
                    .opacity(opacity)
            }
        }
    }
}

#Preview {
    RingsView(tracker: SharedPreviewData.makeSampleTracker(), now: .now)
        .frame(width: 260, height: 260)
        .padding()
}
