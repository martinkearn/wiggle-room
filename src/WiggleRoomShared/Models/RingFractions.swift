//
//  RingFractions.swift
//  WiggleRoom
//

import Foundation

/// How far each ring is filled. The rings always cover the whole period;
/// zoom applies to the chart alone (see `ChartZoom`).
struct RingFractions: Equatable {
    /// The share of the period elapsed — the outer ring.
    let elapsed: Double
    /// The share of the allowance consumed — the inner ring.
    let consumed: Double
}

extension Tracker {
    /// Both rings' fills for the tracker's latest reading as of `now`.
    func ringFractions(asOf now: Date) -> RingFractions {
        ringFractions(actualValue: latestReading?.value ?? startingValue, asOf: now)
    }

    /// The share of the whole period elapsed, and the share of the whole
    /// allowance consumed, each clamped to 0...1.
    func ringFractions(actualValue: Decimal, asOf now: Date) -> RingFractions {
        let pace = pace(actualValue: actualValue, asOf: now)
        let elapsed = pace.periodHours > 0 ? min(max(pace.hoursElapsed / pace.periodHours, 0), 1) : 0
        let consumed: Double
        if totalAllowance != 0 {
            consumed = min(max((pace.consumedSoFar / totalAllowance as NSDecimalNumber).doubleValue, 0), 1)
        } else {
            consumed = 0
        }
        return RingFractions(elapsed: elapsed, consumed: consumed)
    }
}
