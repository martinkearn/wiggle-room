//
//  TrackerTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class TrackerTests: XCTestCase {

    private func tracker(
        unit: String = "£",
        direction: TrackerDirection = .decreasing,
        startingValue: Decimal = 500,
        totalAllowance: Decimal = 500
    ) -> Tracker {
        Tracker(
            name: "Test tracker",
            unit: unit,
            direction: direction,
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    // MARK: - isCurrencyUnit / usesBudgetLanguage

    func testIsCurrencyUnit_recognizesKnownSymbols() {
        XCTAssertTrue(Tracker.isCurrencyUnit("£"))
        XCTAssertTrue(Tracker.isCurrencyUnit("$"))
        XCTAssertTrue(Tracker.isCurrencyUnit("€"))
    }

    func testIsCurrencyUnit_rejectsSuffixUnits() {
        XCTAssertFalse(Tracker.isCurrencyUnit("mi"))
        XCTAssertFalse(Tracker.isCurrencyUnit("km"))
        XCTAssertFalse(Tracker.isCurrencyUnit("hrs"))
    }

    func testUsesBudgetLanguage_onlyForDecreasingCurrencyTrackers() {
        XCTAssertTrue(tracker(unit: "£", direction: .decreasing).usesBudgetLanguage)
        XCTAssertFalse(tracker(unit: "£", direction: .increasing).usesBudgetLanguage, "an increasing currency tracker (e.g. savings goal) isn't a 'budget'")
        XCTAssertFalse(tracker(unit: "mi", direction: .decreasing).usesBudgetLanguage, "a decreasing non-currency tracker (e.g. mileage allowance) isn't a 'budget' either")
    }

    func testCurrentValueLabel_matchesCurrencyVsOtherUnits() {
        XCTAssertEqual(tracker(unit: "£").currentValueLabel, "Current Balance")
        XCTAssertEqual(tracker(unit: "mi").currentValueLabel, "Current")
    }

    // MARK: - formattedValue

    func testFormattedValue_currencyUnit_prefixesSymbolWithNoSpace() {
        let t = tracker(unit: "£")
        XCTAssertEqual(t.formattedValue(1234.56), "£1,234.56")
    }

    func testFormattedValue_suffixUnit_appendsUnitWithSpace() {
        let t = tracker(unit: "mi")
        XCTAssertEqual(t.formattedValue(1234), "1,234 mi")
    }

    func testFormattedValue_wholeNumber_showsNoDecimalPlaces() {
        let t = tracker(unit: "£")
        XCTAssertEqual(t.formattedValue(684), "£684")
    }

    func testFormattedValue_fractional_alwaysShowsExactlyTwoDecimalPlaces() {
        let t = tracker(unit: "£")
        XCTAssertEqual(t.formattedValue(692.4), "£692.40")
    }

    func testFormattedValue_negative_alwaysShowsMinusSignRegardlessOfSignedFlag() {
        let t = tracker(unit: "£")
        XCTAssertEqual(t.formattedValue(-50, signed: false), "-£50")
        XCTAssertEqual(t.formattedValue(-50, signed: true), "-£50")
    }

    func testFormattedValue_nonNegativeWithSignedTrue_prefixesPlus() {
        let t = tracker(unit: "£")
        XCTAssertEqual(t.formattedValue(50, signed: true), "+£50")
        XCTAssertEqual(t.formattedValue(0, signed: true), "+£0")
    }

    func testFormattedValue_nonNegativeWithSignedFalse_showsNoSign() {
        let t = tracker(unit: "£")
        XCTAssertEqual(t.formattedValue(50, signed: false), "£50")
    }

    func testFormattedValue_suffixUnit_neverShowsDecimalPlaces() {
        let t = tracker(unit: "mi")
        XCTAssertEqual(t.formattedValue(1234.56), "1,235 mi", "a fractional mile isn't a meaningful reading, so it rounds rather than showing decimals")
    }

    // MARK: - projectedRemainder

    func testProjectedRemainder_increasingTracker_isAlwaysNil() {
        let t = tracker(direction: .increasing, startingValue: 10_000, totalAllowance: 3_000)
        XCTAssertNil(t.projectedRemainder, "projected remainder is only meaningful for spend-down trackers")
    }

    func testProjectedRemainder_startingValueExceedsBudget_isPositive() {
        let t = tracker(direction: .decreasing, startingValue: 500, totalAllowance: 400)
        XCTAssertEqual(t.projectedRemainder, 100)
    }

    func testProjectedRemainder_budgetExceedsStartingValue_isNegative() {
        let t = tracker(direction: .decreasing, startingValue: 400, totalAllowance: 500)
        XCTAssertEqual(t.projectedRemainder, -100)
    }

    func testProjectedRemainder_startingValueEqualsBudget_isNil() {
        let t = tracker(direction: .decreasing, startingValue: 500, totalAllowance: 500)
        XCTAssertNil(t.projectedRemainder, "no remainder worth surfacing when the budget exactly matches the starting value")
    }

    // MARK: - remainingAtEndCaption

    func testRemainingAtEndCaption_startingValueExceedsBudget_saysWhatWillRemain() {
        let t = tracker(unit: "£", direction: .decreasing, startingValue: 500, totalAllowance: 400)
        XCTAssertEqual(t.remainingAtEndCaption, "£100 left at the end")
    }

    func testRemainingAtEndCaption_budgetExceedsStartingValue_saysByHowMuch() {
        let t = tracker(unit: "£", direction: .decreasing, startingValue: 400, totalAllowance: 500)
        XCTAssertEqual(t.remainingAtEndCaption, "Budget is £100 more than the starting value")
    }

    func testRemainingAtEndCaption_startingValueEqualsBudget_isNil() {
        let t = tracker(unit: "£", direction: .decreasing, startingValue: 500, totalAllowance: 500)
        XCTAssertNil(t.remainingAtEndCaption)
    }

    // MARK: - periodRemainingText(asOf:)

    func testPeriodRemainingText_multipleDaysLeft_pluralizes() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start
        t.endDate = start.addingTimeInterval(3 * 24 * 3600 + 3600) // just over 3 days
        XCTAssertEqual(t.periodRemainingText(asOf: start), "3 days remaining")
    }

    func testPeriodRemainingText_oneDayLeft_singular() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start
        t.endDate = start.addingTimeInterval(1 * 24 * 3600 + 3600)
        XCTAssertEqual(t.periodRemainingText(asOf: start), "1 day remaining")
    }

    func testPeriodRemainingText_lessThanADay_fallsBackToHours() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start
        t.endDate = start.addingTimeInterval(5 * 3600)
        XCTAssertEqual(t.periodRemainingText(asOf: start), "5 hours remaining")
    }

    func testPeriodRemainingText_periodOver_saysEnded() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start.addingTimeInterval(-7200)
        t.endDate = start.addingTimeInterval(-3600)
        XCTAssertEqual(t.periodRemainingText(asOf: start), "Period ended")
    }

    func testPeriodRemainingText_lessThanAnHour_fallsBackToMinutes() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start
        t.endDate = start.addingTimeInterval(42 * 60)
        XCTAssertEqual(t.periodRemainingText(asOf: start), "42 minutes remaining")
    }

    // MARK: - isCompleted(asOf:)

    func testIsCompleted_beforeEndDate_isFalse() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start
        t.endDate = start.addingTimeInterval(3600)
        XCTAssertFalse(t.isCompleted(asOf: start))
    }

    func testIsCompleted_atOrAfterEndDate_isTrue() {
        let start = Date()
        let t = tracker(startingValue: 100, totalAllowance: 100)
        t.startDate = start
        t.endDate = start.addingTimeInterval(3600)
        XCTAssertTrue(t.isCompleted(asOf: t.endDate))
        XCTAssertTrue(t.isCompleted(asOf: t.endDate.addingTimeInterval(1)))
    }
}
