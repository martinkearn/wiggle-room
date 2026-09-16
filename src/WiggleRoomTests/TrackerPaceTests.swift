//
//  TrackerPaceTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

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
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
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
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
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

    // MARK: - Status thresholds (§3.2 amber early-warning band)

    func testStatus_aheadOfPace_isGood() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let halfway = date(2026, 1, 16)
        let pace = tracker.pace(actualValue: 1600, asOf: halfway) // 100 ahead, of 3000
        XCTAssertEqual(pace.status, .good)
    }

    func testStatus_behindByLessThanOnePercent_isGood() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let halfway = date(2026, 1, 16)
        // Expected consumed 1500; behind by 20 (~0.67% of 3000) stays green.
        let pace = tracker.pace(actualValue: 1480, asOf: halfway)
        XCTAssertEqual(pace.status, .good)
    }

    func testStatus_behindByOneToFivePercent_isWarning() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let halfway = date(2026, 1, 16)
        // Expected consumed 1500; behind by 60 (2% of 3000).
        let pace = tracker.pace(actualValue: 1440, asOf: halfway)
        XCTAssertEqual(pace.status, .warning)
    }

    func testStatus_behindByMoreThanFivePercent_isBad() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let halfway = date(2026, 1, 16)
        // Expected consumed 1500; behind by 300 (10% of 3000).
        let pace = tracker.pace(actualValue: 1200, asOf: halfway)
        XCTAssertEqual(pace.status, .bad)
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

    // MARK: - displayDifference(for:) sign/wording rules

    func testDisplayDifference_budgetTracker_good_showsUnsignedMagnitude() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 1600, asOf: date(2026, 1, 16)) // 100 ahead
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.displayDifference(for: tracker), "£100", "good/bad status colors already convey direction, so the sign would be redundant")
    }

    func testDisplayDifference_budgetTracker_bad_showsUnsignedMagnitude() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 1200, asOf: date(2026, 1, 16)) // 300 behind (10%)
        XCTAssertEqual(pace.status, .bad)
        XCTAssertEqual(pace.displayDifference(for: tracker), "£300")
    }

    func testDisplayDifference_budgetTracker_warning_showsSignedValue() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 1440, asOf: date(2026, 1, 16)) // 60 behind (2%)
        XCTAssertEqual(pace.status, .warning)
        XCTAssertEqual(pace.displayDifference(for: tracker), "-£60", "the early-warning band isn't a clean over/under yet, so it keeps the sign")
    }

    func testDisplayDifference_nonBudgetTracker_alwaysShowsSignedValue() {
        let tracker = mileageTracker()
        let ahead = tracker.pace(actualValue: 11400, asOf: date(2026, 1, 16)) // 100 ahead
        let behind = tracker.pace(actualValue: 11700, asOf: date(2026, 1, 16)) // 200 behind

        XCTAssertEqual(ahead.displayDifference(for: tracker), "+100 mi")
        XCTAssertEqual(behind.displayDifference(for: tracker), "-200 mi")
    }

    // MARK: - statusLine(for:) wording rules

    func testStatusLine_budgetTracker_good_appendsBy() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 1600, asOf: date(2026, 1, 16))
        XCTAssertEqual(pace.statusLine(for: tracker), "Under Budget by")
    }

    func testStatusLine_budgetTracker_bad_appendsBy() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 1200, asOf: date(2026, 1, 16))
        XCTAssertEqual(pace.statusLine(for: tracker), "Over Budget by")
    }

    func testStatusLine_budgetTracker_warning_omitsBy() {
        let tracker = moneyTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 1440, asOf: date(2026, 1, 16))
        XCTAssertEqual(pace.statusLine(for: tracker), "Slightly Over Budget", "the warning label already reads as a complete phrase")
    }

    func testStatusLine_nonBudgetTracker_neverAppendsBy() {
        let tracker = mileageTracker()
        let ahead = tracker.pace(actualValue: 11400, asOf: date(2026, 1, 16)) // 100 ahead
        let behind = tracker.pace(actualValue: 11700, asOf: date(2026, 1, 16)) // 200 behind (~6.7%, .bad)

        XCTAssertEqual(ahead.statusLine(for: tracker), "On Track")
        XCTAssertEqual(behind.statusLine(for: tracker), "Needs Attention")
    }

    // MARK: - remainingInAllowanceCaption(for:)

    func testRemainingInAllowanceCaption_budgetTracker_reportsAmountLeft() {
        let tracker = moneyTracker(startingValue: 500, totalAllowance: 500)
        let pace = tracker.pace(actualValue: 400, asOf: date(2026, 1, 16)) // spent 100 of 500
        XCTAssertEqual(pace.remainingInAllowanceCaption(for: tracker), "£400 left in this budget")
    }

    func testRemainingInAllowanceCaption_nonBudgetTracker_usesGenericWording() {
        let tracker = mileageTracker(totalAllowance: 3000)
        let pace = tracker.pace(actualValue: 11000, asOf: date(2026, 1, 16)) // used 1000 of 3000
        XCTAssertEqual(pace.remainingInAllowanceCaption(for: tracker), "2,000 mi left to use")
    }

    func testRemainingInAllowanceCaption_allowanceFullyUsed_isNil() {
        let tracker = moneyTracker(startingValue: 500, totalAllowance: 500)
        let pace = tracker.pace(actualValue: 0, asOf: date(2026, 1, 31)) // spent exactly 500
        XCTAssertNil(pace.remainingInAllowanceCaption(for: tracker))
    }

    func testRemainingInAllowanceCaption_allowanceExceeded_isNil() {
        let tracker = moneyTracker(startingValue: 500, totalAllowance: 500)
        let pace = tracker.pace(actualValue: -50, asOf: date(2026, 1, 31)) // overspent by 50
        XCTAssertNil(pace.remainingInAllowanceCaption(for: tracker), "should not show a negative amount as if it were 'left'")
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
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
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
