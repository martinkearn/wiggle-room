//
//  TrackerStoreTests.swift
//  RingetTests
//

import XCTest
@testable import Ringet

final class TrackerStoreTests: XCTestCase {

    func testAddTracker_appendsToTrackers() {
        let store = TrackerStore()
        let source = store.manualEntrySource
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

    func testManualEntrySource_usesManualProviderIdAndIsStable() {
        let store = TrackerStore()

        let source = store.manualEntrySource

        XCTAssertEqual(source.providerId, "manual")
        XCTAssertEqual(store.manualEntrySource, source, "should return the same source on repeated access")
    }

    func testAddedSources_startsEmpty() {
        let store = TrackerStore()

        XCTAssertTrue(store.addedSources.isEmpty, "no external provider is implemented yet, so nothing should be pre-populated")
    }

    func testSourceWithId_resolvesManualEntrySource() {
        let store = TrackerStore()

        XCTAssertEqual(store.source(withId: store.manualEntrySource.id), store.manualEntrySource)
    }

    func testSourceWithId_returnsNilForUnknownId() {
        let store = TrackerStore()

        XCTAssertNil(store.source(withId: UUID()))
    }

    func testManualProvider_listsImplicitTargetForManualEntrySource() async throws {
        let store = TrackerStore()
        let source = store.manualEntrySource

        let targets = try await store.manualProvider.listAvailableTargets(for: source)

        XCTAssertEqual(targets, [ManualEntryProvider.implicitTarget(for: source)])
    }
}
