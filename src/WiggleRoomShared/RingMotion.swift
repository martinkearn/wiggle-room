//
//  RingMotion.swift
//  WiggleRoom
//

import SwiftUI

/// Why the rings' fill changed, which decides how they move (§6, Ring
/// motion). Motion is where the app's personality lives, so the rings say
/// *why* they moved, not just *that* they moved: three causes, three
/// animations, never more than one playing at once.
nonisolated enum RingMotion: Equatable {
    /// The rings are arriving, or a change landed while the arrival was
    /// still in flight — which redirects the arrival rather than starting a
    /// second animation.
    case arrival
    /// A new latest reading: drain to empty and refill.
    case update
    /// The target moved but the reading did not: a small dip and wobble on
    /// whichever rings visibly moved.
    case drift(outer: Bool, inner: Bool)
    /// Nothing moved far enough to see. The drawn arc stays where it is.
    case settle

    /// Everything about a tracker that moves its rings. The reading is
    /// identified by id, not value, so re-logging the same figure is still
    /// an update.
    struct Key: Equatable {
        var outer: Double
        var inner: Double
        var readingID: UUID?
    }

    /// Below this change in either fraction the arc does not visibly move,
    /// so drift does not play — the ring equivalent of the pace-figure card
    /// only turning when its formatted figure changes.
    static let minimumDriftDelta = 0.0025

    /// Why the rings went from `old` to `new`. `old` is what they were last
    /// drawn at, not the previous value, so movement too small to show on
    /// its own still accumulates towards a drift. `hasArrived` is false
    /// until the arrival animation has finished.
    static func reason(from old: Key, to new: Key, hasArrived: Bool) -> RingMotion {
        guard hasArrived else { return .arrival }
        if old.readingID != new.readingID { return .update }
        let outer = abs(new.outer - old.outer) >= minimumDriftDelta
        let inner = abs(new.inner - old.inner) >= minimumDriftDelta
        return outer || inner ? .drift(outer: outer, inner: inner) : .settle
    }
}

// MARK: - Parameters

/// Starting points, tuned on a device rather than defended. Only the live
/// surfaces reach these; widgets and complications render a static snapshot
/// and never animate, so nothing random reaches them either.
extension RingMotion {
    /// Both rings grow from empty; the inner one follows the outer after a
    /// random lag, so the pair reads as drawn in sequence.
    static let arrivalSpring = Spring(response: 0.85, dampingRatio: 0.68)
    static let innerArrivalLag: ClosedRange<Double> = 0.04...0.09

    static let drainDuration = 0.4
    static let drain = Animation.easeIn(duration: drainDuration)
    static let refillSpring = Spring(response: 1.1, dampingRatio: 0.62)

    static let driftDip = 0.94
    static let driftDipDuration = 0.15
    static let driftReturnSpring = Spring(response: 0.5, dampingRatio: 0.55)
    /// The wobble peaks at this during the dip, then settles back to rest
    /// over `driftWobbleSettle` — about 0.6s end to end.
    static let driftWobble = 0.6
    static let driftWobbleSettle = Animation.easeInOut(duration: 0.45)
    /// Per surface and per play, so a list of rows never wobbles in unison.
    static let driftStagger: ClosedRange<Double> = 0...0.4

    /// While a refresh the user asked for is in flight, both outlines swing
    /// out to this wobble and back, 0.9s each way, in place of the system
    /// spinner — then settle to rest when it lands.
    static let refreshWobble = 0.5
    static let refreshWobbleSwing = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    static let refreshWobbleSettle = Animation.easeOut(duration: 0.4)

    static let statusFade = Animation.easeInOut(duration: 0.45)
    static let statusBeatScale: CGFloat = 1.06
    static let statusBeat = Animation.spring(response: 0.4, dampingFraction: 0.5)
    static let figureRoll = Animation.smooth(duration: 0.5)
}

extension Spring {
    /// This spring with its response and damping each nudged by up to ±10%,
    /// so repeated plays are never quite identical.
    func jittered() -> Spring {
        Spring(response: response * .random(in: 0.9...1.1),
               dampingRatio: dampingRatio * .random(in: 0.9...1.1))
    }
}

// MARK: - Figures and status

extension View {
    /// Draws `color` as the foreground style, cross-fading when it changes.
    /// Used for status colours, which only change when the status does, so
    /// the pace line being crossed reads as an event rather than a swap.
    /// Scoped to the colour alone, so nothing else in the view picks up the
    /// fade. Kept under Reduce Motion, which asks for a fade in place of
    /// movement rather than for the change to be hidden.
    func crossFadingForeground(_ color: Color, isEnabled: Bool = true) -> some View {
        animation(isEnabled ? RingMotion.statusFade : nil) { $0.foregroundStyle(color) }
    }

    /// One beat of emphasis when `status` changes: a single spring up to a
    /// slightly larger scale and back, never a repeating pulse. Keyed on the
    /// status itself, so an ordinary re-render cannot set it off. Nothing
    /// under Reduce Motion.
    func paceStatusBeat(_ status: PaceStatus, isEnabled: Bool = true) -> some View {
        modifier(PaceStatusBeat(status: status, isEnabled: isEnabled))
    }

    /// Rolls a live figure's digits when it changes, downwards for a falling
    /// value and upwards for a rising one. `text` is what the figure shows;
    /// the animation is keyed on it because nothing that moves these figures
    /// (the pace clock, a reading arriving through SwiftData) changes them
    /// inside an animation of its own, and a content transition only plays
    /// inside one. Figures simply swap under Reduce Motion.
    func rollingFigure(_ value: Decimal?, text: String, isEnabled: Bool = true) -> some View {
        modifier(RollingFigure(value: value.map { NSDecimalNumber(decimal: $0).doubleValue },
                               text: text, isEnabled: isEnabled))
    }
}

private struct PaceStatusBeat: ViewModifier {
    let status: PaceStatus
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isEnabled && !reduceMotion {
            content.phaseAnimator([1, RingMotion.statusBeatScale], trigger: status) { view, scale in
                view.scaleEffect(scale)
            } animation: { _ in
                RingMotion.statusBeat
            }
        } else {
            content
        }
    }
}

private struct RollingFigure: ViewModifier {
    let value: Double?
    let text: String
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isEnabled && !reduceMotion {
            content
                .contentTransition(value.map { .numericText(value: $0) } ?? .numericText())
                .animation(RingMotion.figureRoll, value: text)
        } else {
            content
        }
    }
}
