//
//  ChartZoomTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class ChartZoomTests: XCTestCase {

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

    private func window(_ zoom: ChartZoom, now: Date, calendar: Calendar? = nil) -> DateInterval? {
        ChartZoom.window(for: zoom, around: now, calendar: calendar ?? self.calendar)
    }

    // MARK: - Window

    func testWholePeriodHasNoWindow() {
        XCTAssertNil(window(.full, now: date(2026, 1, 16, 12)))
    }

    func testWeekWindowIsThreeDaysEitherSideOfToday() throws {
        let window = try XCTUnwrap(window(.week, now: date(2026, 1, 16, 12)))
        XCTAssertEqual(window.start, date(2026, 1, 13))
        XCTAssertEqual(window.end, date(2026, 1, 20))
        XCTAssertEqual(window.start.addingTimeInterval(window.duration / 2), date(2026, 1, 16, 12))
    }

    func testMonthWindowIsFifteenDaysEitherSideOfToday() throws {
        let window = try XCTUnwrap(window(.month, now: date(2026, 3, 10, 9)))
        XCTAssertEqual(window.start, date(2026, 2, 23))
        XCTAssertEqual(window.end, date(2026, 3, 26))
        XCTAssertEqual(window.start.addingTimeInterval(window.duration / 2), date(2026, 3, 10, 12))
    }

    func testWindowStaysCentredOnTodayNearThePeriodStart() throws {
        let tracker = makeTracker()
        tracker.chartZoom = .week
        let window = try XCTUnwrap(tracker.chartZoomWindow(asOf: date(2026, 1, 1, 10), calendar: calendar))
        XCTAssertEqual(window.start, date(2025, 12, 29))
        XCTAssertEqual(window.end, date(2026, 1, 5))
    }

    func testWindowFollowsLocalDaysAcrossADaylightSavingChange() throws {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        // Clocks go forward on 29 Mar 2026, so that local day is 23 hours.
        let window = try XCTUnwrap(window(.week, now: date(2026, 3, 29, 12, in: london), calendar: london))
        XCTAssertEqual(window.start, date(2026, 3, 26, in: london))
        XCTAssertEqual(window.end, date(2026, 4, 2, in: london))
        XCTAssertEqual(window.duration, 167 * 3600)
    }

    // MARK: - Eligibility

    func testWeekNeedsAPeriodLongerThanAWeek() {
        let now = date(2026, 1, 2)
        let exactlyAWeek = makeTracker(end: date(2026, 1, 8))
        let justOver = makeTracker(end: date(2026, 1, 8, 1))
        XCTAssertEqual(exactlyAWeek.availableChartZooms(asOf: now, calendar: calendar), [.full, .threeDays])
        XCTAssertEqual(justOver.availableChartZooms(asOf: now, calendar: calendar), [.full, .week, .threeDays])
    }

    func testThreeDaysNeedsAPeriodOfThreeDays() {
        let now = date(2026, 1, 2)
        let justUnder = makeTracker(end: date(2026, 1, 3, 23))
        let threeDays = makeTracker(end: date(2026, 1, 4))
        XCTAssertEqual(justUnder.availableChartZooms(asOf: now, calendar: calendar), [.full])
        XCTAssertEqual(threeDays.availableChartZooms(asOf: now, calendar: calendar), [.full, .threeDays])
    }

    func testThreeDaysWindowIsYesterdayTodayAndTomorrow() throws {
        let window = try XCTUnwrap(window(.threeDays, now: date(2026, 1, 16, 10)))
        XCTAssertEqual(window.start, date(2026, 1, 15))
        XCTAssertEqual(window.end, date(2026, 1, 18))
    }

    func testMonthNeedsAPeriodOfTwoMonths() {
        let now = date(2026, 1, 2)
        let justUnder = makeTracker(end: date(2026, 2, 28))
        let twoMonths = makeTracker(end: date(2026, 3, 1))
        XCTAssertEqual(justUnder.availableChartZooms(asOf: now, calendar: calendar), [.full, .week, .threeDays])
        XCTAssertEqual(twoMonths.availableChartZooms(asOf: now, calendar: calendar), [.full, .month, .week, .threeDays])
    }

    func testNoZoomBeforeThePeriodStartsOrOnceItHasEnded() {
        let tracker = makeTracker()
        XCTAssertEqual(tracker.availableChartZooms(asOf: date(2025, 12, 31), calendar: calendar), [.full])
        XCTAssertEqual(tracker.availableChartZooms(asOf: date(2026, 1, 31), calendar: calendar), [.full])
    }

    func testStoredLevelIsIgnoredWhileItDoesNotApply() {
        let tracker = makeTracker()
        let now = date(2026, 1, 16, 12)
        XCTAssertNil(tracker.chartZoomWindow(asOf: now, calendar: calendar))

        // Thirty days is too short for a month view.
        tracker.chartZoom = .month
        XCTAssertEqual(tracker.effectiveChartZoom(asOf: now, calendar: calendar), .full)
        XCTAssertNil(tracker.chartZoomWindow(asOf: now, calendar: calendar))

        tracker.chartZoom = .week
        XCTAssertNotNil(tracker.chartZoomWindow(asOf: now, calendar: calendar))

        // The stored level stays, but it's ignored once the period no
        // longer qualifies.
        tracker.endDate = date(2026, 1, 5)
        XCTAssertNil(tracker.chartZoomWindow(asOf: date(2026, 1, 2), calendar: calendar))
        XCTAssertEqual(tracker.chartZoom, .week)
    }

    func testUnknownStoredValueReadsAsWholePeriod() {
        let tracker = makeTracker()
        XCTAssertEqual(tracker.chartZoom, .full)
        tracker.chartZoomRawValue = "fortnight"
        XCTAssertEqual(tracker.chartZoom, .full)
    }

    func testNextChartZoomWindowChangeIsLocalMidnightOnlyWhenZoomed() {
        let tracker = makeTracker()
        let now = date(2026, 1, 16, 12)
        XCTAssertNil(tracker.nextChartZoomWindowChange(after: now, calendar: calendar))
        tracker.chartZoom = .week
        XCTAssertEqual(tracker.nextChartZoomWindowChange(after: now, calendar: calendar), date(2026, 1, 17))
    }

    // MARK: - Rings

    /// Midday on Jan 20: 19.5 of 30 days elapsed.
    private var mockupNow: Date { date(2026, 1, 20, 12) }

    func testRingFractionsCoverTheWholePeriod() {
        let tracker = makeTracker()
        let fractions = tracker.ringFractions(actualValue: 180, asOf: mockupNow)
        XCTAssertEqual(fractions.elapsed, 0.65, accuracy: 1e-9)
        XCTAssertEqual(fractions.consumed, 0.7, accuracy: 1e-9)
    }

    func testChartZoomLeavesTheRingsWholePeriod() {
        let tracker = makeTracker()
        let unzoomed = tracker.ringFractions(asOf: mockupNow)
        tracker.chartZoom = .week
        XCTAssertEqual(tracker.ringFractions(asOf: mockupNow), unzoomed)
        XCTAssertEqual(unzoomed.elapsed, 0.65, accuracy: 1e-9)
    }
}
