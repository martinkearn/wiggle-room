//
//  LinearFit.swift
//  WiggleRoom
//

import Foundation

/// A least-squares line of best fit through a set of date/value points.
/// Shared by `TrendChartView` (§3.5's dotted trend line) and
/// `Tracker.estimatedFinalValue` below, so there's exactly one regression
/// calculation in the app rather than two that could quietly drift apart.
struct LinearFit {
    let slope: Double
    let intercept: Double
    let referenceDate: Date

    func value(at date: Date) -> Double {
        intercept + slope * date.timeIntervalSince(referenceDate)
    }
}

/// `nil` if there are fewer than two readings, or if every reading landed
/// at the exact same instant (a degenerate, zero-width span) since a slope
/// isn't meaningful then.
func linearFit(through readings: some Collection<ValueSnapshot>) -> LinearFit? {
    guard readings.count > 1, let referenceDate = readings.first?.date else { return nil }
    let xs = readings.map { $0.date.timeIntervalSince(referenceDate) }
    let ys = readings.map { ($0.value as NSDecimalNumber).doubleValue }

    let n = Double(xs.count)
    let sumX = xs.reduce(0, +)
    let sumY = ys.reduce(0, +)
    let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
    let sumXX = xs.reduce(0) { $0 + $1 * $1 }
    let denominator = n * sumXX - sumX * sumX
    guard denominator != 0 else { return nil }

    let slope = (n * sumXY - sumX * sumY) / denominator
    let intercept = (sumY - slope * sumX) / n
    return LinearFit(slope: slope, intercept: intercept, referenceDate: referenceDate)
}

extension Tracker {
    /// The range of values a trend projection is trusted to land within —
    /// shared by the chart's Y-axis clamp (`TrendChartView.yDomain`) and
    /// `estimatedFinalValue` below, so the two can never show two different
    /// "where this is headed" values for the exact same underlying fit.
    /// Built from the tracker's own real anchors — `startingValue`,
    /// `projectedFinalValue` (the fixed target), and every logged reading —
    /// padded by 10%. Deliberately not a statistical confidence interval,
    /// just a sane bound tied to numbers the tracker has actually produced:
    /// a least-squares fit skewed by a handful of early, closely-spaced
    /// readings can imply a slope that's mathematically correct but, once
    /// extrapolated across weeks of remaining time, lands somewhere wildly
    /// outside the scale of everything else on screen — this keeps both the
    /// chart and the card from ever stating that number as if it were
    /// trustworthy on its own.
    var plausibleTrendRange: ClosedRange<Decimal> {
        var values = [startingValue, projectedFinalValue]
        values += sortedReadings.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.1, 1)
        return (low - padding)...(high + padding)
    }

    /// Where the trend line (§3.5) projects this tracker's value to land by
    /// `endDate`, based on a least-squares fit through every reading logged
    /// so far, clamped into `plausibleTrendRange` — **the same clamp**
    /// `TrendChartView`'s own plotted trend line uses, so this card always
    /// states the exact number the trend line visually ends at rather than
    /// a separately-computed raw value that can look inconsistent with it.
    /// `nil` before at least two readings exist — matching the chart's own
    /// threshold for showing a trend line at all, since a single point has
    /// no slope to extrapolate from.
    var estimatedFinalValue: Decimal? {
        guard let fit = linearFit(through: sortedReadings) else { return nil }
        let raw = Decimal(fit.value(at: endDate))
        let range = plausibleTrendRange
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    /// How far `estimatedFinalValue` trends from `projectedFinalValue` (the
    /// tracker's fixed, configured target), **oriented so positive always
    /// means "trending toward the good outcome"** — matching the sign
    /// convention `TrackerPace.difference` already uses elsewhere: ending
    /// with more left over than planned is good for a decreasing/budget
    /// tracker, ending below the cap is good for an increasing one. `nil`
    /// whenever `estimatedFinalValue` itself is.
    var estimatedFinalDifference: Decimal? {
        guard let estimatedFinalValue else { return nil }
        switch direction {
        case .decreasing: return estimatedFinalValue - projectedFinalValue
        case .increasing: return projectedFinalValue - estimatedFinalValue
        }
    }
}
