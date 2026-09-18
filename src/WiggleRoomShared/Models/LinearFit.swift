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
    /// Where the trend line (§3.5) projects this tracker's value to land by
    /// `endDate`, based on a least-squares fit through every reading logged
    /// so far — **unclamped**, unlike `TrendChartView`'s own plotted trend
    /// points (clamped into the chart's visible Y range purely to avoid a
    /// Swift Charts rendering bug, §3.5). `nil` before at least two readings
    /// exist, matching the chart's own threshold for showing a trend line
    /// at all — a single point has no slope to extrapolate from.
    var estimatedFinalValue: Decimal? {
        guard let fit = linearFit(through: sortedReadings) else { return nil }
        return Decimal(fit.value(at: endDate))
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
