//
//  TrackerUpdateSchedulingTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

final class TrackerUpdateSchedulingTests: XCTestCase {
    func testNextUpdateDate_farFromEnd_stepsForwardByInterval() {
        let now = Date()
        let end = now.addingTimeInterval(3600) // an hour away
        let next = TrackerUpdateScheduling.nextUpdateDate(after: now, until: end, interval: 60)
        XCTAssertEqual(next.timeIntervalSince(now), 60, accuracy: 0.01)
    }

    func testNextUpdateDate_lastTickAlwaysLandsExactlyOnEndDate() {
        let now = Date()
        // 90 seconds left with a 60s interval: two ticks remain (60s, then
        // 30s) — the final one must land exactly on `end`, not overshoot it.
        let end = now.addingTimeInterval(90)
        let firstTick = TrackerUpdateScheduling.nextUpdateDate(after: now, until: end, interval: 60)
        let secondTick = TrackerUpdateScheduling.nextUpdateDate(after: firstTick, until: end, interval: 60)
        XCTAssertEqual(secondTick, end)
    }

    func testNextUpdateDate_afterEndDate_returnsEndDate() {
        let now = Date()
        let end = now.addingTimeInterval(-10)
        XCTAssertEqual(TrackerUpdateScheduling.nextUpdateDate(after: now, until: end), end)
    }

    func testNextWidgetReloadDate_farFromEnd_usesFarInterval() {
        let now = Date()
        let end = now.addingTimeInterval(2 * 3600)
        let next = TrackerUpdateScheduling.nextWidgetReloadDate(after: now, until: end, farInterval: 900, nearInterval: 60)
        XCTAssertEqual(next.timeIntervalSince(now), 900, accuracy: 0.01)
    }

    func testNextWidgetReloadDate_withinFinalHour_usesNearInterval() {
        let now = Date()
        let end = now.addingTimeInterval(1800) // 30 minutes left
        let next = TrackerUpdateScheduling.nextWidgetReloadDate(after: now, until: end, farInterval: 900, nearInterval: 60)
        XCTAssertEqual(next.timeIntervalSince(now), 60, accuracy: 0.01)
    }

    // MARK: - Poll policies

    /// A fixed timezone and a fixed day, so "20:00 local" means one exact
    /// instant in every test rather than whatever the machine's clock says.
    private var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func london(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        londonCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func timeUntilDue(
        policy: TrackerUpdateScheduling.SourcePollPolicy,
        lastAttempt: Date?,
        now: Date,
        readings: [ValueSnapshot] = []
    ) -> TimeInterval {
        TrackerUpdateScheduling.timeUntilDue(
            policy: policy,
            lastAttempt: lastAttempt,
            readings: readings,
            asOf: now,
            calendar: londonCalendar
        )
    }

    func testPollPolicy_healthKitIsDailyInTheEvening_everythingElseIsTransactional() {
        XCTAssertEqual(TrackerUpdateScheduling.pollPolicy(forProviderId: "healthkit"), .dailyEvening(hour: 20))
        XCTAssertEqual(TrackerUpdateScheduling.pollPolicy(forProviderId: "starling"), .transactional)
        XCTAssertEqual(TrackerUpdateScheduling.pollPolicy(forProviderId: "manual"), .transactional)
        XCTAssertEqual(TrackerUpdateScheduling.pollPolicy(forProviderId: nil), .transactional)
    }

    func testDailyEvening_neverPolled_isDueImmediately() {
        let due = timeUntilDue(policy: .dailyEvening(hour: 20), lastAttempt: nil, now: london(2026, 7, 14, 9))
        XCTAssertEqual(due, 0)
    }

    func testDailyEvening_beforeTheSlot_waitsForIt() {
        // Polled last night; it's now mid-morning. Nothing to do until 20:00.
        let due = timeUntilDue(
            policy: .dailyEvening(hour: 20),
            lastAttempt: london(2026, 7, 13, 20, 5),
            now: london(2026, 7, 14, 9)
        )
        XCTAssertEqual(due, 11 * 3600, accuracy: 1)
    }

    func testDailyEvening_atTheSlot_isDue() {
        let due = timeUntilDue(
            policy: .dailyEvening(hour: 20),
            lastAttempt: london(2026, 7, 14, 9),
            now: london(2026, 7, 14, 20)
        )
        XCTAssertEqual(due, 0)
    }

    func testDailyEvening_alreadyPolledThisEvening_waitsForTomorrow() {
        let due = timeUntilDue(
            policy: .dailyEvening(hour: 20),
            lastAttempt: london(2026, 7, 14, 20, 30),
            now: london(2026, 7, 14, 21)
        )
        XCTAssertEqual(due, 23 * 3600, accuracy: 1)
    }

    func testDailyEvening_missedYesterdaysSlot_catchesUpImmediately() {
        // A device that was off for days shouldn't wait for the next evening
        // to come round before reading a weight at all.
        let due = timeUntilDue(
            policy: .dailyEvening(hour: 20),
            lastAttempt: london(2026, 7, 11, 20, 5),
            now: london(2026, 7, 14, 9)
        )
        XCTAssertEqual(due, 0)
    }

    func testDailyEvening_acrossTheEndOfBritishSummerTime_staysAt20Local() {
        // Clocks go back on 25 October 2026. The slot follows the clock, so
        // the gap between two 20:00 slots is 25 hours, not 24.
        let due = timeUntilDue(
            policy: .dailyEvening(hour: 20),
            lastAttempt: london(2026, 10, 24, 20, 5),
            now: london(2026, 10, 24, 21)
        )
        XCTAssertEqual(due, 24 * 3600, accuracy: 1)
        let slot = TrackerUpdateScheduling.mostRecentDailySlot(
            hour: 20,
            asOf: london(2026, 10, 25, 22),
            calendar: londonCalendar
        )
        XCTAssertEqual(slot, london(2026, 10, 25, 20))
    }

    func testDailyEvening_ignoresBursts() {
        // Two weigh-ins half an hour apart are no reason to poll every five
        // minutes — unlike a Starling tracker, where that's exactly the point.
        let now = london(2026, 7, 14, 9)
        let readings = [
            ValueSnapshot(value: 84, date: now.addingTimeInterval(-600)),
            ValueSnapshot(value: 83, date: now.addingTimeInterval(-300))
        ]
        let health = timeUntilDue(
            policy: .dailyEvening(hour: 20),
            lastAttempt: london(2026, 7, 13, 20, 5),
            now: now,
            readings: readings
        )
        XCTAssertEqual(health, 11 * 3600, accuracy: 1)

        let starling = timeUntilDue(
            policy: .transactional,
            lastAttempt: now.addingTimeInterval(-60),
            now: now,
            readings: readings
        )
        XCTAssertEqual(starling, TrackerUpdateScheduling.RefreshBand.peak.interval - 60, accuracy: 1)
    }

    func testTransactional_usesTheTimeOfDayBandSinceTheLastAttempt() {
        // 09:00 is peak: 5 minutes between polls.
        let now = london(2026, 7, 14, 9)
        let due = timeUntilDue(policy: .transactional, lastAttempt: now.addingTimeInterval(-120), now: now)
        XCTAssertEqual(due, TrackerUpdateScheduling.RefreshBand.peak.interval - 120, accuracy: 1)
    }

    func testTransactional_neverPolled_isDueImmediately() {
        let due = timeUntilDue(policy: .transactional, lastAttempt: nil, now: london(2026, 7, 14, 9))
        XCTAssertEqual(due, 0)
    }
}
