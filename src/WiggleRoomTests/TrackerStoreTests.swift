//
//  TrackerStoreTests.swift
//  WiggleRoomTests
//

import XCTest
import SwiftData
@testable import WiggleRoom

@MainActor
final class TrackerStoreTests: XCTestCase {

    func testAddTracker_persistsIt() throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let source = store.manualEntrySource
        let id = UUID()
        let tracker = Tracker(
            id: id,
            name: "Test",
            unit: "£",
            direction: .decreasing,
            connectedSource: source,
            sourceTargetId: id.uuidString,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )

        store.addTracker(tracker)

        let fetched = try context.fetch(FetchDescriptor<Tracker>())
        XCTAssertEqual(fetched.map(\.id), [id])
    }

    func testDeleteTracker_removesIt() throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id,
            name: "Test",
            unit: "£",
            direction: .decreasing,
            connectedSource: store.manualEntrySource,
            sourceTargetId: id.uuidString,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )
        store.addTracker(tracker)

        store.deleteTracker(tracker)

        let fetched = try context.fetch(FetchDescriptor<Tracker>())
        XCTAssertTrue(fetched.isEmpty)
    }

    func testLogReading_appendsToTrackerReadings() {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id,
            name: "Test",
            unit: "£",
            direction: .decreasing,
            connectedSource: store.manualEntrySource,
            sourceTargetId: id.uuidString,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )
        store.addTracker(tracker)

        store.logReading(value: 80, date: Date(), for: tracker)

        XCTAssertEqual(tracker.sortedReadings.count, 1)
        XCTAssertEqual(tracker.latestReading?.value, 80)
    }

    func testManualEntrySource_usesManualProviderIdAndIsStableAcrossInstances() {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)

        XCTAssertEqual(store.manualEntrySource.providerId, "manual")

        // A second TrackerStore over the same context (as happens across
        // app launches sharing one persistent store) must reuse the same
        // manual-entry source rather than creating a duplicate.
        let secondStore = TrackerStore(modelContext: context)
        XCTAssertEqual(secondStore.manualEntrySource.id, store.manualEntrySource.id)
    }

    func testManualProvider_listsNoTargetsForManualEntrySource() async throws {
        let container = makeInMemoryModelContainer()
        let store = TrackerStore(modelContext: container.mainContext)

        let targets = try await store.manualProvider.listAvailableTargets(for: store.manualEntrySource)

        XCTAssertTrue(targets.isEmpty)
    }
}
