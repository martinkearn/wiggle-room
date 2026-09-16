//
//  ZoomLevelTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class ZoomLevelTests: XCTestCase {

    // `Calendar.current`, not a fixed UTC calendar — `Tracker.subPeriod`
    // calendar-aligns to the device's own local calendar (the whole point
    // of "this month" meaning something intuitive to the user, §4.5), so
    // test dates/expectations are built the same way rather than assuming
    // UTC, which would make these tests fail depending on the host's own
    // time zone and DST rules.
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // A 2-year lease-style tracker: Jan 1 2026 -> Jan 1 2028, 24,000 miles.
    private func longRunningTracker(startingValue: Decimal = 0, totalAllowance: Decimal = 24000) -> Tracker {
        Tracker(
            name: "Car lease mileage",
            unit: "mi",
            direction: .increasing,
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
            startDate: date(2026, 1, 1),
            endDate: date(2028, 1, 1),
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
    }

    // A short, week-long tracker.
    private func weekTracker() -> Tracker {
        Tracker(
            name: "Weekly spending money",
            unit: "£",
            direction: .decreasing,
            connectedSource: ConnectedSource(providerId: "manual", displayName: "Test source"),
            startDate: date(2026, 3, 2), // a Monday
            endDate: date(2026, 3, 9),
            startingValue: 100,
            totalAllowance: 100
        )
    }

    // MARK: - availableZoomLevels (§4.5 — depends on the tracker's own length)

    func testAvailableZoomLevels_longRunningTracker_offersEveryLevel() {
        let tracker = longRunningTracker()
        XCTAssertEqual(tracker.availableZoomLevels, [.overall, .thisYear, .thisMonth, .thisWeek])
    }

    func testAvailableZoomLevels_weekLongTracker_offersOnlyOverall() {
        let tracker = weekTracker()
        XCTAssertEqual(tracker.availableZoomLevels, [.overall], "a week-long tracker has no meaningfully shorter zoom level to offer")
    }

    // MARK: - subPeriod(for:asOf:)

    func testSubPeriod_overall_isNil() {
        let tracker = longRunningTracker()
        XCTAssertNil(tracker.subPeriod(for: .overall, asOf: date(2026, 6, 15)))
    }

    func testSubPeriod_thisMonth_isCalendarAligned() {
        let tracker = longRunningTracker()
        let subPeriod = tracker.subPeriod(for: .thisMonth, asOf: date(2026, 3, 15))
        XCTAssertEqual(subPeriod?.start, date(2026, 3, 1))
        XCTAssertEqual(subPeriod?.end, date(2026, 4, 1))
    }

    func testSubPeriod_thisMonth_clampedToTrackerStart() {
        // asOf lands in the tracker's very first month — the sub-period
        // shouldn't extend before the tracker's own startDate even though
        // the calendar month does.
        let tracker = longRunningTracker()
        let subPeriod = tracker.subPeriod(for: .thisMonth, asOf: date(2026, 1, 10))
        XCTAssertEqual(subPeriod?.start, tracker.startDate)
        XCTAssertEqual(subPeriod?.end, date(2026, 2, 1))
    }

    func testSubPeriod_thisYear_clampedToTrackerEnd() {
        // The tracker ends mid-way through what would otherwise be a full
        // calendar year (2028) — the sub-period should stop at the
        // tracker's own endDate.
        let tracker = longRunningTracker()
        let subPeriod = tracker.subPeriod(for: .thisYear, asOf: date(2028, 1, 1).addingTimeInterval(-3600))
        XCTAssertEqual(subPeriod?.end, tracker.endDate)
    }

    // MARK: - actualValue(atOrBefore:)

    func testActualValueAtOrBefore_beforeAnyReading_returnsStartingValue() {
        let tracker = longRunningTracker(startingValue: 1000)
        XCTAssertEqual(tracker.actualValue(atOrBefore: date(2026, 1, 1)), 1000)
        XCTAssertEqual(tracker.actualValue(atOrBefore: date(2026, 6, 1)), 1000)
    }

    func testActualValueAtOrBefore_usesLatestReadingAtOrBeforeDate() {
        let tracker = longRunningTracker(startingValue: 0)
        let earlyReading = ValueSnapshot(value: 5000, date: date(2026, 2, 1))
        earlyReading.tracker = tracker
        let laterReading = ValueSnapshot(value: 8000, date: date(2026, 4, 1))
        laterReading.tracker = tracker
        tracker.readings = [earlyReading, laterReading]

        XCTAssertEqual(tracker.actualValue(atOrBefore: date(2026, 3, 1)), 5000, "should use the latest reading at or before the date, not the very latest overall")
        XCTAssertEqual(tracker.actualValue(atOrBefore: date(2026, 5, 1)), 8000)
    }

    // MARK: - pace(actualValue:asOf:zoomLevel:) — sub-period scoping (§4.5)

    func testZoomedPace_thisMonth_scalesAllowanceToSubPeriodDays() {
        // The tracker itself spans 2 full years (Jan 1 2026 -> Jan 1 2028),
        // not 1 — subAllowance = totalAllowance * daysInSubPeriod /
        // totalPeriodDays, where totalPeriodDays is the *tracker's own*
        // period, not a calendar year.
        let tracker = longRunningTracker(startingValue: 0, totalAllowance: 24000)
        let asOf = date(2026, 3, 15)
        let subPeriod = tracker.subPeriod(for: .thisMonth, asOf: asOf)!
        let pace = tracker.pace(actualValue: 3000, asOf: asOf, zoomLevel: .thisMonth)

        let totalPeriodDays = tracker.endDate.timeIntervalSince(tracker.startDate) / 86400
        let subPeriodDays = subPeriod.end.timeIntervalSince(subPeriod.start) / 86400
        let expectedAllowance = Decimal(24000) * Decimal(subPeriodDays / totalPeriodDays)
        XCTAssertEqual((pace.totalAllowance as NSDecimalNumber).doubleValue, (expectedAllowance as NSDecimalNumber).doubleValue, accuracy: 0.01)
    }

    func testZoomedPace_thisMonth_usesLocalStartingValueFromHistory() {
        let tracker = longRunningTracker(startingValue: 0, totalAllowance: 24000)
        let readingAtMonthStart = ValueSnapshot(value: 2800, date: date(2026, 3, 1))
        readingAtMonthStart.tracker = tracker
        tracker.readings = [readingAtMonthStart]

        let pace = tracker.pace(actualValue: 3100, asOf: date(2026, 3, 15), zoomLevel: .thisMonth)

        // consumedSoFar (increasing) = actualValue - localStartingValue = 3100 - 2800 = 300,
        // not actualValue - tracker.startingValue (3100 - 0).
        XCTAssertEqual(pace.consumedSoFar, 300)
    }

    func testZoomedPace_periodBoundsMatchSubPeriod() {
        let tracker = longRunningTracker()
        let asOf = date(2026, 3, 15)
        let subPeriod = tracker.subPeriod(for: .thisMonth, asOf: asOf)!
        let pace = tracker.pace(actualValue: 0, asOf: asOf, zoomLevel: .thisMonth)
        // Real elapsed wall-clock hours between the sub-period's own bounds
        // — not a hardcoded "31 days = 744 hours", since a DST transition
        // inside the sub-period would make that assumption wrong (same
        // DST-safety rule as the tracker's own full-period math, §4.3).
        XCTAssertEqual(pace.periodHours, subPeriod.end.timeIntervalSince(subPeriod.start) / 3600)
    }

    func testZoomedPace_fallsBackToOverall_whenLevelIsOverall() {
        let tracker = longRunningTracker(startingValue: 0, totalAllowance: 24000)
        let asOf = date(2026, 3, 15)
        let overall = tracker.pace(actualValue: 3000, asOf: asOf)
        let zoomedOverall = tracker.pace(actualValue: 3000, asOf: asOf, zoomLevel: .overall)
        XCTAssertEqual(overall, zoomedOverall)
    }

    func testZoomedPace_notOfferedLevel_stillFallsBackGracefully() {
        // A week-long tracker has no meaningfully-shorter sub-period, but
        // asking for `.thisYear` anyway shouldn't crash — it should just
        // read as the overall period since the calendar year fully contains
        // (and thus clamps to) the whole tracker.
        let tracker = weekTracker()
        let pace = tracker.pace(actualValue: 50, asOf: date(2026, 3, 5), zoomLevel: .thisYear)
        XCTAssertEqual(pace.periodHours, tracker.endDate.timeIntervalSince(tracker.startDate) / 3600)
    }
}
