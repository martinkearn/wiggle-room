//
//  TrackerPace.swift
//  WiggleRoom
//

import Foundation
import SwiftUI

/// A snapshot of a tracker's derived pace calculations at a single point in
/// time, given an `actualValue` read from its source. See spec §4.3.
///
/// All fields are computed together from one `asOf` instant so they stay
/// mutually consistent, rather than being separate computed properties that
/// would each implicitly capture a different `Date()`.
struct TrackerPace: Equatable {
    let periodHours: Double
    let hoursElapsed: Double
    let consumedSoFar: Decimal
    let expectedConsumedByNow: Decimal
    let difference: Decimal

    /// The `actualValue` this snapshot was computed from, in the tracker's
    /// own terms.
    let currentValue: Decimal

    /// Where the tracked value should be right now to be exactly on pace,
    /// in the tracker's own terms (e.g. "target balance today").
    let targetValueToday: Decimal

    /// The tracker's total allowance for the period — carried alongside the
    /// other figures so `status` can express "behind" as a percentage of
    /// the whole, rather than an absolute amount that means very different
    /// things for a £50 tracker and a £5,000 one.
    let totalAllowance: Decimal

    /// `difference >= 0` means ahead of pace; `< 0` means behind.
    var isAheadOfPace: Bool { difference >= 0 }

    /// How far behind pace, as a percentage of the total allowance —
    /// `0` when on pace or ahead.
    private var percentBehind: Double {
        guard totalAllowance != 0 else { return 0 }
        let behindAmount = max(-difference, 0)
        return ((behindAmount / abs(totalAllowance)) as NSDecimalNumber).doubleValue * 100
    }

    /// Traffic-light status (§3.2): on pace, drifting behind, or badly
    /// behind. Amber is a genuine early-warning band — behind pace by up to
    /// 5% of the total allowance — not an exact "landed on the target"
    /// match: ahead of pace, or exactly on it, reads as green; behind by
    /// more than 5% reads as red. Unlike the amber/red split, there's no
    /// grace zone before green turns amber — any shortfall at all, however
    /// small a percentage of the total allowance, means the actual figure
    /// has already slipped behind the target figure shown right next to
    /// it, and showing that pair as "green"/"on track" would contradict
    /// what's plainly printed on screen.
    var status: PaceStatus {
        guard difference < 0 else { return .good }
        return percentBehind > 5 ? .bad : .warning
    }

    /// The at-a-glance difference figure, formatted for `tracker`. For a
    /// budget tracker that's genuinely over or under (not just at), this
    /// drops the +/- sign: the color and status word already say which
    /// direction, so a sign on top of that is redundant, not clarifying.
    ///
    /// For an increasing tracker, `difference` itself is negated first —
    /// `difference` is "expected minus actual," so a positive `difference`
    /// already reads naturally as a plus for a decreasing tracker (using
    /// less than planned, a good thing), but for an increasing tracker a
    /// positive `difference` means using *less* than planned too, which is
    /// still the good case — the sign convention users actually expect,
    /// though, mirrors direction: over the target (the bad case, a higher
    /// actual number) shown without a minus, under it (the good case, a
    /// lower actual number) shown with one.
    func displayDifference(for tracker: Tracker) -> String {
        let orientedDifference = tracker.direction == .increasing ? -difference : difference
        guard tracker.usesBudgetLanguage, status != .warning else {
            return tracker.formattedValue(orientedDifference, signed: true)
        }
        return tracker.formattedValue(abs(difference))
    }

    /// The status wording shown alongside the difference figure — "Over
    /// Budget by", "Under Budget by" for a budget tracker that's genuinely
    /// over/under (not just close), or the plain status label otherwise.
    /// Shared by the dashboard ring's center content and the tracker list
    /// row so the two read identically rather than the list using a bare
    /// number with no status word at all.
    func statusLine(for tracker: Tracker) -> String {
        let label = status.label(for: tracker)
        guard tracker.usesBudgetLanguage, status != .warning else { return label }
        return "\(label) by"
    }

    /// How much of the total allowance is left to use *right now* — e.g.
    /// "£100 left in this budget" after spending £400 of a £500 budget.
    /// This moves as readings come in, unlike `Tracker.projectedRemainder`,
    /// which projects a fixed starting-value-vs-budget gap independent of
    /// actual spending. `nil` once the allowance is already used up or
    /// exceeded — the ring/status wording already covers being over.
    func remainingInAllowanceCaption(for tracker: Tracker) -> String? {
        let remaining = totalAllowance - consumedSoFar
        guard remaining > 0 else { return nil }
        let formatted = tracker.formattedValue(remaining)
        return tracker.usesBudgetLanguage ? "\(formatted) left in this budget" : "\(formatted) left to use"
    }
}

