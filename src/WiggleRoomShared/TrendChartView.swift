//
//  TrendChartView.swift
//  WiggleRoom
//

import SwiftUI
import Charts

/// Secondary detail view (§3.5): a solid target reference line from starting
/// value to the end-of-period target, with actual logged readings plotted on
/// top — colored green where that segment is ahead of pace and red where
/// it's behind, so the shape relative to the reference line reads at a
/// glance rather than needing a legend. A dotted trend line — a best-fit
/// through the actual readings, following the history as it developed and
/// then projected on to the period's end — shows where things are headed
/// overall if the current trend continues, distinct from both the target
/// line and the noisy point-to-point reading history. Minimal axis
/// labeling — the shape is the point, not precise chart-reading.
struct TrendChartView: View {
    let tracker: Tracker
    var now: Date = .now
    /// Widgets are too small for the legend and axis labels; the shape is the
    /// point there (§3.5), so they turn both off.
    var showsLegend = true
    var showsAxes = true

    private static let liveContinuationLineStyle = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4])

    private var window: DateInterval {
        DateInterval(start: tracker.startDate, end: tracker.endDate)
    }

    /// Bottom-axis ticks scaled to the tracker's length: hours up to a day,
    /// days up to a week, then weeks (up to ~3 months) or months beyond
    /// that. Ticks start at the tracker's own start and are thinned to at
    /// most ~6 so labels never collide.
    private var xAxisTicks: (dates: [Date], format: Date.FormatStyle) {
        let cal = Calendar.current
        let start = window.start, end = window.end
        let days = window.duration / 86_400
        let component: Calendar.Component
        let format: Date.FormatStyle
        var step = 1
        if days <= 1 {
            component = .hour
            format = .dateTime.hour()
        } else if days <= 7 {
            component = .day
            format = .dateTime.weekday(.abbreviated).day()
        } else if days <= 92 {
            component = .day
            step = 7
            format = .dateTime.month(.abbreviated).day()
        } else {
            component = .month
            format = .dateTime.month(.abbreviated)
        }
        var all: [Date] = []
        var i = 0
        while let d = cal.date(byAdding: component, value: i * step, to: start), d <= end, all.count < 500 {
            all.append(d)
            i += 1
        }
        let thin = max(1, Int((Double(all.count) / 6).rounded(.up)))
        let dates = all.enumerated().filter { $0.offset % thin == 0 }.map(\.element)
        return (dates.isEmpty ? [start, end] : dates, format)
    }

    private var latestReading: ValueSnapshot? {
        tracker.sortedReadings.last
    }

    private var targetEndValue: Decimal {
        switch tracker.direction {
        case .decreasing: tracker.startingValue - tracker.totalAllowance
        case .increasing: tracker.startingValue + tracker.totalAllowance
        }
    }

    /// The Y range the chart should actually be scaled to — `tracker
    /// .plausibleTrendRange` (shared with `Tracker.estimatedFinalValue`, so
    /// the detail screen's card can never show a different "where this
    /// lands" number than what this chart's trend line visually ends at),
    /// converted to `Double` for Swift Charts. Deliberately based only on
    /// the pace reference line and the real logged readings, *excluding*
    /// the trend line's own extrapolated values — a trend fitted from just
    /// a couple of early readings can imply a very steep slope; letting
    /// Swift Charts auto-scale the axis to fit that extrapolation all the
    /// way out to the period's end would squash the pace line and the
    /// actual readings into an unreadable sliver at one edge. `trendPoints`
    /// below also clamps its own values into this range directly — see that
    /// property for why leaving the raw, un-clamped values for Charts' own
    /// axis-driven clipping to handle isn't enough.
    private var yDomain: ClosedRange<Double> {
        let range = tracker.plausibleTrendRange
        return (range.lowerBound as NSDecimalNumber).doubleValue...(range.upperBound as NSDecimalNumber).doubleValue
    }

    /// The trend line's anchor points. Rather than a single straight line
    /// fitted once across every reading, each historical anchor is the
    /// *expanding-window* fit — the best-fit line through every reading up
    /// to and including that point, evaluated at that point's own date. As
    /// more readings arrive the fit shifts slightly, so the line traces
    /// gentle curves through history instead of being perfectly rigid — the
    /// trend "as understood at the time," rather than one line retroactively
    /// applied to the whole past. The final anchor projects the full-data
    /// fit forward to the window's end — where the balance is expected to
    /// land by the end of the tracker.
    ///
    /// Every value is clamped into `yDomain` rather than left at whatever
    /// the raw extrapolation computes — a fit from a couple of readings with
    /// a big early swing can imply a wildly steep slope, and passing that
    /// raw, far-out-of-frame value to Swift Charts (even with
    /// `.chartYScale(domain:)` set) triggers a real rendering bug here: the
    /// line's stroke bleeds straight through the rest of the screen above
    /// the chart instead of being cleanly clipped to the plot area. Clamping
    /// the values themselves — so nothing handed to Charts is ever far
    /// outside the visible domain — avoids that entirely. The line still
    /// visibly runs to the domain's top/bottom edge, which reads as "steep"
    /// just as well as the true extrapolated value would.
    private var trendPoints: [(date: Date, value: Decimal)]? {
        let readings = tracker.sortedReadings
        guard readings.count > 1 else { return nil }
        let domain = yDomain
        func clamped(_ raw: Double) -> Decimal {
            Decimal(min(max(raw, domain.lowerBound), domain.upperBound))
        }

        var points: [(date: Date, value: Decimal)] = []
        for index in 1..<readings.count {
            guard let expandingFit = linearFit(through: readings[0...index]) else { continue }
            points.append((readings[index].date, clamped(expandingFit.value(at: readings[index].date))))
        }
        guard !points.isEmpty, let fullFit = linearFit(through: readings[readings.startIndex...]) else { return nil }
        points.append((window.end, clamped(fullFit.value(at: window.end))))
        return points
    }

    /// A marker carrying the latest logged balance forward to "now" — keeps
    /// the chart feeling live even between readings, distinct from the
    /// trend projection. `nil` once the tracker's period has ended, since
    /// the last real reading already sits at that edge.
    private var liveNowPoint: (date: Date, value: Decimal)? {
        guard let latestReading, now < window.end else { return nil }
        return (min(now, window.end), latestReading.value)
    }

    /// The color of the most recent real segment/reading — reused for both
    /// the dotted continuation from the last reading to `liveNowPoint` and
    /// that point's own marker, so the "this is where things stood as of
    /// your last update, carried forward to right now" link reads as one
    /// continuous idea rather than an unconnected, unexplained dot.
    private var liveContinuationColor: Color {
        guard let latestReading else { return .secondary }
        return paceColor(for: latestReading.value, at: latestReading.date)
    }

    /// Whether a given logged value, at the date it was logged, was ahead of
    /// pace — reuses the exact same direction-aware calculation as the rest
    /// of the app (`TrackerPace.isAheadOfPace`) rather than re-deriving
    /// "above/below the line" separately for each direction.
    private func isAheadOfPace(value: Decimal, at date: Date) -> Bool {
        tracker.pace(actualValue: value, asOf: date).isAheadOfPace
    }

    private func paceColor(for value: Decimal, at date: Date) -> Color {
        isAheadOfPace(value: value, at: date) ? WiggleRoomColors.good : WiggleRoomColors.bad
    }

    /// Consecutive reading pairs, each tagged with whether the *later*
    /// point was ahead of pace — a segment is colored by where it ends up,
    /// same convention as coloring a stock chart's rising/falling days.
    private var segments: [(id: String, start: ValueSnapshot, end: ValueSnapshot, isAhead: Bool)] {
        let readings = tracker.sortedReadings
        guard readings.count > 1 else { return [] }
        return zip(readings, readings.dropFirst()).map { start, end in
            (id: "\(start.id)-\(end.id)", start: start, end: end, isAhead: isAheadOfPace(value: end.value, at: end.date))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            if showsLegend, trendPoints != nil {
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: WiggleRoomColors.paceRing, label: "Target")
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
            // Target reference line — the strongest line on the chart, since
            // it's the fixed yardstick everything else is read against.
            LineMark(
                x: .value("Date", window.start),
                y: .value("Target", tracker.startingValue),
                series: .value("Series", "Target")
            )
            .foregroundStyle(WiggleRoomColors.paceRing)
            .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round))
            LineMark(
                x: .value("Date", window.end),
                y: .value("Target", targetEndValue),
                series: .value("Series", "Target")
            )
            .foregroundStyle(WiggleRoomColors.paceRing)
            .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round))

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

            ForEach(tracker.sortedReadings) { reading in
                PointMark(
                    x: .value("Date", reading.date),
                    y: .value("Actual", reading.value)
                )
                .foregroundStyle(paceColor(for: reading.value, at: reading.date))
            }

            if let liveNowPoint, let latestReading {
                // A dotted continuation from the last real reading up to
                // "now" — without this, `liveNowPoint` below read as an
                // unexplained floating dot rather than a clear "your last
                // update, carried forward to this moment."
                LineMark(
                    x: .value("Date", latestReading.date),
                    y: .value("Now", latestReading.value),
                    series: .value("Series", "LiveContinuation")
                )
                .foregroundStyle(liveContinuationColor)
                .lineStyle(Self.liveContinuationLineStyle)
                LineMark(
                    x: .value("Date", liveNowPoint.date),
                    y: .value("Now", liveNowPoint.value),
                    series: .value("Series", "LiveContinuation")
                )
                .foregroundStyle(liveContinuationColor)
                .lineStyle(Self.liveContinuationLineStyle)

                PointMark(
                    x: .value("Date", liveNowPoint.date),
                    y: .value("Now", liveNowPoint.value)
                )
                .foregroundStyle(liveContinuationColor)
                .symbolSize(24)
            }

            if let trendPoints {
                ForEach(Array(trendPoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Trend", point.value),
                        series: .value("Series", "Trend")
                    )
                    .foregroundStyle(WiggleRoomColors.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 5]))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: xAxisTicks.dates) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: xAxisTicks.format)
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading)
            }
        }
        .chartYScale(domain: yDomain)
    }
}

#Preview {
    TrendChartView(tracker: SharedPreviewData.makeSampleTracker())
        .frame(height: 240)
        .padding()
}
