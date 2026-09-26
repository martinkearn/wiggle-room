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

    /// Every tracker below runs Jan 1 00:00 -> Jan 31 00:00 (720 hours), so
    /// Jan 16 00:00 is exactly halfway.
    private var halfway: Date { date(2026, 1, 16) }

    private func makeTracker(
        name: String,
        type: TrackerType,
        unit: TrackerUnit? = nil,
        startingValue: Decimal,
        totalAllowance: Decimal
    ) -> Tracker {
        Tracker(
            name: name,
            type: type,
            unit: unit,
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    private func spendingTracker(startingValue: Decimal = 3000, budget: Decimal = 3000) -> Tracker {
        makeTracker(name: "Joint account", type: .spendingMoney, startingValue: startingValue, totalAllowance: budget)
    }

    /// Goal types store the *distance* to the goal — see
    /// `TrackerType.totalAllowance(startingValue:targetValue:)`.
    private func savingTracker(startingValue: Decimal = 200, goal: Decimal = 5000) -> Tracker {
        makeTracker(
            name: "House deposit", type: .savingMoney, startingValue: startingValue,
            totalAllowance: TrackerType.savingMoney.totalAllowance(startingValue: startingValue, targetValue: goal)
        )
    }

    private func mileageTracker(startingValue: Decimal = 10000, allowance: Decimal = 3000) -> Tracker {
        makeTracker(name: "Car lease mileage", type: .mileage, startingValue: startingValue, totalAllowance: allowance)
    }

    private func weightTracker(unit: TrackerUnit = .kilograms, startingValue: Decimal = 95, goal: Decimal = 85) -> Tracker {
        makeTracker(
            name: "Weight", type: .weightLoss, unit: unit, startingValue: startingValue,
            totalAllowance: TrackerType.weightLoss.totalAllowance(startingValue: startingValue, targetValue: goal)
        )
    }

    /// A card that starts each period empty and fills up toward its limit.
    private func creditTracker(startingValue: Decimal = 0, limit: Decimal = 600) -> Tracker {
        makeTracker(name: "Groceries card", type: .spendingCredit, startingValue: startingValue, totalAllowance: limit)
    }

    private func plainTracker(_ type: TrackerType, startingValue: Decimal, target: Decimal) -> Tracker {
        makeTracker(
            name: "Fictional count", type: type, startingValue: startingValue,
            totalAllowance: type.totalAllowance(startingValue: startingValue, targetValue: target)
        )
    }

    // MARK: - Spending (decreasing, higher is better)

    func testSpending_aheadOfPace() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 1600, asOf: halfway) // spent 1400 of 3000

        XCTAssertEqual(pace.periodHours, 720)
        XCTAssertEqual(pace.hoursElapsed, 360)
        XCTAssertEqual(pace.consumedSoFar, 1400)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.difference, 100)
        XCTAssertEqual(pace.goodness, 100, "for spending, goodness still equals the old consumption difference")
        XCTAssertTrue(pace.isAheadOfPace)
        XCTAssertEqual(pace.currentValue, 1600)
        XCTAssertEqual(pace.targetValueToday, 1500)
        XCTAssertEqual(pace.status, .good)
    }

    func testSpending_behindPace() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 1300, asOf: halfway) // spent 1700 of 3000

        XCTAssertEqual(pace.consumedSoFar, 1700)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.difference, -200)
        XCTAssertEqual(pace.goodness, -200)
        XCTAssertFalse(pace.isAheadOfPace)
        XCTAssertEqual(pace.targetValueToday, 1500)
    }

    // MARK: - Saving (increasing, higher is better) — the inverted polarity

    /// The worked example from the issue: a savings tracker £400 *ahead* of
    /// its goal pace used to be reported as red "Over Budget", because the
    /// old model read consumption as the bad thing for every tracker.
    func testSaving_aheadOfGoal_readsGreen() {
        let tracker = savingTracker(startingValue: 200, goal: 5000)
        let pace = tracker.pace(actualValue: 3000, asOf: halfway)

        XCTAssertEqual(tracker.totalAllowance, 4800)
        XCTAssertEqual(pace.targetValueToday, 2600)
        XCTAssertEqual(pace.difference, -400, "the raw consumption difference is still negative here…")
        XCTAssertEqual(pace.goodness, 400, "…but saving faster than planned is the good case")
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.statusLine(for: tracker), "Ahead of Target by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "£400")
    }

    func testSaving_behindGoal_readsRed() {
        let tracker = savingTracker(startingValue: 200, goal: 5000)
        let pace = tracker.pace(actualValue: 2000, asOf: halfway) // target 2600, so 600 short

        XCTAssertEqual(pace.goodness, -600)
        XCTAssertEqual(pace.status, .bad, "600 short of a 4,800 goal is well past the 240 amber band")
        XCTAssertEqual(pace.statusLine(for: tracker), "Behind Target by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "£600")
    }

    // MARK: - Mileage (increasing, lower is better)

    func testMileage_aheadOfPace() {
        let tracker = mileageTracker()
        let pace = tracker.pace(actualValue: 11400, asOf: halfway) // used 1400 of 3000 miles

        XCTAssertEqual(pace.consumedSoFar, 1400)
        XCTAssertEqual(pace.expectedConsumedByNow, 1500)
        XCTAssertEqual(pace.goodness, 100)
        XCTAssertTrue(pace.isAheadOfPace)
        XCTAssertEqual(pace.targetValueToday, 11500)
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.statusLine(for: tracker), "Below Allowance by")
    }

    func testMileage_behindPace() {
        let tracker = mileageTracker()
        let pace = tracker.pace(actualValue: 11700, asOf: halfway) // used 1700 of 3000 miles

        XCTAssertEqual(pace.consumedSoFar, 1700)
        XCTAssertEqual(pace.goodness, -200)
        XCTAssertFalse(pace.isAheadOfPace)
        XCTAssertEqual(pace.status, .bad, "200 over a 3,000 allowance is past the 150 amber band")
        XCTAssertEqual(pace.statusLine(for: tracker), "Over Allowance by")
    }

    // MARK: - Weight loss (decreasing, lower is better) — the other inversion

    func testWeightLoss_belowTarget_readsGreen() {
        let tracker = weightTracker(startingValue: 95, goal: 85)
        let pace = tracker.pace(actualValue: 89, asOf: halfway) // target today 90

        XCTAssertEqual(tracker.totalAllowance, 10)
        XCTAssertEqual(pace.targetValueToday, 90)
        XCTAssertEqual(pace.difference, -1, "losing faster than planned looks 'over-consumed' to the raw figure…")
        XCTAssertEqual(pace.goodness, 1, "…but it's exactly the good case")
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.statusLine(for: tracker), "Ahead of Target by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "1 kg")
    }

    func testWeightLoss_aboveTarget_readsBehind() {
        let tracker = weightTracker(startingValue: 95, goal: 85)
        let pace = tracker.pace(actualValue: 92, asOf: halfway) // target today 90

        XCTAssertEqual(pace.goodness, -2)
        XCTAssertEqual(pace.status, .bad)
        XCTAssertEqual(pace.statusLine(for: tracker), "Behind Target by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "2 kg")
    }

    // MARK: - Spending credit (increasing, lower is better)

    /// The worked example from the issue: £600 of groceries a month on a card
    /// that starts each period at zero. Halfway through, £250 on the card is
    /// £50 less than the £300 pace — the good case, even though the balance is
    /// rising.
    func testSpendingCredit_belowLimitPace_readsGreen() {
        let tracker = creditTracker(startingValue: 0, limit: 600)
        let pace = tracker.pace(actualValue: 250, asOf: halfway)

        XCTAssertEqual(pace.consumedSoFar, 250)
        XCTAssertEqual(pace.expectedConsumedByNow, 300)
        XCTAssertEqual(pace.targetValueToday, 300)
        XCTAssertEqual(pace.goodness, 50)
        XCTAssertTrue(pace.isAheadOfPace)
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.statusLine(for: tracker), "Below Limit by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "£50")
    }

    func testSpendingCredit_overLimitPace_readsRed() {
        let tracker = creditTracker(startingValue: 0, limit: 600)
        let pace = tracker.pace(actualValue: 400, asOf: halfway) // pace is 300

        XCTAssertEqual(pace.goodness, -100)
        XCTAssertFalse(pace.isAheadOfPace)
        XCTAssertEqual(pace.status, .bad, "100 over a 600 limit is past the 30 amber band")
        XCTAssertEqual(pace.statusLine(for: tracker), "Over Limit by")
    }

    // MARK: - Plain numbers (no unit, both directions)

    func testNumberRising_aheadOfTarget_readsGreenWithNoUnit() {
        let tracker = plainTracker(.numberRising, startingValue: 0, target: 120)
        let pace = tracker.pace(actualValue: 70, asOf: halfway) // pace is 60

        XCTAssertEqual(tracker.totalAllowance, 120)
        XCTAssertEqual(pace.targetValueToday, 60)
        XCTAssertEqual(pace.goodness, 10)
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.statusLine(for: tracker), "Ahead of Target by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "10", "a plain number carries no symbol")
    }

    func testNumberFalling_aboveTarget_readsBehind() {
        let tracker = plainTracker(.numberFalling, startingValue: 120, target: 0)
        let pace = tracker.pace(actualValue: 80, asOf: halfway) // pace is 60

        XCTAssertEqual(tracker.totalAllowance, 120)
        XCTAssertEqual(pace.targetValueToday, 60)
        XCTAssertEqual(pace.goodness, -20)
        XCTAssertEqual(pace.status, .bad)
        XCTAssertEqual(pace.statusLine(for: tracker), "Behind Target by")
        XCTAssertEqual(pace.displayDifference(for: tracker), "20")
    }

    // MARK: - Amber band, including the per-unit floor (§7)

    func testAmberBand_spending_isFivePercentOfTheAllowance() {
        let tracker = spendingTracker(startingValue: 500, budget: 500)
        XCTAssertEqual(tracker.pace(actualValue: 500, asOf: halfway).amberBand, 25)
    }

    func testAmberBand_saving_isFivePercentOfTheDistanceToTheGoal() {
        let tracker = savingTracker(startingValue: 200, goal: 5000) // 4,800 allowance
        XCTAssertEqual(tracker.pace(actualValue: 200, asOf: halfway).amberBand, 240)
    }

    func testAmberBand_mileage_isFivePercentOfTheAllowance() {
        let tracker = mileageTracker(startingValue: 0, allowance: 10_000)
        XCTAssertEqual(tracker.pace(actualValue: 0, asOf: halfway).amberBand, 500)
    }

    func testAmberBand_weightInKilograms_floorTakesOver() {
        let tracker = weightTracker(startingValue: 95, goal: 85) // 5% of 10 kg = 0.5
        XCTAssertEqual(tracker.pace(actualValue: 95, asOf: halfway).amberBand, 1, "the 1.0 kg floor binds")
    }

    func testAmberBand_weightInPounds_floorTakesOver() {
        let tracker = weightTracker(unit: .pounds, startingValue: 210, goal: 180) // 5% of 30 lb = 1.5
        XCTAssertEqual(tracker.pace(actualValue: 210, asOf: halfway).amberBand, 2, "the 2 lb floor binds")
    }

    func testAmberBand_largeWeightGoal_percentageTakesOverAgain() {
        let tracker = weightTracker(startingValue: 130, goal: 100) // 5% of 30 kg = 1.5 > 1.0 floor
        XCTAssertEqual(tracker.pace(actualValue: 130, asOf: halfway).amberBand, Decimal(string: "1.5"))
    }

    func testAmberBand_tinyCurrencyAllowance_floorTakesOver() {
        let tracker = spendingTracker(startingValue: 1, budget: Decimal(string: "0.20")!) // 5% = 0.01
        XCTAssertEqual(tracker.pace(actualValue: 1, asOf: halfway).amberBand, Decimal(string: "0.02"))
    }

    // MARK: - Status thresholds around the band

    func testStatus_aheadOfPace_isGood() {
        let pace = spendingTracker().pace(actualValue: 1600, asOf: halfway) // 100 ahead
        XCTAssertEqual(pace.status, .good)
    }

    func testStatus_behindByAnyAmount_isAtLeastWarning() {
        // Expected consumed 1500; behind by just 20 — even a tiny shortfall
        // must not read as green, since the actual figure is genuinely below
        // the target figure shown right next to it.
        let pace = spendingTracker().pace(actualValue: 1480, asOf: halfway)
        XCTAssertEqual(pace.status, .warning)
    }

    func testStatus_behindByExactlyTheBand_isStillWarning() {
        // 150 is exactly 5% of a 3,000 allowance.
        let pace = spendingTracker().pace(actualValue: 1350, asOf: halfway)
        XCTAssertEqual(pace.amberBand, 150)
        XCTAssertEqual(pace.status, .warning)
    }

    func testStatus_behindByMoreThanTheBand_isBad() {
        let pace = spendingTracker().pace(actualValue: Decimal(string: "1349.99")!, asOf: halfway)
        XCTAssertEqual(pace.status, .bad)
    }

    func testStatus_weightWithinTheFloor_staysAmberRatherThanRed() {
        let tracker = weightTracker(startingValue: 95, goal: 85) // band 1.0 kg
        // Target today is 90 kg; a retained-water morning reads 1 kg high.
        // A bare 5% band (0.5 kg) would fire the app's loudest signal at
        // someone who is exactly on pace.
        let pace = tracker.pace(actualValue: 91, asOf: halfway)
        XCTAssertEqual(pace.status, .warning)
        XCTAssertEqual(pace.statusLine(for: tracker), "Slightly Behind Target")
        XCTAssertEqual(pace.displayDifference(for: tracker), "+1 kg", "amber shows the signed distance from today's target")
    }

    func testStatus_weightBeyondTheFloor_isBad() {
        let tracker = weightTracker(startingValue: 95, goal: 85)
        let pace = tracker.pace(actualValue: Decimal(string: "91.5")!, asOf: halfway)
        XCTAssertEqual(pace.status, .bad)
    }

    // MARK: - Period-start / period-end edges

    func testEdge_atExactPeriodStart_noTimeElapsed() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 3000, asOf: tracker.startDate)

        XCTAssertEqual(pace.hoursElapsed, 0)
        XCTAssertEqual(pace.expectedConsumedByNow, 0)
        XCTAssertEqual(pace.consumedSoFar, 0)
        XCTAssertEqual(pace.goodness, 0)
        XCTAssertTrue(pace.isAheadOfPace) // exactly on pace counts as ahead
    }

    func testEdge_beforePeriodStart_hoursElapsedClampedToZero() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 3000, asOf: tracker.startDate.addingTimeInterval(-3600))

        XCTAssertEqual(pace.hoursElapsed, 0)
        XCTAssertEqual(pace.expectedConsumedByNow, 0)
    }

    func testEdge_atExactPeriodEnd_fullAllowanceExpected() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 0, asOf: tracker.endDate) // spent exactly the full 3000

        XCTAssertEqual(pace.hoursElapsed, pace.periodHours)
        XCTAssertEqual(pace.expectedConsumedByNow, 3000)
        XCTAssertEqual(pace.consumedSoFar, 3000)
        XCTAssertEqual(pace.goodness, 0)
        XCTAssertEqual(pace.targetValueToday, 0)
    }

    func testEdge_afterPeriodEnd_hoursElapsedClampedToPeriodHours() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 0, asOf: tracker.endDate.addingTimeInterval(10 * 24 * 3600))

        XCTAssertEqual(pace.hoursElapsed, pace.periodHours)
        XCTAssertEqual(pace.expectedConsumedByNow, tracker.totalAllowance)
    }

    // MARK: - displayDifference(for:) sign rules

    func testDisplayDifference_good_showsUnsignedMagnitude() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 1600, asOf: halfway) // 100 ahead
        XCTAssertEqual(pace.status, .good)
        XCTAssertEqual(pace.displayDifference(for: tracker), "£100",
                       "the status word and colour already convey direction, so a sign would be redundant")
    }

    func testDisplayDifference_bad_showsUnsignedMagnitude() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 1200, asOf: halfway) // 300 behind
        XCTAssertEqual(pace.status, .bad)
        XCTAssertEqual(pace.displayDifference(for: tracker), "£300")
    }

    func testDisplayDifference_warning_showsSignedDistanceFromTarget() {
        let tracker = spendingTracker()
        let pace = tracker.pace(actualValue: 1440, asOf: halfway) // 60 behind, inside the 150 band
        XCTAssertEqual(pace.status, .warning)
        XCTAssertEqual(pace.displayDifference(for: tracker), "-£60",
                       "the early-warning band isn't a clean over/under yet, so it keeps the sign")
    }

    func testDisplayDifference_warningOnAnIncreasingTracker_signMirrorsTheNumber() {
        let tracker = mileageTracker()
        // 100 miles over the target, inside the 150 mile band. A higher
        // number than planned takes a "+", however that reads as news.
        let pace = tracker.pace(actualValue: 11600, asOf: halfway)
        XCTAssertEqual(pace.status, .warning)
        XCTAssertEqual(pace.displayDifference(for: tracker), "+100 mi")
    }

    // MARK: - statusLine(for:) wording per type

    func testStatusLine_usesEachTypesOwnWording() {
        let spending = spendingTracker()
        XCTAssertEqual(spending.pace(actualValue: 1600, asOf: halfway).statusLine(for: spending), "Below Budget by")
        XCTAssertEqual(spending.pace(actualValue: 1200, asOf: halfway).statusLine(for: spending), "Over Budget by")
        XCTAssertEqual(spending.pace(actualValue: 1440, asOf: halfway).statusLine(for: spending), "Just Over Budget",
                       "the warning label already reads as a complete phrase")

        let mileage = mileageTracker()
        XCTAssertEqual(mileage.pace(actualValue: 11400, asOf: halfway).statusLine(for: mileage), "Below Allowance by")
        XCTAssertEqual(mileage.pace(actualValue: 11600, asOf: halfway).statusLine(for: mileage), "Just Over Allowance")
        XCTAssertEqual(mileage.pace(actualValue: 11700, asOf: halfway).statusLine(for: mileage), "Over Allowance by")

        let saving = savingTracker()
        XCTAssertEqual(saving.pace(actualValue: 3000, asOf: halfway).statusLine(for: saving), "Ahead of Target by")
        XCTAssertEqual(saving.pace(actualValue: 2000, asOf: halfway).statusLine(for: saving), "Behind Target by")

        let weight = weightTracker()
        XCTAssertEqual(weight.pace(actualValue: 89, asOf: halfway).statusLine(for: weight), "Ahead of Target by")
        XCTAssertEqual(weight.pace(actualValue: 92, asOf: halfway).statusLine(for: weight), "Behind Target by")
    }

    // MARK: - remainingInAllowanceCaption(for:)

    func testRemainingInAllowanceCaption_usesEachTypesOwnWording() {
        let spending = spendingTracker(startingValue: 500, budget: 500)
        XCTAssertEqual(spending.pace(actualValue: 400, asOf: halfway).remainingInAllowanceCaption(for: spending),
                       "£400 left in this budget")

        let mileage = mileageTracker(allowance: 3000)
        XCTAssertEqual(mileage.pace(actualValue: 11000, asOf: halfway).remainingInAllowanceCaption(for: mileage),
                       "2,000 mi left in this allowance")

        let saving = savingTracker(startingValue: 200, goal: 5000)
        XCTAssertEqual(saving.pace(actualValue: 3000, asOf: halfway).remainingInAllowanceCaption(for: saving),
                       "£2,000 still to save")

        let weight = weightTracker(startingValue: 95, goal: 85)
        XCTAssertEqual(weight.pace(actualValue: 89, asOf: halfway).remainingInAllowanceCaption(for: weight),
                       "4 kg still to lose")
    }

    func testRemainingInAllowanceCaption_allowanceFullyUsed_isNil() {
        let tracker = spendingTracker(startingValue: 500, budget: 500)
        let pace = tracker.pace(actualValue: 0, asOf: date(2026, 1, 31)) // spent exactly 500
        XCTAssertNil(pace.remainingInAllowanceCaption(for: tracker))
    }

    func testRemainingInAllowanceCaption_allowanceExceeded_isNil() {
        let tracker = spendingTracker(startingValue: 500, budget: 500)
        let pace = tracker.pace(actualValue: -50, asOf: date(2026, 1, 31)) // overspent by 50
        XCTAssertNil(pace.remainingInAllowanceCaption(for: tracker), "should not show a negative amount as if it were 'left'")
    }

    func testRemainingInAllowanceCaption_goalReached_isNil() {
        let tracker = savingTracker(startingValue: 200, goal: 5000)
        let pace = tracker.pace(actualValue: 5000, asOf: halfway)
        XCTAssertNil(pace.remainingInAllowanceCaption(for: tracker), "nothing left to save once the goal is met")
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
            type: .spendingMoney,
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
