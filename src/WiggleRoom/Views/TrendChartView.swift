//
//  TrendChartView.swift
//  WiggleRoom
//

import SwiftUI
import Charts

/// Secondary detail view (§3.5): a straight pace reference line from
/// starting value to the end-of-period target, with actual logged readings
/// plotted on top — colored green where that segment is ahead of pace and
/// red where it's behind, so the shape relative to the reference line reads
/// at a glance rather than needing a legend. A third line — a best-fit trend
/// through the actual readings, extended across the full period — shows
/// where things are headed overall if the current trend continues, distinct
/// from both the target pace and the noisy point-to-point reading history.
/// Minimal axis labeling — the shape is the point, not precise chart-reading.
struct TrendChartView: View {
    let tracker: Tracker

    /// Re-scopes the chart to a zoom level's calendar-aligned sub-period
    /// (§4.5) — the reference line runs the sub-period's own local starting
    /// value to its own target-end, and only readings actually logged
    /// within the sub-period are plotted. Defaults to `.overall`, the
    /// existing full-period behavior.
    var zoomLevel: ZoomLevel = .overall
    var now: Date = .now

    private var window: DateInterval {
        if let subPeriod = tracker.subPeriod(for: zoomLevel, asOf: now) {
            return subPeriod
        }
        return DateInterval(start: tracker.startDate, end: tracker.endDate)
    }

    private var windowStartingValue: Decimal {
        zoomLevel == .overall ? tracker.startingValue : tracker.actualValue(atOrBefore: window.start)
    }

    private var windowAllowance: Decimal {
        guard zoomLevel != .overall else { return tracker.totalAllowance }
        let totalPeriodDays = tracker.endDate.timeIntervalSince(tracker.startDate) / 86400
        guard totalPeriodDays > 0 else { return tracker.totalAllowance }
        let subPeriodDays = window.end.timeIntervalSince(window.start) / 86400
        return tracker.totalAllowance * Decimal(subPeriodDays / totalPeriodDays)
    }

    /// Readings that actually fall within the zoomed window — the reading
    /// history as a whole still holds everything ever logged, but a zoomed
    /// chart should only plot what happened inside the sub-period it's
    /// showing.
    private var windowedReadings: [ValueSnapshot] {
        tracker.sortedReadings.filter { $0.date >= window.start && $0.date <= window.end }
    }

    private var targetEndValue: Decimal {
        switch tracker.direction {
        case .decreasing: windowStartingValue - windowAllowance
        case .increasing: windowStartingValue + windowAllowance
        }
    }

