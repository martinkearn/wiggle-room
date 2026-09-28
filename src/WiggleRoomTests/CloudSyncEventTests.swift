//
//  CloudSyncEventTests.swift
//  WiggleRoomTests
//

import CloudKit
import XCTest
@testable import WiggleRoom

final class CloudSyncEventTests: XCTestCase {

    // MARK: - Failure reasons

    func testAPlainErrorGivesItsDescriptionDomainAndCode() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134422, userInfo: [
            NSLocalizedDescriptionKey: "CloudKit setup failed."
        ])
        XCTAssertEqual(CloudSyncEvent.failureReason(for: error),
                       "CloudKit setup failed. (NSCocoaErrorDomain 134422)")
    }

    func testAPartialFailureNamesThePerRecordReasonAndTheServerMessage() {
        let error = partialFailure([
            recordID("tracker-1"): schemaError,
            recordID("tracker-2"): schemaError
        ])
        XCTAssertEqual(CloudSyncEvent.failureReason(for: error), """
            Failed to modify some records (CKErrorDomain \(CKError.Code.partialFailure.rawValue))
            2 records: Invalid Arguments — Cannot create or modify field 'CD_exampleField' in record 'CD_Tracker' in production schema (CKErrorDomain \(CKError.Code.invalidArguments.rawValue))
            """)
    }

    func testRecordsThatOnlyFailedWithTheirBatchAreLeftOut() {
        let error = partialFailure([
            recordID("tracker-1"): schemaError,
            recordID("reading-1"): cloudKitError(.batchRequestFailed, "Batch Request Failed"),
            recordID("reading-2"): cloudKitError(.batchRequestFailed, "Batch Request Failed")
        ])
        let reason = CloudSyncEvent.failureReason(for: error)
        XCTAssertTrue(reason.contains("1 record: Invalid Arguments"))
        XCTAssertFalse(reason.contains("Batch Request Failed"))
    }

    func testABatchFailureIsStillReportedWhenItIsTheOnlyReasonGiven() {
        let error = partialFailure([
            recordID("reading-1"): cloudKitError(.batchRequestFailed, "Batch Request Failed")
        ])
        XCTAssertTrue(CloudSyncEvent.failureReason(for: error).contains("1 record: Batch Request Failed"))
    }

    func testAPartialFailureWrappedByCoreDataIsStillFound() {
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [
            NSLocalizedDescriptionKey: "Export failed.",
            NSUnderlyingErrorKey: partialFailure([recordID("tracker-1"): schemaError])
        ])
        let reason = CloudSyncEvent.failureReason(for: wrapped)
        XCTAssertTrue(reason.hasPrefix("Failed to modify some records"))
        XCTAssertTrue(reason.contains("CD_exampleField"))
    }

    func testTheMostCommonReasonLeadsAndTheRestAreCounted() {
        let error = partialFailure([
            recordID("a-1"): cloudKitError(.invalidArguments, "Reason A"),
            recordID("b-1"): cloudKitError(.invalidArguments, "Reason B"),
            recordID("b-2"): cloudKitError(.invalidArguments, "Reason B"),
            recordID("c-1"): cloudKitError(.invalidArguments, "Reason C"),
            recordID("d-1"): cloudKitError(.invalidArguments, "Reason D"),
            recordID("e-1"): cloudKitError(.invalidArguments, "Reason E")
        ])
        let lines = CloudSyncEvent.failureReason(for: error).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1 + CloudSyncEvent.maximumListedItemReasons + 1)
        XCTAssertTrue(lines[1].hasPrefix("2 records: Reason B"))
        XCTAssertTrue(lines[2].hasPrefix("1 record: Reason A"))
        XCTAssertEqual(lines.last, "2 other reasons.")
    }

    func testAPartialFailureWithNoPerRecordErrorsFallsBackToItsOwnDescription() {
        let error = partialFailure([:])
        XCTAssertEqual(CloudSyncEvent.failureReason(for: error),
                       "Failed to modify some records (CKErrorDomain \(CKError.Code.partialFailure.rawValue))")
    }

    // MARK: - Activity

    func testAFinishedEventReplacesTheOneInProgress() {
        var activity = CloudSyncActivity()
        let id = UUID()
        activity.record(event(id, finished: false))
        XCTAssertEqual(activity.inProgress?.id, id)
        XCTAssertNil(activity.lastFinished)

        activity.record(event(id, finished: true, succeeded: true))
        XCTAssertNil(activity.inProgress)
        XCTAssertEqual(activity.lastFinished?.id, id)
    }

    func testAFailureStaysVisibleWhileTheRetryRuns() {
        var activity = CloudSyncActivity()
        let failed = UUID()
        let retry = UUID()
        activity.record(event(failed, finished: false))
        activity.record(event(failed, finished: true, succeeded: false, reason: "Rejected"))
        activity.record(event(retry, finished: false))

        XCTAssertEqual(activity.lastFinished?.id, failed)
        XCTAssertTrue(activity.lastFinished?.isFailure ?? false)
        XCTAssertEqual(activity.lastFinished?.failureReason, "Rejected")
        XCTAssertEqual(activity.inProgress?.id, retry)
    }

    func testAStartDeliveredAfterItsOwnEndIsIgnored() {
        var activity = CloudSyncActivity()
        let id = UUID()
        activity.record(event(id, finished: true, succeeded: true))
        activity.record(event(id, finished: false))
        XCTAssertNil(activity.inProgress)
        XCTAssertEqual(activity.lastFinished?.id, id)
    }

    // MARK: - Helpers

    private var schemaError: NSError {
        NSError(domain: CKError.errorDomain, code: CKError.Code.invalidArguments.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Invalid Arguments",
            "ServerErrorDescription": "Cannot create or modify field 'CD_exampleField' in record 'CD_Tracker' in production schema"
        ])
    }

    private func cloudKitError(_ code: CKError.Code, _ description: String) -> NSError {
        NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name)
    }

    private func partialFailure(_ itemErrors: [CKRecord.ID: NSError]) -> NSError {
        NSError(domain: CKError.errorDomain, code: CKError.Code.partialFailure.rawValue, userInfo: [
            NSLocalizedDescriptionKey: "Failed to modify some records",
            CKPartialErrorsByItemIDKey: itemErrors
        ])
    }

    private func event(_ id: UUID, finished: Bool, succeeded: Bool = false, reason: String? = nil) -> CloudSyncEvent {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return CloudSyncEvent(
            id: id,
            kind: .upload,
            startedAt: start,
            endedAt: finished ? start.addingTimeInterval(2) : nil,
            succeeded: succeeded,
            failureReason: reason
        )
    }
}
