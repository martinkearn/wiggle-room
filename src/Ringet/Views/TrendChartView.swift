//
//  TrendChartView.swift
//  Ringet
//

import SwiftUI
import Charts

/// Secondary detail view (§3.5): a straight pace reference line from
/// starting value to the end-of-period target, with actual logged readings
/// plotted on top — colored green where that segment is ahead of pace and
/// red where it's behind, so the shape relative to the reference line reads
/// at a glance rather than needing a legend. Minimal axis labeling — the
/// shape is the point, not precise chart-reading.
struct TrendChartView: View {
    let tracker: Tracker

    private var targetEndValue: Decimal {
        switch tracker.direction {
        case .decreasing: tracker.startingValue - tracker.totalAllowance
        case .increasing: tracker.startingValue + tracker.totalAllowance
        }
    }

    /// Whether a given logged value, at the date it was logged, was ahead of
    /// pace — reuses the exact same direction-aware calculation as the rest
    /// of the app (`TrackerPace.isAheadOfPace`) rather than re-deriving
    /// "above/below the line" separately for each direction.
    private func isAheadOfPace(value: Decimal, at date: Date) -> Bool {
        tracker.pace(actualValue: value, asOf: date).isAheadOfPace
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
        Chart {
            LineMark(
                x: .value("Date", tracker.startDate),
                y: .value("Pace", tracker.startingValue)
            )
            .foregroundStyle(RingetColors.paceRing)
            LineMark(
                x: .value("Date", tracker.endDate),
                y: .value("Pace", targetEndValue)
            )
            .foregroundStyle(RingetColors.paceRing)

            ForEach(segments, id: \.id) { segment in
                LineMark(
                    x: .value("Date", segment.start.date),
                    y: .value("Actual", segment.start.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(segment.isAhead ? RingetColors.good : RingetColors.bad)
                LineMark(
                    x: .value("Date", segment.end.date),
                    y: .value("Actual", segment.end.value),
                    series: .value("Segment", segment.id)
                )
                .foregroundStyle(segment.isAhead ? RingetColors.good : RingetColors.bad)
            }

            ForEach(tracker.sortedReadings) { reading in
                PointMark(
                    x: .value("Date", reading.date),
                    y: .value("Actual", reading.value)
                )
                .foregroundStyle(isAheadOfPace(value: reading.value, at: reading.date) ? RingetColors.good : RingetColors.bad)
            }
        }
        .chartXAxis {
            AxisMarks(values: [tracker.startDate, tracker.endDate]) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

#Preview {
    TrendChartView(tracker: PreviewData.makeSampleTracker())
        .frame(height: 220)
        .padding()
}
