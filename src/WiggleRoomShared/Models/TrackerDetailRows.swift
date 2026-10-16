//
//  TrackerDetailRows.swift
//  WiggleRoom
//

import Foundation

/// One label/value line in the list beneath a tracker's chart.
struct TrackerDetailRow: Equatable, Identifiable {
    enum Kind: Equatable {
        case dailyBudget
        case wholePeriod
        case finalFigure
        case estimatedFinal
        case remaining
        case account
        case checked
        case changed
    }

    let kind: Kind
    let label: String
    let value: String

    var id: Kind { kind }
}

extension Tracker {
    /// How far through its period the tracker is as of `now`, from 0 to 1.
    /// 1 once the period has ended, and also for a zero-length period, which
    /// has no "through" to measure.
    func periodElapsedFraction(asOf now: Date) -> Double {
        let span = endDate.timeIntervalSince(startDate)
        guard span > 0 else { return 1 }
        return min(max(now.timeIntervalSince(startDate) / span, 0), 1)
    }

    /// The rows of the dashboard's detail list, in display order. A row is
    /// present only when its data exists, so the caller never has to decide
    /// which to hide.
    ///
    /// - Parameters:
    ///   - pace: The pace snapshot the screen is showing. Only the remaining
    ///     allowance is read from it.
    ///   - account: The connection and account line, for a connected tracker.
    func detailRows(pace: TrackerPace, asOf now: Date, account: String?) -> [TrackerDetailRow] {
        var rows: [TrackerDetailRow] = []

        if let dailyRate {
            let label = trackerType.orientation == .allowance ? "Daily budget" : "Per day"
            rows.append(TrackerDetailRow(
                kind: .dailyBudget,
                label: label,
                value: "\(Self.formattedRate(dailyRate, unit: trackerUnit)) / day"
            ))
        }

        rows.append(TrackerDetailRow(
            kind: .wholePeriod,
            label: terminology.wholePeriodFigure,
            value: formattedValue(wholePeriodValue)
        ))

        // For a goal type the final figure is the goal itself, which the
        // whole-period row has already printed.
        if trackerType.orientation == .allowance {
            rows.append(TrackerDetailRow(
                kind: .finalFigure,
                label: terminology.finalFigure,
                value: formattedValue(projectedFinalValue)
            ))
        }

        if !isCompleted(asOf: now), sortedReadings.count > 1, let estimatedFinalValue {
            rows.append(TrackerDetailRow(
                kind: .estimatedFinal,
                label: "Estimated final",
                value: formattedValue(estimatedFinalValue)
            ))
        }

        if let remaining = pace.remainingInAllowance {
            let wording = terminology.remainingCaption
            rows.append(TrackerDetailRow(
                kind: .remaining,
                label: wording.prefix(1).uppercased() + wording.dropFirst(),
                value: formattedValue(remaining)
            ))
        }

        if let account, !account.isEmpty {
            rows.append(TrackerDetailRow(kind: .account, label: "Account", value: account))
        }

        if !isManualEntry {
            if let lastCheckedDate {
                rows.append(TrackerDetailRow(kind: .checked, label: "Checked", value: Self.timingText(lastCheckedDate, asOf: now)))
            }
            if let latestReading {
                rows.append(TrackerDetailRow(kind: .changed, label: "Changed", value: Self.timingText(latestReading.date, asOf: now)))
            }
        }

        return rows
    }

    /// Time only when it's today, otherwise day and month (no year) and time.
    static func timingText(_ date: Date, asOf now: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))), \(time)"
    }
}
