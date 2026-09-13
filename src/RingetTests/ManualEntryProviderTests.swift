//
//  ManualEntryProviderTests.swift
//  RingetTests
//

import XCTest
@testable import Ringet

final class ManualEntryProviderTests: XCTestCase {

    private func connection(name: String = "My mileage log") -> ConnectedSource {
        ConnectedSource(providerId: "manual", displayName: name)
    }

    func testProviderIdentity() async {
        let provider = ManualEntryProvider()
        let providerId = await provider.providerId
        let displayName = await provider.displayName
        let requiresConnection = await provider.requiresConnection

        XCTAssertEqual(providerId, "manual")
        XCTAssertEqual(displayName, "Manual entry")
        XCTAssertFalse(requiresConnection)
    }

    func testListAvailableTargets_freshConnection_returnsOnlyImplicitTarget() async throws {
        let provider = ManualEntryProvider()
        let source = connection()

        let targets = try await provider.listAvailableTargets(for: source)

        XCTAssertEqual(targets, [ManualEntryProvider.implicitTarget(for: source)])
    }

    func testFetchCurrentValue_beforeAnyLog_throws() async {
        let provider = ManualEntryProvider()
        let target = ManualEntryProvider.implicitTarget(for: connection())

        do {
            _ = try await provider.fetchCurrentValue(target: target)
            XCTFail("expected noReadingsLogged to be thrown")
        } catch ManualEntryProviderError.noReadingsLogged(let targetId) {
            XCTAssertEqual(targetId, target.id)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLogThenFetch_returnsLoggedValue() async throws {
        let provider = ManualEntryProvider()
        let target = ManualEntryProvider.implicitTarget(for: connection())

        try await provider.logManualReading(target: target, value: 12345, date: Date())

        let value = try await provider.fetchCurrentValue(target: target)
        XCTAssertEqual(value, 12345)
    }

    func testFetchCurrentValue_returnsMostRecentByDateNotInsertionOrder() async throws {
        let provider = ManualEntryProvider()
        let target = ManualEntryProvider.implicitTarget(for: connection())
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        // Log the more recent reading first, then an older backfilled one —
        // the current value should still resolve to the later date.
        try await provider.logManualReading(target: target, value: 200, date: later)
        try await provider.logManualReading(target: target, value: 100, date: earlier)

        let value = try await provider.fetchCurrentValue(target: target)
        XCTAssertEqual(value, 200)
    }

    func testAddTarget_registersNamedLog() async throws {
        let provider = ManualEntryProvider()
        let source = connection()

        let named = await provider.addTarget(displayName: "Car A mileage", to: source)
        let targets = try await provider.listAvailableTargets(for: source)

        XCTAssertTrue(targets.contains(named))
        XCTAssertEqual(targets.first, ManualEntryProvider.implicitTarget(for: source))
        XCTAssertEqual(targets.count, 2)
    }

    func testNamedTargets_haveIndependentReadingHistories() async throws {
        let provider = ManualEntryProvider()
        let source = connection()
        let carA = await provider.addTarget(displayName: "Car A mileage", to: source)
        let carB = await provider.addTarget(displayName: "Car B mileage", to: source)

        try await provider.logManualReading(target: carA, value: 10_000, date: Date())
        try await provider.logManualReading(target: carB, value: 50_000, date: Date())

        let valueA = try await provider.fetchCurrentValue(target: carA)
        let valueB = try await provider.fetchCurrentValue(target: carB)

        XCTAssertEqual(valueA, 10_000)
        XCTAssertEqual(valueB, 50_000)
    }

    func testDifferentConnections_haveIndependentImplicitTargets() async throws {
        let provider = ManualEntryProvider()
        let sourceA = connection(name: "Account A")
        let sourceB = connection(name: "Account B")

        try await provider.logManualReading(target: ManualEntryProvider.implicitTarget(for: sourceA), value: 111, date: Date())
        try await provider.logManualReading(target: ManualEntryProvider.implicitTarget(for: sourceB), value: 222, date: Date())

        let valueA = try await provider.fetchCurrentValue(target: ManualEntryProvider.implicitTarget(for: sourceA))
        let valueB = try await provider.fetchCurrentValue(target: ManualEntryProvider.implicitTarget(for: sourceB))

        XCTAssertEqual(valueA, 111)
        XCTAssertEqual(valueB, 222)
    }

    func testReadings_returnsFullHistoryOldestFirst() async throws {
        let provider = ManualEntryProvider()
        let target = ManualEntryProvider.implicitTarget(for: connection())
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        try await provider.logManualReading(target: target, value: 200, date: later)
        try await provider.logManualReading(target: target, value: 100, date: earlier)

        let readings = await provider.readings(for: target)

        XCTAssertEqual(readings, [
            ValueSnapshot(value: 100, date: earlier),
            ValueSnapshot(value: 200, date: later),
        ])
    }
}