/// Traffic-light reading of a tracker's pace (§3.2), independent of
/// direction — `.good` always means "green", regardless of whether that's a
/// decreasing tracker running under budget or an increasing one running
/// under its cap.
enum PaceStatus {
    case good
    case warning
    case bad

    var color: Color {
        switch self {
        case .good: WiggleRoomColors.good
        case .warning: WiggleRoomColors.warning
        case .bad: WiggleRoomColors.bad
        }
    }

    /// A decreasing tracker denominated in currency reads naturally as a
    /// budget ("under/over budget"), which draws a much clearer good/bad
    /// line for money than the generic on-track language does. An
    /// increasing tracker (regardless of unit — mileage included) reads
    /// just as naturally as a budget once it's over: a higher number than
    /// planned literally *is* going over whatever cap the allowance
    /// represents, so the warning/bad wording matches the decreasing
    /// budget case even though `usesBudgetLanguage` itself only covers
    /// decreasing currency trackers. Only a non-currency decreasing
    /// tracker keeps the neutral "on track"/"needs attention" wording.
    func label(for tracker: Tracker) -> String {
        switch self {
        case .good:
            return tracker.usesBudgetLanguage ? "Under Budget" : "On Track"
        case .warning:
            if tracker.usesBudgetLanguage { return "Just Over Budget" }
            return tracker.direction == .increasing ? "Slightly Over Budget" : "Slightly Behind"
        case .bad:
            if tracker.usesBudgetLanguage { return "Over Budget" }
            return tracker.direction == .increasing ? "Over Budget" : "Needs Attention"
        }
    }
}

extension Tracker {
    /// Computes this tracker's pace given its current `actualValue` (§4.2)
    /// as of a given instant (defaults to now).
    ///
    /// `hoursElapsed` is derived from `timeIntervalSince`, i.e. real elapsed
    /// wall-clock seconds, never calendar-component subtraction — so a
    /// period spanning a DST transition is not distorted by the local
    /// calendar day gaining or losing an hour.
    func pace(actualValue: Decimal, asOf: Date = Date()) -> TrackerPace {
        let periodHours = endDate.timeIntervalSince(startDate) / 3600

        let hoursElapsed: Double
        if periodHours > 0 {
            let rawHours = asOf.timeIntervalSince(startDate) / 3600
            hoursElapsed = min(max(rawHours, 0), periodHours)
        } else {
            // Degenerate zero-length (or inverted) period: there is no pace
            // to measure partway through, only "not yet" or "already".
            hoursElapsed = 0
        }

        let consumedSoFar: Decimal
        switch direction {
        case .decreasing:
            consumedSoFar = startingValue - actualValue
        case .increasing:
            consumedSoFar = actualValue - startingValue
        }

        let paceFraction: Double
        if periodHours > 0 {
            paceFraction = hoursElapsed / periodHours
        } else {
            paceFraction = asOf >= startDate ? 1 : 0
        }

        let expectedConsumedByNow = totalAllowance * Decimal(paceFraction)
        let difference = expectedConsumedByNow - consumedSoFar

        let targetValueToday: Decimal
        switch direction {
        case .decreasing:
            targetValueToday = startingValue - expectedConsumedByNow
        case .increasing:
            targetValueToday = startingValue + expectedConsumedByNow
        }

        return TrackerPace(
            periodHours: periodHours,
            hoursElapsed: hoursElapsed,
            consumedSoFar: consumedSoFar,
            expectedConsumedByNow: expectedConsumedByNow,
            difference: difference,
            currentValue: actualValue,
            targetValueToday: targetValueToday,
            totalAllowance: totalAllowance
        )
    }
}

extension Tracker {
    /// The tracker's final, whole-period `PaceStatus` once its period has
    /// actually ended — `nil` before `endDate`, or if there's no reading yet
    /// to judge it by. Pinned to `endDate` itself rather than whatever "now"
    /// is well after completion, so the answer stays stable no matter how
    /// long after closing the tracker is actually looked at. Used to decide
    /// whether a tracker's completion deserves the celebration in
    /// `TrackerDetailView`.
    func finalPaceStatus(asOf now: Date) -> PaceStatus? {
        guard now >= endDate, let latest = latestReading else { return nil }
        return pace(actualValue: latest.value, asOf: endDate).status
    }
}
