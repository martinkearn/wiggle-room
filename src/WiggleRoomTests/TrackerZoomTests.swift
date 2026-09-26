//
//  TrackerZoomTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class TrackerZoomTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, in calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A fictional tracker running Jan 1 00:00 -> Jan 31 00:00 (30 days).
    private func makeTracker(
        type: TrackerType = .spendingMoney,
        startingValue: Decimal = 600,
        totalAllowance: Decimal = 600,
        start: Date? = nil,
        end: Date? = nil
    ) -> Tracker {
        Tracker(
            name: "Fictional Tracker",
            type: type,
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
            startDate: start ?? date(2026, 1, 1),
            endDate: end ?? date(2026, 1, 31),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    private func window(for tracker: Tracker, now: Date, calendar: Calendar? = nil) -> DateInterval {
        TrackerZoom.window(periodStart: tracker.startDate, periodEnd: tracker.endDate, now: now, calendar: calendar ?? self.calendar)
    }

    // MARK: - Window

    func testWindowIsTwoDaysEitherSideOfToday() {
        let tracker = makeTracker()
        let window = window(for: tracker, now: date(2026, 1, 16, 12))
        XCTAssertEqual(window.start, date(2026, 1, 14))
        XCTAssertEqual(window.end, date(2026, 1, 19))
    }

    func testWindowSlidesForwardNearThePeriodStart() {
        let tracker = makeTracker()
        let window = window(for: tracker, now: date(2026, 1, 1, 10))
        XCTAssertEqual(window.start, date(2026, 1, 1))
        XCTAssertEqual(window.end, date(2026, 1, 6))
    }

    func testWindowSlidesBackNearThePeriodEnd() {
        let tracker = makeTracker()
        let window = window(for: tracker, now: date(2026, 1, 30, 12))
        XCTAssertEqual(window.start, date(2026, 1, 26))
        XCTAssertEqual(window.end, date(2026, 1, 31))
    }

    func testWindowRespectsExplicitStartTime() {
        let tracker = makeTracker(start: date(2026, 1, 1, 9), end: date(2026, 1, 31, 9))
        let window = window(for: tracker, now: date(2026, 1, 1, 12))
        XCTAssertEqual(window.start, date(2026, 1, 1, 9))
        XCTAssertEqual(window.end, date(2026, 1, 6, 9))
    }

    func testWindowFollowsLocalDaysAcrossADaylightSavingChange() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        // Clocks go forward on 29 Mar 2026, so that local day is 23 hours.
        let tracker = makeTracker(start: date(2026, 3, 1, in: london), end: date(2026, 4, 30, in: london))
        let window = window(for: tracker, now: date(2026, 3, 29, 12, in: london), calendar: london)
        XCTAssertEqual(window.start, date(2026, 3, 27, in: london))
        XCTAssertEqual(window.end, date(2026, 4, 1, in: london))
        XCTAssertEqual(window.duration, 119 * 3600)
    }

    // MARK: - Eligibility

    func testOnlyTrackersLongerThanFiveDaysCanZoom() {
        let now = date(2026, 1, 2)
        let exactlyFive = makeTracker(end: date(2026, 1, 6))
        let justOver = makeTracker(end: date(2026, 1, 6, 1))
        XCTAssertFalse(exactlyFive.canZoom(asOf: now))
        XCTAssertTrue(justOver.canZoom(asOf: now))
    }

    func testCompletedTrackerCannotZoom() {
        let tracker = makeTracker()
        XCTAssertFalse(tracker.canZoom(asOf: date(2026, 1, 31)))
    }

    func testZoomWindowIsNilUnlessZoomedAndEligible() {
        let tracker = makeTracker()
        let now = date(2026, 1, 16, 12)
        XCTAssertNil(tracker.zoomWindow(asOf: now, calendar: calendar))

        tracker.isZoomed = true
        XCTAssertNotNil(tracker.zoomWindow(asOf: now, calendar: calendar))

        // The stored flag stays, but it's ignored once the period no longer
        // qualifies.
        tracker.endDate = date(2026, 1, 5)
        XCTAssertNil(tracker.zoomWindow(asOf: date(2026, 1, 2), calendar: calendar))
        XCTAssertTrue(tracker.isZoomed)
    }

    func testNextZoomWindowChangeIsLocalMidnightOnlyWhenZoomed() {
        let tracker = makeTracker()
        let now = date(2026, 1, 16, 12)
        XCTAssertNil(tracker.nextZoomWindowChange(after: now, calendar: calendar))
        tracker.isZoomed = true
        XCTAssertEqual(tracker.nextZoomWindowChange(after: now, calendar: calendar), date(2026, 1, 17))
    }

    // MARK: - Ring fractions

    /// Midday on Jan 20: 19.5 of 30 days elapsed, and the window is
    /// Jan 18 -> Jan 23. On a £600 allowance, pace expects £340 spent at the
    /// window's start and £440 at its end.
    private var mockupNow: Date { date(2026, 1, 20, 12) }

    func testUnzoomedFractionsCoverTheWholePeriod() {
        let tracker = makeTracker()
        let fractions = tracker.ringFractions(actualValue: 180, asOf: mockupNow, window: nil)
        XCTAssertEqual(fractions.elapsed, 0.65, accuracy: 1e-9)
        XCTAssertEqual(fractions.consumed, 0.7, accuracy: 1e-9)
        XCTAssertNil(fractions.overflow)
    }

    func testZoomedFractionsMagnifyTheWindowSlice() {
        let tracker = makeTracker()
        let window = window(for: tracker, now: mockupNow)
        // £420 spent is 80% of the way from £340 to £440.
        let fractions = tracker.ringFractions(actualValue: 180, asOf: mockupNow, window: window)
        XCTAssertEqual(fractions.elapsed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(fractions.consumed, 0.8, accuracy: 1e-9)
        XCTAssertNil(fractions.overflow)
    }

    func testZoomedInnerRingPinsFullBeyondTheSlice() {
        let tracker = makeTracker()
        let window = window(for: tracker, now: mockupNow)
        let fractions = tracker.ringFractions(actualValue: 100, asOf: mockupNow, window: window)
        XCTAssertEqual(fractions.consumed, 1)
        XCTAssertEqual(fractions.overflow, .beyondFull)
    }

    func testZoomedInnerRingPinsEmptyBelowTheSlice() {
        let tracker = makeTracker()
        let window = window(for: tracker, now: mockupNow)
        let fractions = tracker.ringFractions(actualValue: 300, asOf: mockupNow, window: window)
        XCTAssertEqual(fractions.consumed, 0)
        XCTAssertEqual(fractions.overflow, .belowEmpty)
    }

    func testZoomedRingsAreLevelWhenOnPaceForEveryType() {
        let cases: [(TrackerType, Decimal, Decimal)] = [
            (.spendingMoney, 600, 600),
            (.savingMoney, 1_000, 3_000),
            (.mileage, 10_000, 3_000),
            (.weightLoss, 90, 6),
        ]
        for (type, startingValue, totalAllowance) in cases {
            let tracker = makeTracker(type: type, startingValue: startingValue, totalAllowance: totalAllowance)
            let window = window(for: tracker, now: mockupNow)
            let onPace = tracker.pace(actualValue: startingValue, asOf: mockupNow).targetValueToday
            let fractions = tracker.ringFractions(actualValue: onPace, asOf: mockupNow, window: window)
            XCTAssertEqual(fractions.consumed, fractions.elapsed, accuracy: 1e-9, "\(type)")
            XCTAssertNil(fractions.overflow, "\(type)")
        }
    }
}
