//
//  TrackerCloneTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class TrackerCloneTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let locale = Locale(identifier: "en_GB")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func next(_ start: Date, _ end: Date) -> (start: Date, end: Date) {
        TrackerClone.nextPeriod(startDate: start, endDate: end, calendar: calendar)
    }

    func testMonthEndingOnTheNextFirstRollsToTheNextMonth() {
        let period = next(date(2026, 10, 1), date(2026, 11, 1))
        XCTAssertEqual(period.start, date(2026, 11, 1))
        XCTAssertEqual(period.end, date(2026, 12, 1))
    }

    func testMonthEndingOnItsLastDayRollsToTheNextMonthsLastDay() {
        let period = next(date(2026, 1, 1), date(2026, 1, 31))
        XCTAssertEqual(period.start, date(2026, 2, 1))
        XCTAssertEqual(period.end, date(2026, 2, 28))
    }

    func testMonthEndingOnItsLastDayKeepsTheTimeOfDay() {
        let period = next(date(2026, 4, 1), date(2026, 4, 30, 17))
        XCTAssertEqual(period.start, date(2026, 5, 1))
        XCTAssertEqual(period.end, date(2026, 5, 31, 17))
    }

    func testMonthRollsAcrossAYearBoundary() {
        let period = next(date(2026, 12, 1), date(2027, 1, 1))
        XCTAssertEqual(period.start, date(2027, 1, 1))
        XCTAssertEqual(period.end, date(2027, 2, 1))
    }

    func testOtherPeriodsStartTheDayAfterAndKeepTheirLength() {
        // A fortnight: 3 Mar to 17 Mar is 14 days.
        let period = next(date(2026, 3, 3), date(2026, 3, 17))
        XCTAssertEqual(period.start, date(2026, 3, 18))
        XCTAssertEqual(period.end, date(2026, 4, 1))
    }

    func testAMonthNotStartingOnTheFirstIsNotACalendarMonth() {
        let period = next(date(2026, 10, 15), date(2026, 11, 15))
        XCTAssertEqual(period.start, date(2026, 11, 16))
        // 15 Oct to 15 Nov is 31 days, so the copy runs 31 days from 16 Nov.
        XCTAssertEqual(period.end, date(2026, 12, 17))
    }

    func testSuffixNamesTheNewPeriodsMonth() {
        let name = TrackerClone.name(
            from: "Groceries",
            originalStart: date(2026, 10, 1),
            newStart: date(2026, 11, 1),
            calendar: calendar,
            locale: locale
        )
        XCTAssertEqual(name, "Groceries \u{2013} Nov 2026")
    }

    func testAnEarlierSuffixIsReplacedNotStacked() {
        let name = TrackerClone.name(
            from: "Groceries \u{2013} Oct 2026",
            originalStart: date(2026, 10, 1),
            newStart: date(2026, 11, 1),
            calendar: calendar,
            locale: locale
        )
        XCTAssertEqual(name, "Groceries \u{2013} Nov 2026")
    }
}
