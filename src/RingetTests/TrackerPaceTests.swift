//
//  TrackerPaceTests.swift
//  RingetTests
//

import XCTest
@testable import Ringet

final class TrackerPaceTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // A 30-day money tracker: Jan 1 00:00 -> Jan 31 00:00.
    private func moneyTracker(startingValue: Decimal = 3000, totalAllowance: Decimal = 3000) -> Tracker {
        Tracker(
            name: "Joint account",
            unit: "£",
            direction: .decreasing,
            connectedSourceId: UUID(),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    // A 30-day mileage tracker: Jan 1 00:00 -> Jan 31 00:00.
    private func mileageTracker(startingValue: Decimal = 10000, totalAllowance: Decimal = 3000) -> Tracker {
        Tracker(
            name: "Car lease mileage",
            unit: "mi",
            direction: .increasing,
            connectedSourceId: UUID(),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    // MARK: - Decreasing (money) tracker

    func testDecreasingTracker_aheadOfPace() {
        let tracker = moneyTracker()
        let halfway = date(2026, 1, 16) // 15 days = 360h elapsed of 720h total -> 50%
        let pace = tracker.pace(actualValue: 1600, asOf: halfway) // spent 1400 of 3000

        XCTAssertEqual(pace.periodHours, 720)
        XCTAssertEqual(pace.hoursElapsed, 360)
        XCTAssertEqual(pace.consumedSoFar, 1400)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.difference, 100)
        XCTAssertTrue(pace.isAheadOfPace)
        XCTAssertEqual(pace.currentValue, 1600)
        XCTAssertEqual(pace.targetValueToday, 1500)
    }

    func testDecreasingTracker_behindPace() {
        let tracker = moneyTracker()
        let halfway = date(2026, 1, 16)
        let pace = tracker.pace(actualValue: 1300, asOf: halfway) // spent 1700 of 3000

        XCTAssertEqual(pace.consumedSoFar, 1700)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.difference, -200)
        XCTAssertFalse(pace.isAheadOfPace)
        XCTAssertEqual(pace.targetValueToday, 1500)
    }

    // MARK: - Increasing (mileage) tracker

    func testIncreasingTracker_aheadOfPace() {
        let tracker = mileageTracker()
        let halfway = date(2026, 1, 16)
        let pace = tracker.pace(actualValue: 11400, asOf: halfway) // used 1400 of 3000 miles

        XCTAssertEqual(pace.consumedSoFar, 1400)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.difference, 100)
        XCTAssertTrue(pace.isAheadOfPace)
        XCTAssertEqual(pace.currentValue, 11400)
        XCTAssertEqual(pace.targetValueToday, 11500)
    }

    func testIncreasingTracker_behindPace() {
        let tracker = mileageTracker()
        let halfway = date(2026, 1, 16)
        let pace = tracker.pace(actualValue: 11700, asOf: halfway) // used 1700 of 3000 miles

        XCTAssertEqual(pace.consumedSoFar, 1700)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.difference, -200)
        XCTAssertFalse(pace.isAheadOfPace)
        XCTAssertEqual(pace.targetValueToday, 11500)
    }

    // MARK: - Period-start / period-end edges

    func testEdge_atExactPeriodStart_noTimeElapsed() {
        let tracker = moneyTracker()
        let pace = tracker.pace(actualValue: 3000, asOf: tracker.startDate)

        XCTAssertEqual(pace.hoursElapsed, 0)
        XCTAssertEqual(pace.expectedConsumedByNow, 0)
        XCTAssertEqual(pace.consumedSoFar, 0)
        XCTAssertEqual(pace.difference, 0)
        XCTAssertTrue(pace.isAheadOfPace) // difference == 0 counts as on/ahead of pace
    }

    func testEdge_beforePeriodStart_hoursElapsedClampedToZero() {
        let tracker = moneyTracker()
        let beforeStart = tracker.startDate.addingTimeInterval(-3600)
        let pace = tracker.pace(actualValue: 3000, asOf: beforeStart)

        XCTAssertEqual(pace.hoursElapsed, 0)
        XCTAssertEqual(pace.expectedConsumedByNow, 0)
    }

    func testEdge_atExactPeriodEnd_fullAllowanceExpected() {
        let tracker = moneyTracker()
        let pace = tracker.pace(actualValue: 0, asOf: tracker.endDate) // spent exactly the full 3000

        XCTAssertEqual(pace.hoursElapsed, pace.periodHours)
        XCTAssertEqual(pace.expectedConsumedByNow, 3000)
        XCTAssertEqual(pace.consumedSoFar, 3000)
        XCTAssertEqual(pace.difference, 0)
        XCTAssertEqual(pace.targetValueToday, 0)
    }

    func testEdge_afterPeriodEnd_hoursElapsedClampedToPeriodHours() {
        let tracker = moneyTracker()
        let longAfterEnd = tracker.endDate.addingTimeInterval(10 * 24 * 3600)
        let pace = tracker.pace(actualValue: 0, asOf: longAfterEnd)

        XCTAssertEqual(pace.hoursElapsed, pace.periodHours)
        XCTAssertEqual(pace.expectedConsumedByNow, tracker.totalAllowance)
    }

    // MARK: - DST-safe elapsed hours (spec §4.3)

    /// Builds start/end dates for the local calendar day containing the next
    /// Europe/London DST transition, using DST-aware calendar day arithmetic
    /// (`Calendar.date(byAdding:)`) rather than a fixed `+24h` offset. Also
    /// independently derives the expected day length (23h or 25h) from the
    /// transition's DST-offset change, so the test has a concrete expected
    /// constant rather than re-deriving the same formula under test.
    func testHoursElapsed_isDSTSafe_acrossLondonTransition() throws {
        let london = TimeZone(identifier: "Europe/London")!
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = london

        let referenceNow = date(2026, 1, 1)
        guard let transition = london.nextDaylightSavingTimeTransition(after: referenceNow) else {
            throw XCTSkip("No DST transition available from TimeZoneData on this platform")
        }

        let offsetBefore = london.daylightSavingTimeOffset(for: transition.addingTimeInterval(-60))
        let offsetAfter = london.daylightSavingTimeOffset(for: transition.addingTimeInterval(60))
        let expectedDayHours: Double = offsetAfter > offsetBefore ? 23 : 25
        XCTAssertNotEqual(expectedDayHours, 24, "test setup should land on an actual DST transition day")

        let transitionDayComponents = londonCalendar.dateComponents([.year, .month, .day], from: transition)
        let startOfTransitionDay = londonCalendar.date(from: DateComponents(
            year: transitionDayComponents.year,
            month: transitionDayComponents.month,
            day: transitionDayComponents.day,
            hour: 0, minute: 0, second: 0
        ))!
        let startOfNextDay = londonCalendar.date(byAdding: .day, value: 1, to: startOfTransitionDay)!

        let tracker = Tracker(
            name: "DST test tracker",
            unit: "£",
            direction: .decreasing,
            connectedSourceId: UUID(),
            startDate: startOfTransitionDay,
            endDate: startOfNextDay,
            startingValue: 100,
            totalAllowance: 100
        )

        let pace = tracker.pace(actualValue: 100, asOf: startOfNextDay)

        XCTAssertEqual(pace.periodHours, expectedDayHours)
        XCTAssertEqual(pace.hoursElapsed, expectedDayHours)
    }
}
