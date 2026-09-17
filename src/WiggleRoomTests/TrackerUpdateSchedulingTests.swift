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
}
