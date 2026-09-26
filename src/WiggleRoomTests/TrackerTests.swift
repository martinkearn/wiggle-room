//
//  TrackerTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class TrackerTests: XCTestCase {

    private func tracker(
        type: TrackerType = .spendingMoney,
        unit: TrackerUnit? = nil,
        startingValue: Decimal = 500,
        totalAllowance: Decimal = 500
    ) -> Tracker {
        Tracker(
            name: "Test tracker",
            type: type,
            unit: unit,
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    // MARK: - Type resolution

    func testTrackerType_unrecognizedRawValue_fallsBackRatherThanFaulting() {
        let t = tracker()
        t.typeRawValue = "somethingAFutureBuildInvented"
        XCTAssertEqual(t.trackerType, TrackerType.fallback, "a newer device's type must not break an older one")
        XCTAssertEqual(t.trackerUnit, TrackerType.fallback.defaultUnit)
    }

    func testTrackerUnit_unrecognizedSymbol_fallsBackToTheTypesDefault() {
        let t = tracker(type: .mileage)
        t.unit = "hrs"
        XCTAssertEqual(t.trackerUnit, .miles)
    }

    func testTypeDefinitions_matchTheSpecifiedTwoByTwo() {
        XCTAssertEqual(TrackerType.spendingMoney.direction, .decreasing)
        XCTAssertTrue(TrackerType.spendingMoney.higherIsBetter)
        XCTAssertEqual(TrackerType.spendingMoney.orientation, .allowance)

        // The mirror of Spending Money: the same spending, counted upward on
        // a card, so a lower balance is the good side.
        XCTAssertEqual(TrackerType.spendingCredit.direction, .increasing)
        XCTAssertFalse(TrackerType.spendingCredit.higherIsBetter)
        XCTAssertEqual(TrackerType.spendingCredit.orientation, .allowance)

        XCTAssertEqual(TrackerType.savingMoney.direction, .increasing)
        XCTAssertTrue(TrackerType.savingMoney.higherIsBetter)
        XCTAssertEqual(TrackerType.savingMoney.orientation, .goal)

        XCTAssertEqual(TrackerType.mileage.direction, .increasing)
        XCTAssertFalse(TrackerType.mileage.higherIsBetter)
        XCTAssertEqual(TrackerType.mileage.orientation, .allowance)

        XCTAssertEqual(TrackerType.weightLoss.direction, .decreasing)
        XCTAssertFalse(TrackerType.weightLoss.higherIsBetter)
        XCTAssertEqual(TrackerType.weightLoss.orientation, .goal)

        XCTAssertEqual(TrackerType.numberRising.direction, .increasing)
        XCTAssertTrue(TrackerType.numberRising.higherIsBetter)
        XCTAssertEqual(TrackerType.numberRising.orientation, .goal)

        XCTAssertEqual(TrackerType.numberFalling.direction, .decreasing)
        XCTAssertFalse(TrackerType.numberFalling.higherIsBetter)
        XCTAssertEqual(TrackerType.numberFalling.orientation, .goal)
    }

    func testEveryTypesDefaultUnitIsOneItPermits() {
        for type in TrackerType.allCases {
            XCTAssertTrue(type.permittedUnits.contains(type.defaultUnit), "\(type.displayName)")
        }
    }

    /// The badge grid is the only place a glyph can be chosen, so a type whose
    /// default isn't in it would show a badge the user can never get back to.
    func testEveryTypesDefaultGlyphIsOfferedByThePicker() {
        for type in TrackerType.allCases {
            XCTAssertTrue(TrackerPalette.glyphs.contains(type.defaultGlyph), "\(type.displayName)")
        }
    }

    func testOnlyWeightLossArrivesWithAReminderAlreadySet() {
        XCTAssertEqual(TrackerType.weightLoss.defaultReminderCadenceMinutes, 10_080, "weekly")
        for type in TrackerType.allCases where type != .weightLoss {
            XCTAssertNil(type.defaultReminderCadenceMinutes, "\(type.displayName)")
        }
    }


    // MARK: - Units

    func testUnitPrecisionAndPlacement() {
        XCTAssertEqual(TrackerUnit.sterling.precision, 2)
        XCTAssertEqual(TrackerUnit.sterling.placement, .prefix)
        XCTAssertEqual(TrackerUnit.miles.precision, 0)
        XCTAssertEqual(TrackerUnit.miles.placement, .suffix)
        XCTAssertEqual(TrackerUnit.kilometres.precision, 0)
        XCTAssertEqual(TrackerUnit.kilograms.precision, 1)
        XCTAssertEqual(TrackerUnit.pounds.precision, 0)
        XCTAssertEqual(TrackerUnit.number.precision, 0)
        XCTAssertEqual(TrackerUnit.number.placement, .bare)
        XCTAssertEqual(TrackerUnit.number.symbol, "", "a plain number has no symbol to show")
    }

    /// `Tracker.unit` stores the raw value, so a unit whose raw value isn't
    /// its symbol still round-trips.
    func testTrackerUnit_roundTripsThroughStorage() {
        for unit in TrackerUnit.allCases {
            let t = tracker()
            t.trackerUnit = unit
            XCTAssertEqual(t.trackerUnit, unit, unit.rawValue)
        }
    }

    /// Every unit that existed before the plain number stores its symbol, and
    /// must keep doing so — those strings are already synced to CloudKit.
    func testTrackerUnit_symbolUnitsStillStoreTheirSymbol() {
        for unit in TrackerUnit.allCases where unit != .number {
            XCTAssertEqual(unit.rawValue, unit.symbol, "stored representation must not change")
        }
    }

    func testUnitAmberFloors() {
        XCTAssertEqual(TrackerUnit.sterling.amberFloor, Decimal(string: "0.02"))
        XCTAssertEqual(TrackerUnit.dollar.amberFloor, Decimal(string: "0.02"))
        XCTAssertEqual(TrackerUnit.euro.amberFloor, Decimal(string: "0.02"))
        XCTAssertEqual(TrackerUnit.miles.amberFloor, 2)
        XCTAssertEqual(TrackerUnit.kilometres.amberFloor, 2)
        XCTAssertEqual(TrackerUnit.kilograms.amberFloor, 1)
        XCTAssertEqual(TrackerUnit.pounds.amberFloor, 2)
        XCTAssertEqual(TrackerUnit.number.amberFloor, 2)
    }

    func testRoundingHint_onlyOnZeroDecimalUnits() {
        XCTAssertEqual(TrackerUnit.miles.roundingHint, "Round up to the nearest whole mile.")
        XCTAssertEqual(TrackerUnit.kilometres.roundingHint, "Round up to the nearest whole km.")
        XCTAssertEqual(TrackerUnit.pounds.roundingHint, "Round up to the nearest whole pound.")
        XCTAssertEqual(TrackerUnit.number.roundingHint, "Round up to the nearest whole number.")
        XCTAssertNil(TrackerUnit.sterling.roundingHint)
        XCTAssertNil(TrackerUnit.kilograms.roundingHint)
    }

    /// A hint is the app stating the rounding it applies, so the two must
    /// agree: every unit that rounds says so, and no unit that doesn't.
    func testRoundingHintIsPresentExactlyWhenRoundingHappens() {
        for unit in TrackerUnit.allCases {
            XCTAssertEqual(unit.roundingHint != nil, !unit.allowsDecimals, unit.rawValue)
        }
    }

    func testRounded_zeroDecimalUnitsRoundUp() {
        XCTAssertEqual(TrackerUnit.miles.rounded(Decimal(string: "8400.1")!), 8401)
        XCTAssertEqual(TrackerUnit.pounds.rounded(Decimal(string: "184.2")!), 185)
        XCTAssertEqual(TrackerUnit.number.rounded(Decimal(string: "8400.5")!), 8401)
        XCTAssertEqual(TrackerUnit.miles.rounded(8400), 8400, "a whole value is left alone")
        XCTAssertEqual(TrackerUnit.number.rounded(8400), 8400, "a whole value is left alone")
    }

    func testRounded_decimalUnitsKeepTheirPrecision() {
        XCTAssertEqual(TrackerUnit.kilograms.rounded(Decimal(string: "84.64")!), Decimal(string: "84.6"))
        XCTAssertEqual(TrackerUnit.sterling.rounded(Decimal(string: "692.404")!), Decimal(string: "692.40"))
    }

    // MARK: - formattedValue

    func testFormattedValue_currencyUnit_prefixesSymbolWithNoSpace() {
        XCTAssertEqual(tracker().formattedValue(1234.56), "£1,234.56")
    }

    func testFormattedValue_suffixUnit_appendsUnitWithSpace() {
        XCTAssertEqual(tracker(type: .mileage).formattedValue(8400), "8,400 mi")
    }

    func testFormattedValue_unitlessType_showsTheBareNumber() {
        XCTAssertEqual(tracker(type: .numberRising).formattedValue(8400), "8,400", "no symbol, no stray space")
        XCTAssertEqual(tracker(type: .numberFalling).formattedValue(8400), "8,400")
        XCTAssertEqual(tracker(type: .numberRising).formattedValue(-50, signed: true), "-50")
        XCTAssertEqual(tracker(type: .numberRising).formattedValue(50, signed: true), "+50")
    }

    func testFormattedValue_spendingCredit_usesTheChosenCurrency() {
        XCTAssertEqual(tracker(type: .spendingCredit).formattedValue(Decimal(string: "128.40")!), "£128.40")
        XCTAssertEqual(tracker(type: .spendingCredit, unit: .euro).formattedValue(600), "€600")
    }

    func testFormattedValue_wholeNumber_showsNoDecimalPlaces() {
        XCTAssertEqual(tracker().formattedValue(684), "£684")
        XCTAssertEqual(tracker(type: .weightLoss).formattedValue(85), "85 kg", "1 dp unit still drops decimals when whole")
    }

    func testFormattedValue_fractional_showsTheUnitsOwnPrecision() {
        XCTAssertEqual(tracker().formattedValue(692.4), "£692.40")
        XCTAssertEqual(tracker(type: .weightLoss).formattedValue(Decimal(string: "84.6")!), "84.6 kg")
    }

    func testFormattedValue_zeroDecimalUnit_neverShowsDecimalPlaces() {
        XCTAssertEqual(tracker(type: .mileage).formattedValue(Decimal(string: "1234.56")!), "1,235 mi")
        XCTAssertEqual(tracker(type: .weightLoss, unit: .pounds).formattedValue(Decimal(string: "184.6")!), "185 lb")
    }

    func testFormattedValue_negative_alwaysShowsMinusSignRegardlessOfSignedFlag() {
        XCTAssertEqual(tracker().formattedValue(-50, signed: false), "-£50")
        XCTAssertEqual(tracker().formattedValue(-50, signed: true), "-£50")
    }

    func testFormattedValue_nonNegativeWithSignedTrue_prefixesPlus() {
        XCTAssertEqual(tracker().formattedValue(50, signed: true), "+£50")
        XCTAssertEqual(tracker().formattedValue(0, signed: true), "+£0")
    }

    func testFormattedValue_nonNegativeWithSignedFalse_showsNoSign() {
        XCTAssertEqual(tracker().formattedValue(50, signed: false), "£50")
    }

    // MARK: - Goal-type allowance derivation (§6)

    func testTotalAllowance_allowanceType_isTheMovementItself() {
        XCTAssertEqual(TrackerType.spendingMoney.totalAllowance(startingValue: 3_000, targetValue: 500), 500)
        XCTAssertEqual(TrackerType.mileage.totalAllowance(startingValue: 8_400, targetValue: 10_000), 10_000)
        // A credit period typically opens at zero, but a carried-over balance
        // mustn't eat into the limit the user actually typed.
        XCTAssertEqual(TrackerType.spendingCredit.totalAllowance(startingValue: 0, targetValue: 600), 600)
        XCTAssertEqual(TrackerType.spendingCredit.totalAllowance(startingValue: 120, targetValue: 600), 600)
    }

    func testTotalAllowance_goalType_isTheDistanceToTheGoal() {
        XCTAssertEqual(TrackerType.savingMoney.totalAllowance(startingValue: 200, targetValue: 5_000), 4_800)
        XCTAssertEqual(TrackerType.weightLoss.totalAllowance(startingValue: 95, targetValue: 85), 10)
        XCTAssertEqual(TrackerType.numberRising.totalAllowance(startingValue: 0, targetValue: 120), 120)
        XCTAssertEqual(TrackerType.numberFalling.totalAllowance(startingValue: 120, targetValue: 0), 120)
    }

    func testGoalType_editingStartingValue_keepsTheStatedGoalFixed() {
        // The goal the user typed stays put; the stored allowance is
        // recomputed around the new starting value.
        let goal: Decimal = 5_000
        var startingValue: Decimal = 200
        var allowance = TrackerType.savingMoney.totalAllowance(startingValue: startingValue, targetValue: goal)
        let t = tracker(type: .savingMoney, startingValue: startingValue, totalAllowance: allowance)
        XCTAssertEqual(t.projectedFinalValue, goal)

        startingValue = 1_000
        allowance = TrackerType.savingMoney.totalAllowance(startingValue: startingValue, targetValue: goal)
        t.startingValue = startingValue
        t.totalAllowance = allowance
        XCTAssertEqual(t.totalAllowance, 4_000)
        XCTAssertEqual(t.projectedFinalValue, goal, "the goal must not drift when the starting value is edited")
    }

    func testWholePeriodValue_isTheFigureTheUserActuallyEntered() {
        XCTAssertEqual(tracker(type: .spendingMoney, startingValue: 3_000, totalAllowance: 500).wholePeriodValue, 500)
        XCTAssertEqual(tracker(type: .mileage, startingValue: 8_400, totalAllowance: 10_000).wholePeriodValue, 10_000)
        XCTAssertEqual(tracker(type: .savingMoney, startingValue: 200, totalAllowance: 4_800).wholePeriodValue, 5_000)
        XCTAssertEqual(tracker(type: .weightLoss, startingValue: 95, totalAllowance: 10).wholePeriodValue, 85)
        XCTAssertEqual(tracker(type: .spendingCredit, startingValue: 0, totalAllowance: 600).wholePeriodValue, 600)
        XCTAssertEqual(tracker(type: .numberRising, startingValue: 0, totalAllowance: 120).wholePeriodValue, 120)
        XCTAssertEqual(tracker(type: .numberFalling, startingValue: 120, totalAllowance: 120).wholePeriodValue, 0)
    }

    /// Wording is the whole point of a tracker type, and a new type is easy to
    /// add with a phrase left blank — every surface reads from this table, so
    /// an empty string would show up as a missing label on the dashboard.
    func testEveryTypeHasCompleteWording() {
        for type in TrackerType.allCases {
            let words = type.terminology
            let phrases = [
                words.currentFigure, words.paceFigure, words.wholePeriodFigure, words.finalFigure,
                words.goodLabel, words.amberLabel, words.badLabel, words.remainingCaption,
                words.paceNoun, words.celebration,
                type.displayName, type.summary, type.startingValueLabel, type.targetValueLabel,
                type.startingValueHint, type.targetValueHint, type.logHint, type.validationMessage,
            ]
            for phrase in phrases {
                XCTAssertFalse(phrase.isEmpty, "\(type.rawValue) has a blank phrase")
            }
        }
    }

    // MARK: - Per-type validation (§4)

    func testValidation_allowanceTypes_requireAPositiveMovement() {
        XCTAssertTrue(TrackerType.spendingMoney.isValidPair(startingValue: 3_000, targetValue: 500))
        XCTAssertFalse(TrackerType.spendingMoney.isValidPair(startingValue: 3_000, targetValue: 0))
        XCTAssertTrue(TrackerType.mileage.isValidPair(startingValue: 8_400, targetValue: 10_000))
        XCTAssertFalse(TrackerType.mileage.isValidPair(startingValue: 8_400, targetValue: -1))
        XCTAssertTrue(TrackerType.spendingCredit.isValidPair(startingValue: 0, targetValue: 600))
        XCTAssertFalse(TrackerType.spendingCredit.isValidPair(startingValue: 0, targetValue: 0))
    }

    func testValidation_plainNumberTargetsMustSitOnTheRightSideOfTheStart() {
        XCTAssertTrue(TrackerType.numberRising.isValidPair(startingValue: 0, targetValue: 120))
        XCTAssertFalse(TrackerType.numberRising.isValidPair(startingValue: 120, targetValue: 0))
        XCTAssertFalse(TrackerType.numberRising.isValidPair(startingValue: 120, targetValue: 120))

        XCTAssertTrue(TrackerType.numberFalling.isValidPair(startingValue: 120, targetValue: 0))
        XCTAssertFalse(TrackerType.numberFalling.isValidPair(startingValue: 0, targetValue: 120))
        XCTAssertFalse(TrackerType.numberFalling.isValidPair(startingValue: 120, targetValue: 120))
    }

    func testValidation_savingGoalMustBeAboveTheStartingBalance() {
        XCTAssertTrue(TrackerType.savingMoney.isValidPair(startingValue: 200, targetValue: 5_000))
        XCTAssertFalse(TrackerType.savingMoney.isValidPair(startingValue: 5_000, targetValue: 200))
        XCTAssertFalse(TrackerType.savingMoney.isValidPair(startingValue: 200, targetValue: 200))
    }

    func testValidation_weightGoalMustBeBelowTheStartingWeight() {
        XCTAssertTrue(TrackerType.weightLoss.isValidPair(startingValue: 95, targetValue: 85))
        XCTAssertFalse(TrackerType.weightLoss.isValidPair(startingValue: 85, targetValue: 95))
        XCTAssertFalse(TrackerType.weightLoss.isValidPair(startingValue: 85, targetValue: 85))
    }

    // MARK: - projectedRemainder

    func testProjectedRemainder_increasingTracker_isAlwaysNil() {
        let t = tracker(type: .mileage, startingValue: 10_000, totalAllowance: 3_000)
        XCTAssertNil(t.projectedRemainder, "projected remainder is only meaningful for spend-down allowances")
    }

    func testProjectedRemainder_goalType_isAlwaysNil() {
        let t = tracker(type: .weightLoss, startingValue: 95, totalAllowance: 10)
        XCTAssertNil(t.projectedRemainder, "a goal type's allowance is the distance to the goal, not a leftover")
    }

    func testProjectedRemainder_startingValueExceedsBudget_isPositive() {
        XCTAssertEqual(tracker(startingValue: 500, totalAllowance: 400).projectedRemainder, 100)
    }

    func testProjectedRemainder_budgetExceedsStartingValue_isNegative() {
        XCTAssertEqual(tracker(startingValue: 400, totalAllowance: 500).projectedRemainder, -100)
    }

    func testProjectedRemainder_startingValueEqualsBudget_isNil() {
        XCTAssertNil(tracker(startingValue: 500, totalAllowance: 500).projectedRemainder,
                     "no remainder worth surfacing when the budget exactly matches the starting value")
    }

    // MARK: - remainingAtEndCaption

    func testRemainingAtEndCaption_startingValueExceedsBudget_saysWhatWillRemain() {
        XCTAssertEqual(tracker(startingValue: 500, totalAllowance: 400).remainingAtEndCaption, "£100 left at the end")
    }

    func testRemainingAtEndCaption_budgetExceedsStartingValue_saysByHowMuch() {
        XCTAssertEqual(tracker(startingValue: 400, totalAllowance: 500).remainingAtEndCaption,
                       "Budget is £100 more than the starting value")
    }

    func testRemainingAtEndCaption_startingValueEqualsBudget_isNil() {
        XCTAssertNil(tracker(startingValue: 500, totalAllowance: 500).remainingAtEndCaption)
    }

    // MARK: - Glyphs

    func testGlyphSymbol_defaultsToTheTypesOwnGlyph() {
        XCTAssertEqual(tracker(type: .spendingMoney).glyphSymbol, "creditcard.fill")
        XCTAssertEqual(tracker(type: .savingMoney).glyphSymbol, "banknote.fill")
        XCTAssertEqual(tracker(type: .mileage).glyphSymbol, "car.fill")
        XCTAssertEqual(tracker(type: .weightLoss).glyphSymbol, "scalemass.fill")
    }

    func testGlyphSymbol_chosenGlyphWins() {
        let t = tracker(type: .mileage)
        t.glyph = "bicycle"
        XCTAssertEqual(t.glyphSymbol, "bicycle")
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
