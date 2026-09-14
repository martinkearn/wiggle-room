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

    /// Traffic-light status (§3.2), within a small tolerance band around
    /// the target so being right on pace doesn't read as a hard pass/fail.
    /// `totalAllowance` sizes that tolerance relative to the tracker's own
    /// scale rather than an absolute amount.
    func status(totalAllowance: Decimal, toleranceFraction: Decimal = 0.05) -> PaceStatus {
        let tolerance = abs(totalAllowance) * toleranceFraction
        if abs(difference) <= tolerance {
            return .warning
        }
        return difference >= 0 ? .good : .bad
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
        let usesBudgetLanguage = tracker.direction == .decreasing && tracker.isCurrencyUnit
        switch self {
        case .good: return usesBudgetLanguage ? "Under Budget" : "On Track"
        case .warning: return usesBudgetLanguage ? "Near Budget" : "Near Target"
        case .bad: return usesBudgetLanguage ? "Over Budget" : "Needs Attention"
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
