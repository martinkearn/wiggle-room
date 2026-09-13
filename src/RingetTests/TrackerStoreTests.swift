//
//  TrackerStoreTests.swift
//  RingetTests
//

import XCTest
@testable import Ringet

final class TrackerStoreTests: XCTestCase {

    func testAddTracker_appendsToTrackers() {
        let store = TrackerStore()
        let source = store.defaultManualSource
        let tracker = Tracker(
            name: "Test",
            unit: "£",
            direction: .decreasing,
            connectedSourceId: source.id,
            sourceTargetId: ManualEntryProvider.implicitTarget(for: source).id,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )

        store.addTracker(tracker)

        XCTAssertEqual(store.trackers, [tracker])
    }

    func testDefaultManualSource_usesManualProviderIdAndIsStable() {
        let store = TrackerStore()

        let source = store.defaultManualSource

        XCTAssertEqual(source.providerId, "manual")
        XCTAssertEqual(store.defaultManualSource, source, "should return the same source on repeated access")
    }

    func testConnectedSources_seededWithDefaultManualSourceAtInit() {
        let store = TrackerStore()

        XCTAssertEqual(store.connectedSources, [store.defaultManualSource])
    }

    func testManualProvider_listsImplicitTargetForDefaultSource() async throws {
        let store = TrackerStore()
        let source = store.defaultManualSource

        let targets = try await store.manualProvider.listAvailableTargets(for: source)

        XCTAssertEqual(targets, [ManualEntryProvider.implicitTarget(for: source)])
    }
}
