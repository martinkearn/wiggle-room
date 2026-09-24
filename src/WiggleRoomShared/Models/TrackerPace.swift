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

    /// Expected consumption minus actual — how much of the allowance is
    /// still unspent relative to the clock. Still the figure the ring fill
    /// and the chart are built from, but **not** the one that decides
    /// good/bad: consumption is the *point* for a goal type (saving, losing
    /// weight), so consuming faster than planned is the good case there.
    /// `goodness` is the polarity-aware figure.
    let difference: Decimal

    /// The `actualValue` this snapshot was computed from, in the tracker's
    /// own terms.
    let currentValue: Decimal

    /// Where the tracked value should be right now to be exactly on pace,
    /// in the tracker's own terms (e.g. "target balance today").
    let targetValueToday: Decimal

    /// The tracker's total allowance for the period — carried alongside the
    /// other figures so `amberBand` can express "drifting" as a proportion
    /// of the whole, rather than an absolute amount that means very
    /// different things for a £50 tracker and a £5,000 one.
    let totalAllowance: Decimal

    /// Which side of the pace line is the good side, from the tracker's type.
    let higherIsBetter: Bool

    /// The narrowest the amber band may be, from the tracker's unit.
    let amberFloor: Decimal

    /// How far ahead of pace the tracker is, in its own units, with the
    /// tracker's polarity already applied — the single sign flip that
    /// replaces every `direction ==` branch the wording used to carry.
    ///
    /// `>= 0` is on or ahead of pace. For a decreasing "higher is better"
    /// tracker (Spending) this reduces algebraically to
    /// `expectedConsumedByNow - consumedSoFar`, so that type's behaviour is
    /// unchanged; for Saving and Weight loss it inverts, which is exactly the
    /// bug it exists to fix (a savings balance £400 above target used to read
    /// red).
    var goodness: Decimal {
        higherIsBetter ? currentValue - targetValueToday : targetValueToday - currentValue
    }

    /// `goodness >= 0` means ahead of pace; `< 0` means behind.
    var isAheadOfPace: Bool { goodness >= 0 }

    /// The early-warning band (§7): 5% of the whole allowance, but never
    /// narrower than the unit's own floor.
    ///
    /// In practice only weight is affected. Day-to-day body weight swings
    /// about ±1 kg from water, food in transit and sodium, so a bare 5% band
    /// (0.5 kg on a 10 kg goal) would show red — the app's loudest signal —
    /// for someone exactly on pace who happened to weigh in on a retained-water
    /// morning. Weighing less often doesn't help: cadence changes how many
    /// noisy readings you see, not the spread of each one.
    var amberBand: Decimal {
        max(abs(totalAllowance) * Decimal(string: "0.05")!, amberFloor)
    }

    /// Traffic-light status (§3.2): on pace, drifting behind, or badly
    /// behind. Ahead of pace, or exactly on it, reads as green; behind by up
    /// to `amberBand` reads as amber; further behind reads as red. Unlike the
    /// amber/red split, there's no grace zone before green turns amber — any
    /// shortfall at all means the actual figure has already slipped past the
    /// target figure printed right next to it, and showing that pair as
    /// "green" would contradict what's plainly on screen.
    var status: PaceStatus {
        let goodness = goodness
        guard goodness < 0 else { return .good }
        return -goodness > amberBand ? .bad : .warning
    }

    /// The at-a-glance difference figure, formatted for `tracker`. When the
    /// tracker is clearly on one side or the other this drops the +/- sign:
    /// the colour and the status word already say which direction, so a sign
    /// on top of that is redundant rather than clarifying.
    ///
    /// In the amber band there's no clean over/under to name yet, so the
    /// signed distance from today's target is shown instead — signed the way
    /// the number itself moved, not the way the news reads. Above the target
    /// takes a "+" and below it a "−", whether that's a mileage figure
    /// running hot or a savings balance running cold.
    func displayDifference(for tracker: Tracker) -> String {
        guard status == .warning else {
            return tracker.formattedValue(abs(goodness))
        }
        return tracker.formattedValue(currentValue - targetValueToday, signed: true)
    }

    /// The status wording shown alongside the difference figure — the type's
    /// own good/bad label followed by "by" ("Below Budget by", "Behind Target
    /// by"), or the amber label on its own, which already reads as a complete
    /// phrase. Shared by the dashboard ring's centre content and the tracker
    /// list row so the two read identically rather than the list showing a
    /// bare number with no status word at all.
    func statusLine(for tracker: Tracker) -> String {
        let label = status.label(for: tracker)
        guard status != .warning else { return label }
        return "\(label) by"
    }

    /// How much of the allowance is left to use *right now* — "£100 left in
    /// this budget" after spending £400 of a £500 budget, "£1,800 still to
    /// save", "3.2 kg still to lose". This moves as readings come in, unlike
    /// `Tracker.projectedRemainder`, which projects a fixed
    /// starting-value-vs-allowance gap independent of actual progress. `nil`
    /// once the allowance is used up, reached or exceeded — the ring/status
    /// wording already covers being past it.
    func remainingInAllowanceCaption(for tracker: Tracker) -> String? {
        let remaining = totalAllowance - consumedSoFar
        guard remaining > 0 else { return nil }
        return "\(tracker.formattedValue(remaining)) \(tracker.terminology.remainingCaption)"
    }
}

/// Traffic-light reading of a tracker's pace (§3.2), independent of type —
/// `.good` always means "green", whether that's a spending tracker running
/// below budget, a savings balance running ahead of target, or a weight
/// tracker below where it's meant to be today.
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

    /// The tracker type's own wording for this status — the only place the
    /// app decides what "green" is called, so every surface says the same
    /// thing about the same tracker. See `TrackerTerminology`.
    func label(for tracker: Tracker) -> String {
        let terminology = tracker.terminology
        switch self {
        case .good: return terminology.goodLabel
        case .warning: return terminology.amberLabel
        case .bad: return terminology.badLabel
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
            totalAllowance: totalAllowance,
            higherIsBetter: higherIsBetter,
            amberFloor: trackerUnit.amberFloor
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
