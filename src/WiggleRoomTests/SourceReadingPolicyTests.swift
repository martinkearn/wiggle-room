//
//  SourceReadingPolicyTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

/// The rule `TrackerStore.refreshFromSource` applies to a reading a provider
/// hands back. Fictional weights throughout.
final class SourceReadingPolicyTests: XCTestCase {
    private let periodStart = Date(timeIntervalSince1970: 1_800_000_000)

    private func shouldLog(
        value: Decimal,
        at date: Date,
        latestValue: Decimal? = nil,
        latestDate: Date? = nil,
        startDate: Date? = nil,
        force: Bool = false
    ) -> Bool {
        SourceReadingPolicy.shouldLog(
            reading: SourceReading(value: value, date: date),
            roundedValue: value,
            latestValue: latestValue,
            latestDate: latestDate,
            trackerStartDate: startDate ?? periodStart,
            force: force
        )
    }

    func testFirstReading_isAlwaysLogged() {
        XCTAssertTrue(shouldLog(value: 84, at: periodStart.addingTimeInterval(3600)))
    }

    func testNewerDifferentValue_isLogged() {
        XCTAssertTrue(
            shouldLog(
                value: Decimal(string: "84.1")!,
                at: periodStart.addingTimeInterval(2 * 86_400),
                latestValue: Decimal(string: "84.6")!,
                latestDate: periodStart.addingTimeInterval(86_400)
            )
        )
    }

    func testUnchangedValue_isNotLogged() {
        // The user's whole point: only record a weight that has moved.
        XCTAssertFalse(
            shouldLog(
                value: Decimal(string: "84.6")!,
                at: periodStart.addingTimeInterval(2 * 86_400),
                latestValue: Decimal(string: "84.6")!,
                latestDate: periodStart.addingTimeInterval(86_400)
            )
        )
    }

    func testReadingOlderThanTheLatestOne_isNotLogged() {
        // A past-dated sample sitting behind a hand-typed correction. Without
        // this test it would be re-inserted on every poll, forever, since its
        // value differs from the latest reading's.
        XCTAssertFalse(
            shouldLog(
                value: Decimal(string: "84.6")!,
                at: periodStart.addingTimeInterval(86_400),
                latestValue: Decimal(string: "84.2")!,
                latestDate: periodStart.addingTimeInterval(2 * 86_400)
            )
        )
    }

    func testReadingWithTheSameTimestampAsTheLatestOne_isNotLogged() {
        XCTAssertFalse(
            shouldLog(
                value: Decimal(string: "84.1")!,
                at: periodStart.addingTimeInterval(86_400),
                latestValue: Decimal(string: "84.6")!,
                latestDate: periodStart.addingTimeInterval(86_400)
            )
        )
    }

    func testReadingFromBeforeTheTrackerStarted_isNotLogged() {
        XCTAssertFalse(shouldLog(value: 84, at: periodStart.addingTimeInterval(-86_400)))
    }

    func testForce_logsAnUnchangedValue() {
        // Used right after a tracker is created or connected, so its first
        // reading always lands.
        XCTAssertTrue(
            shouldLog(
                value: Decimal(string: "84.6")!,
                at: periodStart.addingTimeInterval(2 * 86_400),
                latestValue: Decimal(string: "84.6")!,
                latestDate: periodStart.addingTimeInterval(86_400),
                force: true
            )
        )
    }

    func testForce_doesNotLogAReadingFromBeforeTheTrackerStarted() {
        XCTAssertFalse(shouldLog(value: 84, at: periodStart.addingTimeInterval(-60), force: true))
    }

    func testRoundedValueIsWhatGetsCompared() {
        // 84.63999 kg rounds to the 84.6 already on record, so there is
        // nothing to log even though the raw values differ.
        XCTAssertFalse(
            SourceReadingPolicy.shouldLog(
                reading: SourceReading(value: Decimal(string: "84.63999")!, date: periodStart.addingTimeInterval(2 * 86_400)),
                roundedValue: Decimal(string: "84.6")!,
                latestValue: Decimal(string: "84.6")!,
                latestDate: periodStart.addingTimeInterval(86_400),
                trackerStartDate: periodStart,
                force: false
            )
        )
    }
}
