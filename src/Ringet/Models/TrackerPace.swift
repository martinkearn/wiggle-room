//
//  TrackerPace.swift
//  Ringet
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

    /// `difference >= 0` means ahead of pace; `< 0` means behind.
    var isAheadOfPace: Bool { difference >= 0 }

    /// Traffic-light status (§3.2): below, at, or above the target.
    /// "At" is an exact match on the whole-number part only (pennies/cents
    /// don't count) — not a percentage tolerance band, so it's only true
    /// when the current value has genuinely landed on the target.
    var status: PaceStatus {
        let currentWhole = (currentValue as NSDecimalNumber).intValue
        let targetWhole = (targetValueToday as NSDecimalNumber).intValue
        if currentWhole == targetWhole {
            return .warning
        }
        return difference >= 0 ? .good : .bad
    }

    /// The at-a-glance difference figure, formatted for `tracker`. For a
    /// budget tracker that's genuinely over or under (not just at), this
    /// drops the +/- sign: the color and status word already say which
    /// direction, so a sign on top of that is redundant, not clarifying.
    func displayDifference(for tracker: Tracker) -> String {
        guard tracker.usesBudgetLanguage, status != .warning else {
            return tracker.formattedValue(difference, signed: true)
        }
        return tracker.formattedValue(abs(difference))
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
        case .good: RingetColors.good
        case .warning: RingetColors.warning
        case .bad: RingetColors.bad
        }
    }

    /// A decreasing tracker denominated in currency reads naturally as a
    /// budget ("under/over budget"), which draws a much clearer good/bad
    /// line for money than the generic on-track language does. Every other
    /// tracker shape (increasing, or non-currency units like mileage) keeps
    /// the neutral wording.
    func label(for tracker: Tracker) -> String {
        switch self {
        case .good: return tracker.usesBudgetLanguage ? "Under Budget" : "On Track"
        case .warning: return tracker.usesBudgetLanguage ? "At Budget" : "At Target"
        case .bad: return tracker.usesBudgetLanguage ? "Over Budget" : "Needs Attention"
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
            targetValueToday: targetValueToday
        )
    }
}
