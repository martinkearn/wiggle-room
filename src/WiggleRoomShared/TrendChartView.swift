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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let liveContinuationLineStyle = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4])

    typealias ChartPoint = (date: Date, value: Double)

    /// The five days the chart is magnified to when the tracker is zoomed
    /// (see `TrackerZoom`), or `nil` to show the whole period.
    private var zoomWindow: DateInterval? {
        tracker.zoomWindow(asOf: now)
    }

    /// The span the chart's x-axis covers: the zoom window, or the whole
    /// tracking period.
    private var window: DateInterval {
        zoomWindow ?? DateInterval(start: tracker.startDate, end: tracker.endDate)
    }

    /// Where the pace line sits at a given instant.
    private func paceValue(at date: Date) -> Double {
        double(tracker.pace(actualValue: tracker.startingValue, asOf: date).targetValueToday)
    }

    /// Cuts the line from `a` to `b` down to the part inside `window`,
    /// interpolating a new end wherever it crosses an edge. `nil` if none of
    /// it is inside. Unzoomed, lines are left exactly as they are.
    private func clipped(_ a: ChartPoint, _ b: ChartPoint) -> (ChartPoint, ChartPoint)? {
        guard let zoomWindow else { return (a, b) }
        guard b.date >= zoomWindow.start, a.date <= zoomWindow.end else { return nil }
        func value(at date: Date) -> Double {
            let span = b.date.timeIntervalSince(a.date)
            guard span > 0 else { return b.value }
            return a.value + (b.value - a.value) * date.timeIntervalSince(a.date) / span
        }
        let start = a.date < zoomWindow.start ? (zoomWindow.start, value(at: zoomWindow.start)) : a
        let end = b.date > zoomWindow.end ? (zoomWindow.end, value(at: zoomWindow.end)) : b
        return (start, end)
    }

    /// `clipped(_:_:)` applied along a whole polyline.
    private func clipped(_ points: [ChartPoint]) -> [ChartPoint] {
        guard zoomWindow != nil else { return points }
        var result: [ChartPoint] = []
        for (a, b) in zip(points, points.dropFirst()) {
            guard let (start, end) = clipped(a, b) else { continue }
            if let last = result.last, last.date == start.date, last.value == start.value {
                result.append(end)
            } else {
                result += [start, end]
            }
        }
        return result
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

    /// The readings drawn as points — only those inside the zoom window
    /// when zoomed, since anything else would sit off the plot.
    private var visibleReadings: [ValueSnapshot] {
        guard let zoomWindow else { return tracker.sortedReadings }
        return tracker.sortedReadings.filter { zoomWindow.contains($0.date) }
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
    ///
    /// Zoomed, the scale is fitted to what's inside the window instead —
    /// the pace line, the readings (including where lines enter and leave
    /// across the window's edges) and the carried-forward "now" point — so
    /// five days of movement fill the plot rather than sitting as a flat
    /// sliver of the whole period's scale.
    private var yDomain: ClosedRange<Double> {
        guard let zoomWindow else {
            let range = tracker.plausibleTrendRange
            return (range.lowerBound as NSDecimalNumber).doubleValue...(range.upperBound as NSDecimalNumber).doubleValue
        }
        var values = [paceValue(at: zoomWindow.start), paceValue(at: zoomWindow.end)]
        values += segments.flatMap { [$0.start.value, $0.end.value] }
        values += visibleReadings.map { double($0.value) }
        values += liveContinuation.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = high > low ? (high - low) * 0.1 : 1
        return (low - padding)...(high + padding)
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
    ///
    /// Zoomed, the line is still fitted from every reading, but only the
    /// part inside the window is drawn.
    private var trendPoints: [ChartPoint]? {
        let readings = tracker.sortedReadings
        guard readings.count > 1 else { return nil }
        let domain = yDomain

        var points: [ChartPoint] = []
        for index in 1..<readings.count {
            guard let expandingFit = linearFit(through: readings[0...index]) else { continue }
            points.append((readings[index].date, expandingFit.value(at: readings[index].date)))
        }
        guard !points.isEmpty, let fullFit = linearFit(through: readings[readings.startIndex...]) else { return nil }
        points.append((tracker.endDate, fullFit.value(at: tracker.endDate)))
        let visible = clipped(points).map { ($0.date, min(max($0.value, domain.lowerBound), domain.upperBound)) }
        return visible.isEmpty ? nil : visible
    }

    /// A marker carrying the latest logged balance forward to "now" — keeps
    /// the chart feeling live even between readings, distinct from the
    /// trend projection. `nil` once the tracker's period has ended, since
    /// the last real reading already sits at that edge.
    private var liveNowPoint: (date: Date, value: Decimal)? {
        guard let latestReading, now < window.end else { return nil }
        if zoomWindow != nil, now < window.start { return nil }
        return (min(now, window.end), latestReading.value)
    }

    /// The dotted line from the latest reading to `liveNowPoint`, cut to
    /// the zoom window when zoomed. Empty when there's no live point.
    private var liveContinuation: [ChartPoint] {
        guard let liveNowPoint, let latestReading else { return [] }
        return clipped([(latestReading.date, double(latestReading.value)), (liveNowPoint.date, double(liveNowPoint.value))])
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
    /// Zoomed, each segment is cut to the window, keeping the colour of the
    /// reading it ends at even when that reading is off the plot.
    private var segments: [(id: String, start: ChartPoint, end: ChartPoint, isAhead: Bool)] {
        let readings = tracker.sortedReadings
        guard readings.count > 1 else { return [] }
        return zip(readings, readings.dropFirst()).compactMap { start, end in
            guard let (a, b) = clipped((start.date, double(start.value)), (end.date, double(end.value))) else { return nil }
            return (id: "\(start.id)-\(end.id)", start: a, end: b, isAhead: isAheadOfPace(value: end.value, at: end.date))
        }
    }

    /// Points along a straight line from `a` to `b`, nudged sideways by a
    /// small, deterministic wobble that fades to exactly zero at both ends —
    /// so the line still starts and finishes on its real values, but wanders
    /// a touch in between like a hand-drawn stroke, matching the rings and
    /// icon. Amplitude is ~1.8% of the visible Y range. Drawn with
    /// `.catmullRom` so the wander is smooth, not jagged. Data points
    /// (`PointMark`s, the trend line) are never displaced; only the
    /// connecting strokes are.
    private func wobbly(
        from a: (date: Date, value: Double),
        to b: (date: Date, value: Double),
        seed: Double,
        cycles: Double = 1.5
    ) -> [(date: Date, value: Double)] {
        let domain = yDomain
        let amplitude = (domain.upperBound - domain.lowerBound) * 0.018
        let steps = 8
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let base = a.value + (b.value - a.value) * t
            let offset = amplitude * sin(.pi * t) * sin(2 * .pi * cycles * t + seed)
            return (
                a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) * t),
                min(max(base + offset, domain.lowerBound), domain.upperBound)
            )
        }
    }

    private func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
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
            legendItem(colors: [tracker.accentColor], label: tracker.terminology.paceNoun)
            legendItem(colors: [WiggleRoomColors.good, WiggleRoomColors.bad], label: "Actual")
            legendItem(colors: [WiggleRoomColors.brand], label: "Trend")
        }
        .font(.wiggleText(.caption2))
        .foregroundStyle(.secondary)
    }

    /// More than one colour splits the swatch side by side — "Actual" is
    /// drawn green or red depending on pace, so its key shows both.
    private func legendItem(colors: [Color], label: String) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(color)
                }
            }
            .frame(width: 12, height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 1.5))
            Text(label)
        }
    }

    private var chart: some View {
        Chart {
            // Target reference line — the strongest line on the chart, since
            // it's the fixed yardstick everything else is read against.
            ForEach(Array(wobbly(
                from: (window.start, paceValue(at: window.start)),
                to: (window.end, paceValue(at: window.end)),
                seed: 0.7
            ).enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    // The y-value's label is what Swift Charts reads out in
                    // its accessibility description, so it carries the type's
                    // own noun; the series key is an internal identifier.
                    y: .value(tracker.terminology.paceNoun, point.value),
                    series: .value("Series", "Pace")
                )
                .foregroundStyle(tracker.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                ForEach(Array(wobbly(
                    from: segment.start,
                    to: segment.end,
                    seed: 1.9 + Double(index) * 2.3,
                    cycles: 1
                ).enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Actual", point.value),
                        series: .value("Segment", segment.id)
                    )
                    .foregroundStyle(segment.isAhead ? WiggleRoomColors.good : WiggleRoomColors.bad)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
            }

            ForEach(visibleReadings) { reading in
                PointMark(
                    x: .value("Date", reading.date),
                    y: .value("Actual", reading.value)
                )
                .foregroundStyle(paceColor(for: reading.value, at: reading.date))
            }

            if let liveNowPoint {
                // A dotted continuation from the last real reading up to
                // "now" — without this, `liveNowPoint` below read as an
                // unexplained floating dot rather than a clear "your last
                // update, carried forward to this moment."
                ForEach(Array(liveContinuation.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Now", point.value),
                        series: .value("Series", "LiveContinuation")
                    )
                    .foregroundStyle(liveContinuationColor)
                    .lineStyle(Self.liveContinuationLineStyle)
                }

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
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, lineCap: .round, dash: [2, 4]))
                    AxisTick()
                    AxisValueLabel(format: xAxisTicks.format)
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, lineCap: .round, dash: [2, 4]))
                    AxisValueLabel()
                }
            }
        }
        .chartYScale(domain: yDomain)
        .font(.wiggleText(.caption2))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: zoomWindow)
        .modifier(ZoomAccessibility(
            description: zoomWindow.map { "Zoomed to \(Tracker.zoomRangeText($0))" },
            combinesChildren: false
        ))
    }
}

#Preview {
    TrendChartView(tracker: SharedPreviewData.makeSampleTracker())
        .frame(height: 240)
        .padding()
}
