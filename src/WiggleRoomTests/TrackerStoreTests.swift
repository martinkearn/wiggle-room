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
            type: .spendingMoney,
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
            type: .spendingMoney,
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

    func testResetAllData_removesUserDataAndKeepsManualSource() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let externalSource = ConnectedSource(providerId: "starling", displayName: "My Starling")
        context.insert(externalSource)
        let tracker = Tracker(
            name: "Test",
            type: .spendingMoney,
            connectedSource: externalSource,
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )
        store.addTracker(tracker)
        store.logReading(value: 80, date: .now, for: tracker)

        let succeeded = await store.resetAllData()

        XCTAssertTrue(succeeded)
        XCTAssertFalse(store.isResettingData)
        XCTAssertNil(store.resetErrorDescription)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Tracker>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ValueSnapshot>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StarlingRequestLogEntry>()).isEmpty)
        let sources = try context.fetch(FetchDescriptor<ConnectedSource>())
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.providerId, "manual")
    }

    func testLogReading_appendsToTrackerReadings() {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id,
            name: "Test",
            type: .spendingMoney,
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

    func testConnectedTracker_manualReadingCanBeAddedEditedAndDeleted() throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let source = ConnectedSource(providerId: "starling", displayName: "Fictional Bank")
        context.insert(source)
        let store = TrackerStore(modelContext: context)
        let tracker = Tracker(
            name: "Test",
            type: .spendingMoney,
            connectedSource: source,
            sourceTargetId: "synthetic-account",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )
        store.addTracker(tracker)

        store.logReading(value: 80, date: Date(), for: tracker)
        let reading = try XCTUnwrap(tracker.latestReading)
        reading.value = 75
        store.saveChanges()

        XCTAssertEqual(tracker.latestReading?.value, 75)

        store.deleteReading(reading)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ValueSnapshot>()).isEmpty)
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

    func testProvider_forManualTracker_returnsManualProvider() {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id, name: "Test", type: .spendingMoney,
            connectedSource: store.manualEntrySource, sourceTargetId: id.uuidString,
            startDate: Date(), endDate: Date().addingTimeInterval(3600),
            startingValue: 100, totalAllowance: 100
        )

        let provider = store.provider(for: tracker)

        XCTAssertTrue(provider === store.manualProvider)
    }

    func testProvider_forStarlingTracker_returnsStarlingProvider() {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let starlingSource = ConnectedSource(providerId: "starling", displayName: "My Starling")
        context.insert(starlingSource)
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id, name: "Test", type: .spendingMoney,
            connectedSource: starlingSource, sourceTargetId: "abc-123",
            startDate: Date(), endDate: Date().addingTimeInterval(3600),
            startingValue: 100, totalAllowance: 100
        )

        let provider = store.provider(for: tracker)

        XCTAssertTrue(provider is StarlingProvider)
    }

    func testProvider_forUnknownProviderId_returnsNil() {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let unknownSource = ConnectedSource(providerId: "tesla", displayName: "My Tesla")
        context.insert(unknownSource)
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id, name: "Test", type: .mileage,
            connectedSource: unknownSource, sourceTargetId: "vehicle-1",
            startDate: Date(), endDate: Date().addingTimeInterval(3600),
            startingValue: 100, totalAllowance: 100
        )

        XCTAssertNil(store.provider(for: tracker))
    }

    func testRefreshFromSource_manualTracker_noOps() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id, name: "Test", type: .spendingMoney,
            connectedSource: store.manualEntrySource, sourceTargetId: id.uuidString,
            startDate: Date(), endDate: Date().addingTimeInterval(3600),
            startingValue: 100, totalAllowance: 100
        )
        store.addTracker(tracker)

        try await store.refreshFromSource(tracker)

        XCTAssertTrue(tracker.sortedReadings.isEmpty, "a manual tracker has nothing to fetch")
    }

    func testRefreshFromSource_starlingTrackerWithNoStoredToken_throwsNotConnected() async {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        // No credentialToken — mirrors a source that was never actually
        // connected.
        let starlingSource = ConnectedSource(providerId: "starling", displayName: "My Starling")
        context.insert(starlingSource)
        let store = TrackerStore(modelContext: context)
        let id = UUID()
        let tracker = Tracker(
            id: id, name: "Test", type: .spendingMoney,
            connectedSource: starlingSource, sourceTargetId: "abc-123",
            startDate: Date(), endDate: Date().addingTimeInterval(3600),
            startingValue: 100, totalAllowance: 100
        )
        store.addTracker(tracker)

        do {
            try await store.refreshFromSource(tracker)
            XCTFail("expected notConnected")
        } catch StarlingProviderError.notConnected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