    /// The Y range the chart should actually be scaled to — based only on
    /// the pace reference line and the real logged readings, deliberately
    /// *excluding* the trend line's own extrapolated endpoints. A trend
    /// fitted from just a couple of early readings can imply a very steep
    /// slope; letting Swift Charts auto-scale the axis to fit that
    /// extrapolation all the way out to the period's end would squash the
    /// pace line and the actual readings into an unreadable sliver at one
    /// edge. `trendLine` below also clamps its own values into this range
    /// directly — see that property for why leaving the raw, un-clamped
    /// values for Charts' own axis-driven clipping to handle isn't enough.
    private var yDomain: ClosedRange<Double> {
        var values = [windowStartingValue, targetEndValue].map { ($0 as NSDecimalNumber).doubleValue }
        values += windowedReadings.map { ($0.value as NSDecimalNumber).doubleValue }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.1, 1)
        return (low - padding)...(high + padding)
    }

    /// A least-squares line of best fit through the logged readings
    /// (date vs. value), extended across the tracker's full period so it can
    /// be compared directly against the dashed pace reference line — "if
    /// this trend continues, here's roughly where it ends up," as opposed to
    /// the jagged actual-readings line, which only shows what's already
    /// happened. `nil` until there are at least two readings to fit a line
    /// through, and if every reading landed at the exact same instant
    /// (a degenerate, zero-width span) since a slope isn't meaningful then.
    ///
    /// The two endpoint values are clamped into `yDomain` rather than left
    /// at whatever the raw extrapolation computes — a trend fitted from a
    /// couple of readings with a big early swing can imply a wildly steep
    /// slope, and passing that raw, far-out-of-frame value to Swift Charts
    /// (even with `.chartYScale(domain:)` set) triggers a real rendering bug
    /// here: the line's stroke bleeds straight through the rest of the
    /// screen above the chart instead of being cleanly clipped to the plot
    /// area. Clamping the values themselves — so nothing handed to Charts is
    /// ever far outside the visible domain — avoids that entirely. The line
    /// still visibly runs to the domain's top/bottom edge, which reads as
    /// "steep" just as well as the true extrapolated value would.
    private var trendLine: (start: (date: Date, value: Decimal), end: (date: Date, value: Decimal))? {
        let readings = windowedReadings
        guard readings.count > 1 else { return nil }

        let referenceDate = readings[0].date
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

        let startX = window.start.timeIntervalSince(referenceDate)
        let endX = window.end.timeIntervalSince(referenceDate)
        let domain = yDomain
        let clampedStartY = min(max(intercept + slope * startX, domain.lowerBound), domain.upperBound)
        let clampedEndY = min(max(intercept + slope * endX, domain.lowerBound), domain.upperBound)
        return (
            start: (window.start, Decimal(clampedStartY)),
            end: (window.end, Decimal(clampedEndY))
        )
    }

    /// Whether a given logged value, at the date it was logged, was ahead of
    /// pace — reuses the exact same direction-aware calculation as the rest
    /// of the app (`TrackerPace.isAheadOfPace`) rather than re-deriving
    /// "above/below the line" separately for each direction.
    private func isAheadOfPace(value: Decimal, at date: Date) -> Bool {
        tracker.pace(actualValue: value, asOf: date, zoomLevel: zoomLevel).isAheadOfPace
    }

    /// Consecutive reading pairs, each tagged with whether the *later*
    /// point was ahead of pace — a segment is colored by where it ends up,
    /// same convention as coloring a stock chart's rising/falling days.
    private var segments: [(id: String, start: ValueSnapshot, end: ValueSnapshot, isAhead: Bool)] {
        let readings = windowedReadings
        guard readings.count > 1 else { return [] }
        return zip(readings, readings.dropFirst()).map { start, end in
            (id: "\(start.id)-\(end.id)", start: start, end: end, isAhead: isAheadOfPace(value: end.value, at: end.date))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            if trendLine != nil {
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: WiggleRoomColors.paceRing, label: "Pace")
            legendItem(color: WiggleRoomColors.good, label: "Actual")
            legendItem(color: WiggleRoomColors.brand, label: "Trend")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(label)
        }
    }

    private var chart: some View {
        Chart {
            LineMark(
                x: .value("Date", window.start),
                y: .value("Pace", windowStartingValue)
            )
            .foregroundStyle(WiggleRoomColors.paceRing)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))
            LineMark(
                x: .value("Date", window.end),
                y: .value("Pace", targetEndValue)
            )
            .foregroundStyle(WiggleRoomColors.paceRing)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 5]))

            ForEach(segments, id: \.id) { segment in
                LineMark(
                    x: .value("Date", segment.start.date),
                    y: .value("Actual", segment.start.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(segment.isAhead ? WiggleRoomColors.good : WiggleRoomColors.bad)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                LineMark(
                    x: .value("Date", segment.end.date),
                    y: .value("Actual", segment.end.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(segment.isAhead ? WiggleRoomColors.good : WiggleRoomColors.bad)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(windowedReadings) { reading in
                PointMark(
                    x: .value("Date", reading.date),
                    y: .value("Actual", reading.value)
                )
                .foregroundStyle(isAheadOfPace(value: reading.value, at: reading.date) ? WiggleRoomColors.good : WiggleRoomColors.bad)
            }

            if let trendLine {
                LineMark(
                    x: .value("Date", trendLine.start.date),
                    y: .value("Trend", trendLine.start.value),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(WiggleRoomColors.brand)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                LineMark(
                    x: .value("Date", trendLine.end.date),
                    y: .value("Trend", trendLine.end.value),
                    series: .value("Series", "Trend")
                )
                .foregroundStyle(WiggleRoomColors.brand)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .chartXAxis {
            AxisMarks(values: [window.start, window.end]) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: yDomain)
    }
}

#Preview {
    TrendChartView(tracker: PreviewData.makeSampleTracker())
        .frame(height: 240)
        .padding()
}
