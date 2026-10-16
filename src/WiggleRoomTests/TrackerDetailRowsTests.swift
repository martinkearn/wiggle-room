//
//  TrackerDetailRowsTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class TrackerDetailRowsTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Jan 1 -> Jan 31 (30 days); Jan 16 is halfway.
    private var halfway: Date { date(2026, 1, 16) }

    private func makeTracker(
        type: TrackerType = .spendingMoney,
        providerId: String = "manual",
        start: Date? = nil,
        end: Date? = nil,
        startingValue: Decimal = 500,
        totalAllowance: Decimal = 500,
        readings: [ValueSnapshot] = []
    ) -> Tracker {
        let tracker = Tracker(
            name: "Test tracker",
            type: type,
            connectedSource: ConnectedSource(providerId: providerId, displayName: "Test source"),
            startDate: start ?? date(2026, 1, 1),
            endDate: end ?? date(2026, 1, 31),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
        tracker.readings = readings
        return tracker
    }

    private func kinds(of tracker: Tracker, value: Decimal, asOf now: Date? = nil, account: String? = nil) -> [TrackerDetailRow.Kind] {
        let now = now ?? halfway
        return tracker.detailRows(pace: tracker.pace(actualValue: value, asOf: now), asOf: now, account: account).map(\.kind)
    }

    // MARK: - periodElapsedFraction

    func testElapsedFraction_beforeStart_isZero() {
        XCTAssertEqual(makeTracker().periodElapsedFraction(asOf: date(2025, 12, 1)), 0)
    }

    func testElapsedFraction_midway_isOneHalf() {
        XCTAssertEqual(makeTracker().periodElapsedFraction(asOf: halfway), 0.5, accuracy: 0.0001)
    }

    func testElapsedFraction_afterEnd_isOne() {
        XCTAssertEqual(makeTracker().periodElapsedFraction(asOf: date(2026, 3, 1)), 1)
    }

    func testElapsedFraction_zeroLengthPeriod_isOne() {
        let tracker = makeTracker(start: halfway, end: halfway)
        XCTAssertEqual(tracker.periodElapsedFraction(asOf: halfway), 1)
    }

    // MARK: - detailRows

    func testRows_allowanceConnectedTracker_showsEveryRowInOrder() {
        let readings = [
            ValueSnapshot(value: 500, date: date(2026, 1, 2)),
            ValueSnapshot(value: 400, date: date(2026, 1, 10))
        ]
        let tracker = makeTracker(providerId: "starling", readings: readings)
        tracker.lastCheckedDate = halfway

        XCTAssertEqual(
            kinds(of: tracker, value: 400, account: "Test source \u{00B7} Test account"),
            [.dailyBudget, .wholePeriod, .finalFigure, .estimatedFinal, .remaining, .account, .checked, .changed]
        )
    }

    func testRows_goalManualTracker_hasNoFinalFigureOrAccountRows() {
        let tracker = makeTracker(type: .savingMoney, startingValue: 0, totalAllowance: 1000)
        let rows = kinds(of: tracker, value: 100)

        XCTAssertFalse(rows.contains(.finalFigure), "the goal is already printed as the whole-period row")
        XCTAssertFalse(rows.contains(.account))
        XCTAssertFalse(rows.contains(.checked))
        XCTAssertFalse(rows.contains(.changed))
        XCTAssertEqual(rows.first, .dailyBudget)
    }

    func testRows_goalTracker_labelsDailyRowNeutrally() {
        let tracker = makeTracker(type: .savingMoney, startingValue: 0, totalAllowance: 1000)
        let pace = tracker.pace(actualValue: 100, asOf: halfway)
        let rows = tracker.detailRows(pace: pace, asOf: halfway, account: nil)
        XCTAssertEqual(rows.first?.label, "Per day")
    }

    func testRows_completedTracker_hasNoEstimatedFinal() {
        let readings = [
            ValueSnapshot(value: 500, date: date(2026, 1, 2)),
            ValueSnapshot(value: 400, date: date(2026, 1, 10))
        ]
        let tracker = makeTracker(readings: readings)
        let after = date(2026, 2, 5)
        XCTAssertFalse(kinds(of: tracker, value: 400, asOf: after).contains(.estimatedFinal))
    }

    func testRows_underADay_hasNoDailyRow() {
        let tracker = makeTracker(start: date(2026, 1, 1, 9), end: date(2026, 1, 1, 17))
        XCTAssertFalse(kinds(of: tracker, value: 400, asOf: date(2026, 1, 1, 12)).contains(.dailyBudget))
    }

    func testRows_fewerThanTwoReadings_hasNoEstimatedFinal() {
        let none = makeTracker()
        XCTAssertFalse(kinds(of: none, value: 500).contains(.estimatedFinal))

        let one = makeTracker(readings: [ValueSnapshot(value: 450, date: date(2026, 1, 5))])
        XCTAssertFalse(kinds(of: one, value: 450).contains(.estimatedFinal))
    }

    func testRows_remainingRow_isCapitalisedWordingWithTheAmountAlone() {
        let tracker = makeTracker()
        let pace = tracker.pace(actualValue: 400, asOf: halfway)
        let row = tracker.detailRows(pace: pace, asOf: halfway, account: nil).first { $0.kind == .remaining }

        XCTAssertEqual(row?.label, "Left in this budget")
        XCTAssertEqual(row?.value, tracker.formattedValue(pace.remainingInAllowance ?? 0))
    }

    func testRows_emptyAccount_isOmitted() {
        let tracker = makeTracker(providerId: "starling")
        XCTAssertFalse(kinds(of: tracker, value: 400, account: "").contains(.account))
    }

    // MARK: - timingText

    func testTimingText_today_isTimeOnly() {
        let now = date(2026, 1, 16, 12)
        let morning = date(2026, 1, 16, 9)
        XCTAssertEqual(
            Tracker.timingText(morning, asOf: now, calendar: calendar),
            morning.formatted(date: .omitted, time: .shortened)
        )
    }

    func testTimingText_otherDay_includesTheDate() {
        let now = date(2026, 1, 16, 12)
        let earlier = date(2026, 1, 14, 9)
        let text = Tracker.timingText(earlier, asOf: now, calendar: calendar)
        XCTAssertTrue(text.contains(earlier.formatted(.dateTime.day().month(.abbreviated))))
        XCTAssertTrue(text.contains(earlier.formatted(date: .omitted, time: .shortened)))
    }
}
