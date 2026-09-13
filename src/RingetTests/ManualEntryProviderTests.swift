//
//  ManualEntryProviderTests.swift
//  RingetTests
//

import XCTest
import SwiftData
@testable import Ringet

@MainActor
final class ManualEntryProviderTests: XCTestCase {

    private func makeManualSource(in context: ModelContext) -> ConnectedSource {
        let source = ConnectedSource(providerId: "manual", displayName: "Manual Entry")
        context.insert(source)
        return source
    }

    /// Mirrors how `AddTrackerView.save()` creates a manual tracker: its own
    /// id doubles as its `sourceTargetId`.
    private func makeTracker(in context: ModelContext, name: String = "Test tracker") -> Tracker {
        let source = makeManualSource(in: context)
        let id = UUID()
        let tracker = Tracker(
            id: id,
            name: name,
            unit: "£",
            direction: .decreasing,
            connectedSource: source,
            sourceTargetId: id.uuidString,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )
        context.insert(tracker)
        return tracker
    }

    func testProviderIdentity() {
        let container = makeInMemoryModelContainer()
        let provider = ManualEntryProvider(modelContext: container.mainContext)

        XCTAssertEqual(provider.providerId, "manual")
        XCTAssertEqual(provider.displayName, "Manual entry")
        XCTAssertFalse(provider.requiresConnection)
    }

    func testListAvailableTargets_isAlwaysEmpty() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let provider = ManualEntryProvider(modelContext: context)
        let source = makeManualSource(in: context)

        let targets = try await provider.listAvailableTargets(for: source)

        XCTAssertTrue(targets.isEmpty, "manual entry has no shared target list — each tracker owns its own log")
    }

    func testFetchCurrentValue_unknownTrackerId_throwsTrackerNotFound() async {
        let container = makeInMemoryModelContainer()
        let provider = ManualEntryProvider(modelContext: container.mainContext)
        let target = SourceTarget(id: UUID().uuidString, displayName: "Missing")

        do {
            _ = try await provider.fetchCurrentValue(target: target)
            XCTFail("expected trackerNotFound to be thrown")
        } catch ManualEntryProviderError.trackerNotFound(let targetId) {
            XCTAssertEqual(targetId, target.id)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchCurrentValue_beforeAnyLog_throwsNoReadingsLogged() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let provider = ManualEntryProvider(modelContext: context)
        let tracker = makeTracker(in: context)
        let target = SourceTarget(id: tracker.sourceTargetId!, displayName: tracker.name)

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
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let provider = ManualEntryProvider(modelContext: context)
        let tracker = makeTracker(in: context)
        let target = SourceTarget(id: tracker.sourceTargetId!, displayName: tracker.name)

        try await provider.logManualReading(target: target, value: 12345, date: Date())

        let value = try await provider.fetchCurrentValue(target: target)
        XCTAssertEqual(value, 12345)
        XCTAssertEqual(tracker.sortedReadings.count, 1)
    }

    func testFetchCurrentValue_returnsMostRecentByDateNotInsertionOrder() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let provider = ManualEntryProvider(modelContext: context)
        let tracker = makeTracker(in: context)
        let target = SourceTarget(id: tracker.sourceTargetId!, displayName: tracker.name)
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        // Log the more recent reading first, then an older backfilled one —
        // the current value should still resolve to the later date.
        try await provider.logManualReading(target: target, value: 200, date: later)
        try await provider.logManualReading(target: target, value: 100, date: earlier)

        let value = try await provider.fetchCurrentValue(target: target)
        XCTAssertEqual(value, 200)
    }

    func testDifferentTrackers_haveIndependentReadingHistories() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let provider = ManualEntryProvider(modelContext: context)
        let carA = makeTracker(in: context, name: "Car A mileage")
        let carB = makeTracker(in: context, name: "Car B mileage")
        let targetA = SourceTarget(id: carA.sourceTargetId!, displayName: carA.name)
        let targetB = SourceTarget(id: carB.sourceTargetId!, displayName: carB.name)

        try await provider.logManualReading(target: targetA, value: 10_000, date: Date())
        try await provider.logManualReading(target: targetB, value: 50_000, date: Date())

        let valueA = try await provider.fetchCurrentValue(target: targetA)
        let valueB = try await provider.fetchCurrentValue(target: targetB)

        XCTAssertEqual(valueA, 10_000)
        XCTAssertEqual(valueB, 50_000)
    }

    func testTrackerSortedReadings_returnsFullHistoryOldestFirst() async throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let provider = ManualEntryProvider(modelContext: context)
        let tracker = makeTracker(in: context)
        let target = SourceTarget(id: tracker.sourceTargetId!, displayName: tracker.name)
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        try await provider.logManualReading(target: target, value: 200, date: later)
        try await provider.logManualReading(target: target, value: 100, date: earlier)

        let readings = tracker.sortedReadings

        XCTAssertEqual(readings.map(\.value), [100, 200])
        XCTAssertEqual(readings.map(\.date), [earlier, later])
    }
}
