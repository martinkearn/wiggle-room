import SwiftData
import XCTest
@testable import WiggleRoom

@MainActor
final class TrackerArchiveTests: XCTestCase {
    func testExportDeduplicatesSourceSharedByMultipleTrackers() {
        let container = makeInMemoryModelContainer()
        let store = TrackerStore(modelContext: container.mainContext)
        let first = makeTracker(name: "First", source: store.manualEntrySource)
        let second = makeTracker(name: "Second", source: store.manualEntrySource)

        let archive = TrackerArchiveService.makeArchive(trackers: [first, second])

        XCTAssertEqual(archive.trackers.count, 2)
        XCTAssertEqual(archive.sources.count, 1)
        XCTAssertEqual(archive.sources.first?.id, store.manualEntrySource.id)
    }

    func testArchiveRoundTripPreservesEveryTrackerDetailAndReading() throws {
        let container = makeInMemoryModelContainer()
        let context = container.mainContext
        let store = TrackerStore(modelContext: context)
        let tracker = Tracker(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Fictional Holiday",
            type: .spendingMoney,
            connectedSource: store.manualEntrySource,
            sourceTargetId: "00000000-0000-0000-0000-000000000101",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_710_000_000),
            startingValue: Decimal(string: "1234.56")!,
            totalAllowance: Decimal(string: "1000.25")!,
            reminderCadenceMinutes: 1440
        )
        tracker.lastAutoFetchAttempt = Date(timeIntervalSince1970: 1_700_100_000)
        tracker.lastCheckedDate = Date(timeIntervalSince1970: 1_700_200_000)
        tracker.hasCelebratedCompletion = true
        tracker.sortOrder = 3
        tracker.colorIndex = 4
        tracker.glyph = "airplane"
        store.addTracker(tracker)
        let reading = ValueSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            value: Decimal(string: "987.65")!,
            date: Date(timeIntervalSince1970: 1_705_000_000)
        )
        reading.tracker = tracker
        context.insert(reading)
        try context.save()

        let encoded = try TrackerArchiveService.encode(
            TrackerArchiveService.makeArchive(trackers: [tracker])
        )
        let decoded = try TrackerArchiveService.decode(encoded)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.trackers.count, 1)
        let archived = try XCTUnwrap(decoded.trackers.first)
        XCTAssertEqual(archived.id, tracker.id)
        XCTAssertEqual(archived.name, tracker.name)
        XCTAssertEqual(archived.unit, tracker.unit)
        XCTAssertEqual(archived.type, tracker.typeRawValue)
        XCTAssertEqual(archived.sourceTargetId, tracker.sourceTargetId)
        XCTAssertEqual(archived.startDate, tracker.startDate)
        XCTAssertEqual(archived.endDate, tracker.endDate)
        XCTAssertEqual(archived.startingValue, "1234.56")
        XCTAssertEqual(archived.totalAllowance, "1000.25")
        XCTAssertEqual(archived.reminderCadenceMinutes, 1440)
        XCTAssertEqual(archived.lastAutoFetchAttempt, tracker.lastAutoFetchAttempt)
        XCTAssertEqual(archived.lastCheckedDate, tracker.lastCheckedDate)
        XCTAssertTrue(archived.hasCelebratedCompletion)
        XCTAssertEqual(archived.sortOrder, 3)
        XCTAssertEqual(archived.colorIndex, 4)
        XCTAssertEqual(archived.glyph, "airplane")
        XCTAssertEqual(archived.readings.first?.id, reading.id)
        XCTAssertEqual(archived.readings.first?.value, "987.65")
        XCTAssertEqual(archived.readings.first?.date, reading.date)
    }

    func testImportMapsExternalSourceWithoutExportingCredential() throws {
        let sourceContainer = makeInMemoryModelContainer()
        let sourceContext = sourceContainer.mainContext
        let sourceStore = TrackerStore(modelContext: sourceContext)
        let originalSource = ConnectedSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            providerId: "starling",
            displayName: "Fictional Bank",
            credentialToken: "synthetic-token"
        )
        sourceContext.insert(originalSource)
        let tracker = Tracker(
            name: "Fictional Budget",
            type: .spendingMoney,
            connectedSource: originalSource,
            sourceTargetId: "synthetic-account",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 80
        )
        sourceStore.addTracker(tracker)
        let data = try TrackerArchiveService.encode(
            TrackerArchiveService.makeArchive(trackers: [tracker])
        )
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("synthetic-token"))

        let destinationContainer = makeInMemoryModelContainer()
        let destinationContext = destinationContainer.mainContext
        let destinationStore = TrackerStore(modelContext: destinationContext)
        let replacementSource = ConnectedSource(
            providerId: "starling",
            displayName: "Replacement Bank",
            credentialToken: "different-synthetic-token"
        )
        destinationContext.insert(replacementSource)
        let archive = try TrackerArchiveService.decode(data)
        let archivedSourceID = try XCTUnwrap(archive.externalSources.first?.id)

        try TrackerArchiveService.importArchive(
            archive,
            sourceMappings: [archivedSourceID: replacementSource],
            store: destinationStore,
            modelContext: destinationContext
        )

        let imported = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<Tracker>()).first)
        XCTAssertEqual(imported.connectedSource?.id, replacementSource.id)
        XCTAssertEqual(imported.sourceTargetId, "synthetic-account")
    }

    func testImportWithoutSourceCreatesReadOnlyTracker() throws {
        let sourceContainer = makeInMemoryModelContainer()
        let sourceContext = sourceContainer.mainContext
        let sourceStore = TrackerStore(modelContext: sourceContext)
        let externalSource = ConnectedSource(providerId: "starling", displayName: "Fictional Bank")
        sourceContext.insert(externalSource)
        let tracker = Tracker(
            name: "Read Only Example",
            type: .spendingMoney,
            connectedSource: externalSource,
            sourceTargetId: "synthetic-account",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            startingValue: 100,
            totalAllowance: 100
        )
        sourceStore.addTracker(tracker)
        let archive = TrackerArchiveService.makeArchive(trackers: [tracker])

        let destinationContainer = makeInMemoryModelContainer()
        let destinationContext = destinationContainer.mainContext
        let destinationStore = TrackerStore(modelContext: destinationContext)
        try TrackerArchiveService.importArchive(
            archive,
            sourceMappings: [:],
            store: destinationStore,
            modelContext: destinationContext
        )

        let imported = try XCTUnwrap(destinationContext.fetch(FetchDescriptor<Tracker>()).first)
        XCTAssertNil(imported.connectedSource)
        XCTAssertFalse(imported.isManualEntry)
        XCTAssertEqual(imported.sourceTargetId, "synthetic-account")
    }

    private func makeTracker(name: String, source: ConnectedSource) -> Tracker {
        Tracker(
            name: name,
            type: .mileage,
            connectedSource: source,
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            startingValue: 0,
            totalAllowance: 100
        )
    }
}
