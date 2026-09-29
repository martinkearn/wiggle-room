//
//  RingsView.swift
//  WiggleRoom
//

import SwiftUI
import Foundation
import SwiftData

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
/// The rings move differently depending on *why* their fill changed (§6,
/// `RingMotion`): they grow from empty when the tracker is opened, drain
/// and refill when a new reading lands, and dip and wobble briefly when only
/// the target has drifted. Motion is where the personality lives; the rings
/// are hand-wobbled outlines (the app icon's own, `IconRingShape`), trimmed
/// by arc length so their fill is still exact, and the numbers are never
/// anything but exact (§3.4).
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
    /// Pass `false` there to skip all of the motion machinery below and
    /// just show the real fraction immediately, at full opacity, with no
    /// animation — a plain, correct ring rather than a blank one. Nothing
    /// random reaches that path, so a widget re-rendering can't flicker.
    var isAnimated: Bool = true

    /// True while a refresh the user asked for is in flight (a pull, or the
    /// macOS Update button): both outlines hold a slow wobble in place of
    /// the system spinner, settling when the fetch lands. Separate from the
    /// drift's own wobble, which adds on top. Still under Reduce Motion, and
    /// never on a snapshot.
    var isRefreshing = false

    /// The fractions actually drawn on screen — deliberately separate from
    /// `paceFraction`/`actualFraction` (the real, current values) so the
    /// animations can take them somewhere other than straight to the new
    /// value: through empty for an update, a little below it for a drift.
    /// `nil` until the arrival starts, drawing as empty until then (or as
    /// the real value under Reduce Motion, which has no arrival).
    @State private var drawnOuterState: Double?
    @State private var drawnInnerState: Double?

    private var drawnOuter: Double {
        drawnOuterState ?? (reduceMotion ? paceFraction : 0)
    }
    private var drawnInner: Double {
        drawnInnerState ?? (reduceMotion ? actualFraction : 0)
    }

    /// Each ring's `IconRingShape.wobble`, which only leaves its resting 0
    /// during a drift.
    @State private var outerWobble = 0.0
    @State private var innerWobble = 0.0

    /// The refresh's own wobble (`isRefreshing`), added to both rings'.
    @State private var refreshWobble = 0.0

    /// What the rings were last sent to, and so what the next change is
    /// measured against (`RingMotion.reason`). `nil` until the arrival
    /// starts.
    @State private var drawnKey: RingMotion.Key?

    /// The newest key seen, for the deferred arrival to read: its closure
    /// holds a copy of this view from before the deferral, whose `now` may
    /// already be out of date.
    @State private var latestKey: RingMotion.Key?

    /// False until the arrival animation has settled. A change landing
    /// before then redirects the arrival rather than starting a second
    /// animation.
    @State private var hasArrived = false

    /// Identifies the most recent motion kicked off, so a second change
    /// arriving mid-animation doesn't leave a stale, now-outdated step (an
    /// update's refill, a drift's dip or return, the arrival settling) still
    /// scheduled to run behind the newer one.
    @State private var motionToken = UUID()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Everything that moves the rings, in one value so a single `onChange`
    /// sees every change and `RingMotion.reason` can say which kind it was.
    private var motionKey: RingMotion.Key {
        RingMotion.Key(outer: paceFraction, inner: actualFraction, readingID: tracker.latestReading?.id)
    }

    private var fractions: RingFractions {
        tracker.ringFractions(asOf: now)
    }

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    private var status: PaceStatus {
        pace.status
    }

    private var statusColor: Color { status.color }

    private var paceFraction: Double {
        fractions.elapsed
    }

    private var actualFraction: Double {
        fractions.consumed
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
        // `tracker` can be a stale reference to a row that's mid-deletion —
        // its own `@Query` (e.g. `TrackerListView`'s) republishes
        // asynchronously relative to the actual delete/CloudKit-merge, so
        // there's a real window where this view re-renders with a
        // `Tracker` whose backing data has already been detached from its
        // context. Reading any property on it then (`pace`, `direction`,
        // …) is a hard, unrecoverable SwiftData crash, not a catchable
        // error — found via real crash reports (`RingsView.pace` →
        // `Tracker.direction.getter` → SwiftData `_assertionFailure`) on
        // both iOS and macOS. Same guard, same reasoning, as
        // `TrackerDetailView`'s own top-level check.
        if tracker.modelContext == nil {
            Color.clear
        } else {
            ringsBody
        }
    }

    private var ringsBody: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    ring(.outer, fraction: isAnimated ? drawnOuter : paceFraction, target: paceFraction,
                         wobble: outerWobble + refreshWobble, color: WiggleRoomColors.paceRing)
                    ring(.inner, fraction: isAnimated ? drawnInner : actualFraction, target: actualFraction,
                         wobble: innerWobble + refreshWobble, color: statusColor)
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
            // Once per view: a row scrolled back into view, or a screen
            // navigated back to, keeps its rings as they are.
            guard isAnimated, latestKey == nil else { return }
            let key = motionKey
            latestKey = key
            guard !reduceMotion else {
                // Drawn at the final value, with no growth.
                snap(to: key)
                hasArrived = true
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard drawnKey == nil, let key = latestKey else { return }
                arrive(at: key)
            }
        }
        .onChange(of: motionKey) { _, key in
            guard isAnimated else { return }
            latestKey = key
            // Before the arrival starts, it simply picks up the newest key.
            guard let drawnKey else { return }
            let reason = RingMotion.reason(from: drawnKey, to: key, hasArrived: hasArrived)
            guard reason != .settle else { return }
            guard !reduceMotion else {
                // Straight to the new value: no drain, no drift, no slide.
                snap(to: key)
                return
            }
            switch reason {
            case .arrival: arrive(at: key, retargeting: true)
            case .update: update(to: key)
            case let .drift(outer, inner): drift(from: drawnKey, to: key, outer: outer, inner: inner)
            case .settle: break
            }
        }
        .onChange(of: isRefreshing, initial: true) { _, isRefreshing in
            guard isAnimated, !reduceMotion else { return }
            // A new animation on the same value replaces the repeating one,
            // so the swing settles from wherever it had reached.
            withAnimation(isRefreshing ? RingMotion.refreshWobbleSwing : RingMotion.refreshWobbleSettle) {
                refreshWobble = isRefreshing ? RingMotion.refreshWobble : 0
            }
        }
    }

    /// The tracker was opened: both rings grow from empty with an overshoot
    /// spring, the inner one a random beat behind the outer so the pair
    /// reads as drawn in sequence rather than stamped on at once.
    /// `retargeting` redirects an arrival already in flight to a newer
    /// value: opening a connected tracker refreshes it straight away, and a
    /// new balance landing mid-growth should change where the rings grow to,
    /// not play a second animation after the first.
    private func arrive(at key: RingMotion.Key, retargeting: Bool = false) {
        let token = UUID()
        motionToken = token
        drawnKey = key
        let spring = RingMotion.arrivalSpring.jittered()
        let lag = retargeting ? 0 : Double.random(in: RingMotion.innerArrivalLag)
        withAnimation(.spring(spring)) {
            drawnOuterState = key.outer
        }
        withAnimation(.spring(spring).delay(lag)) {
            drawnInnerState = key.inner
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + lag + spring.settlingDuration) {
            guard motionToken == token else { return }
            hasArrived = true
        }
    }

    /// Reduce Motion: straight to the value, with nothing in between.
    private func snap(to key: RingMotion.Key) {
        motionToken = UUID()
        drawnKey = key
        withTransaction(\.disablesAnimations, true) {
            drawnOuterState = key.outer
            drawnInnerState = key.inner
            outerWobble = 0
            innerWobble = 0
        }
    }

    /// A new reading landed: drain both rings back to empty, then refill
    /// them with a spring that overshoots slightly before settling — a full
    /// cycle rather than a plain interpolation from old value to new, so a
    /// real change of data reads as a clear, deliberate moment rather than a
    /// subtle nudge. A little over two seconds end to end.
    private func update(to key: RingMotion.Key) {
        let token = UUID()
        motionToken = token
        drawnKey = key
        withAnimation(RingMotion.drain) {
            drawnOuterState = 0
            drawnInnerState = 0
            outerWobble = 0
            innerWobble = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + RingMotion.drainDuration) {
            // A newer change may have arrived and started its own motion
            // while this one's drain was still playing — don't stomp on it.
            guard motionToken == token else { return }
            withAnimation(.spring(RingMotion.refillSpring.jittered())) {
                drawnOuterState = key.outer
                drawnInnerState = key.inner
            }
        }
    }

    /// The target moved but the reading didn't, so never from empty: each
    /// ring that visibly moved dips a few percent below where it was drawn
    /// and springs to its new value while its outline's wobble swells and
    /// settles, so the line looks briefly redrawn by hand. Subtle enough to
    /// notice only if you're looking at it. Starts after a random stagger so
    /// rows sharing one clock tick don't wobble in unison.
    private func drift(from old: RingMotion.Key, to key: RingMotion.Key, outer: Bool, inner: Bool) {
        let token = UUID()
        motionToken = token
        drawnKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: RingMotion.driftStagger)) {
            guard motionToken == token else { return }
            withAnimation(.easeOut(duration: RingMotion.driftDipDuration)) {
                if outer {
                    drawnOuterState = old.outer * RingMotion.driftDip
                    outerWobble = RingMotion.driftWobble
                }
                if inner {
                    drawnInnerState = old.inner * RingMotion.driftDip
                    innerWobble = RingMotion.driftWobble
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + RingMotion.driftDipDuration) {
                guard motionToken == token else { return }
                withAnimation(.spring(RingMotion.driftReturnSpring.jittered())) {
                    drawnOuterState = key.outer
                    drawnInnerState = key.inner
                }
                withAnimation(RingMotion.driftWobbleSettle) {
                    outerWobble = 0
                    innerWobble = 0
                }
            }
        }
    }

    /// Below this fraction, a round-capped trimmed stroke's two end-caps
    /// overlap enough to render as a solid dot rather than a recognizable
    /// sliver of arc — exactly the range the arrival and update animations
    /// sweep through on every drain and every fill. Fading the stroke out across
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
                        .multilineTextAlignment(.center)
                        .crossFadingForeground(statusColor, isEnabled: isAnimated)
                        .paceStatusBeat(status, isEnabled: isAnimated)
                }
                Text(centerAmountText)
                    .font(.wiggleNumber(size: 32, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .crossFadingForeground(statusColor, isEnabled: isAnimated)
                    .rollingFigure(pace.displayedDifference, text: centerAmountText, isEnabled: isAnimated)
                if showsStatusLabel && status == .warning {
                    Text(tracker.terminology.differenceCaption)
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
    /// perfectly in sync with it), so during the update animation the two
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

    /// `fraction` is what's drawn, `target` the real value it's heading for.
    private func ring(_ kind: IconRingShape.Ring, fraction: Double, target: Double, wobble: Double, color: Color) -> some View {
        let opacity = progressOpacity(for: fraction)
        // Latched on the target rather than the drawn fraction, so a full
        // ring's overlap holds steady through a drift's dip below
        // `closureThreshold` instead of popping off and back on. An update's
        // drain genuinely empties the ring, so it still loses it there.
        let isClosed = target >= closureThreshold && fraction > 0
        let shape = IconRingShape(ring: kind, fitsRect: true, wobble: wobble)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        return ZStack {
            shape
                // The empty part of each ring wears the tracker's own colour;
                // the filled arc keeps its clock/status colour. `reference`
                // rather than `accentColor`, since the track sits directly
                // beneath the status-coloured arc — a red tracker's track
                // under a red arc read as one washed-out ring rather than as
                // a track and its fill (see `TrackerPalette`).
                .stroke(tracker.referenceColor.opacity(0.24), style: style)
            shape
                .trim(from: 0, to: fraction)
                .stroke(style: style)
                .crossFadingForeground(color, isEnabled: isAnimated)
                .opacity(opacity)
            if isClosed {
                shape
                    .trim(from: 0, to: closureOverlapFraction)
                    .stroke(style: style)
                    .crossFadingForeground(color, isEnabled: isAnimated)
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
