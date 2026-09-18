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
    /// Below this, a fit's slope is trusted too little to extrapolate all
    /// the way to `endDate` — see `hasSufficientSpanForTrend`.
    private static let minimumTrendSpanFraction = 0.1
    private static let minimumTrendSpanFloor: TimeInterval = 6 * 3600

    /// Whether the logged readings span enough real time to trust a
    /// straight-line extrapolation out to `endDate`. A least-squares slope
    /// fitted through readings taken minutes apart (e.g. a couple of
    /// foreground polls) is only reliable over that same short window — a
    /// tiny, meaningless wobble between two close-together readings, spread
    /// linearly across weeks remaining, produces a wildly exaggerated final
    /// figure even though the fit itself is mathematically correct. This is
    /// exactly what `TrendChartView`'s trend line hides by clamping its
    /// plotted points into the chart's Y range (§3.5) — this card shows a
    /// specific number rather than just a line, so it can't rely on the
    /// same visual clamp and instead withholds the estimate until there's
    /// enough real elapsed history to back it: at least 10% of the
    /// tracker's total period, with a 6-hour floor for very short trackers.
    private var hasSufficientSpanForTrend: Bool {
        guard let first = sortedReadings.first, let last = sortedReadings.last else { return false }
        let span = last.date.timeIntervalSince(first.date)
        let totalDuration = endDate.timeIntervalSince(startDate)
        let required = max(Self.minimumTrendSpanFloor, totalDuration * Self.minimumTrendSpanFraction)
        return span >= required
    }

    /// Where the trend line (§3.5) projects this tracker's value to land by
    /// `endDate`, based on a least-squares fit through every reading logged
    /// so far — **unclamped**, unlike `TrendChartView`'s own plotted trend
    /// points (clamped into the chart's visible Y range purely to avoid a
    /// Swift Charts rendering bug, §3.5). `nil` before at least two readings
    /// exist (matching the chart's own threshold for showing a trend line at
    /// all — a single point has no slope to extrapolate from), or before
    /// `hasSufficientSpanForTrend` — a fit from readings clustered close
    /// together in time isn't a trustworthy long-range prediction yet.
    var estimatedFinalValue: Decimal? {
        guard hasSufficientSpanForTrend, let fit = linearFit(through: sortedReadings) else { return nil }
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
