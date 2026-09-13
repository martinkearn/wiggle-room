//
//  TrendChartView.swift
//  Ringet
//

import SwiftUI
import Charts

/// Secondary detail view (§3.5): a straight pace reference line from
/// starting value to the end-of-period target, with actual logged readings
/// plotted as a distinct line/color above or below it. Minimal axis
/// labeling — the shape relative to the reference line is the point, not
/// precise chart-reading.
struct TrendChartView: View {
    let tracker: Tracker

    private var targetEndValue: Decimal {
        switch tracker.direction {
        case .decreasing: tracker.startingValue - tracker.totalAllowance
        case .increasing: tracker.startingValue + tracker.totalAllowance
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

            ForEach(tracker.sortedReadings) { reading in
                LineMark(
                    x: .value("Date", reading.date),
                    y: .value("Actual", reading.value)
                )
                .foregroundStyle(.blue)
                PointMark(
                    x: .value("Date", reading.date),
                    y: .value("Actual", reading.value)
                )
                .foregroundStyle(.blue)
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
