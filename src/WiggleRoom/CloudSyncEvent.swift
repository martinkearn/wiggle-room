//
//  CloudSyncEvent.swift
//  WiggleRoom
//

import CloudKit
import CoreData
import Foundation

/// One CloudKit mirroring event — setting up, downloading or uploading — as
/// reported by `NSPersistentCloudKitContainer.eventChangedNotification`,
/// which SwiftData's CloudKit-backed store posts too. Copied out of the
/// Core Data `Event` into plain values so it can cross to the main actor
/// and be compared in tests. `nonisolated` because the target defaults to
/// main-actor isolation and this is built on Core Data's posting thread.
///
/// This is what tells the CloudKit Sync screen whether sync is actually
/// working. Whether the container loaded says nothing about it: a store can
/// load with CloudKit enabled while the server rejects every upload, and
/// downloads still arrive, so nothing else on the device looks wrong.
nonisolated struct CloudSyncEvent: Equatable, Sendable {
    nonisolated enum Kind: CaseIterable, Sendable {
        case setup
        case download
        case upload
    }

    let id: UUID
    let kind: Kind
    let startedAt: Date
    /// `nil` while the event is still running. Core Data posts each event
    /// twice under the same identifier: once as it starts, once as it ends.
    let endedAt: Date?
    let succeeded: Bool
    let failureReason: String?

    var isFinished: Bool { endedAt != nil }
    var isFailure: Bool { isFinished && !succeeded }

    init(id: UUID, kind: Kind, startedAt: Date, endedAt: Date?, succeeded: Bool, failureReason: String?) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.succeeded = succeeded
        self.failureReason = failureReason
    }

    /// `nil` for an event type this build doesn't know about.
    init?(_ event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind
        switch event.type {
        case .setup:
            kind = .setup
        case .import:
            kind = .download
        case .export:
            kind = .upload
        @unknown default:
            return nil
        }
        let isFinished = event.endDate != nil
        self.init(
            id: event.identifier,
            kind: kind,
            startedAt: event.startDate,
            endedAt: event.endDate,
            succeeded: event.succeeded,
            failureReason: isFinished && !event.succeeded
                ? event.error.map(Self.failureReason(for:)) ?? "No error was reported."
                : nil
        )
    }

    // MARK: - Failure reasons

    /// How many distinct per-record reasons a partial failure lists before
    /// summarising the rest as a count.
    static let maximumListedItemReasons = 3

    /// A readable account of why an event failed. For a
    /// `CKError.partialFailure` that is the per-record errors, because the
    /// top-level error only says "some records failed" — the reason, such as
    /// a field missing from the Production schema, is on each record. Core
    /// Data often wraps the CloudKit error, so the underlying errors are
    /// searched too.
    static func failureReason(for error: any Error) -> String {
        if let partialFailure = partialFailure(in: error as NSError),
           let itemReasons = itemReasons(for: partialFailure) {
            return "\(describe(partialFailure as NSError))\n\(itemReasons)"
        }
        return describe(error as NSError)
    }

    private static func partialFailure(in error: NSError, depth: Int = 0) -> CKError? {
        if let cloudKitError = (error as Error) as? CKError, cloudKitError.code == .partialFailure {
            return cloudKitError
        }
        guard depth < 4, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return nil
        }
        return partialFailure(in: underlying, depth: depth + 1)
    }

    private static func itemReasons(for partialFailure: CKError) -> String? {
        let itemErrors = (partialFailure.partialErrorsByItemID ?? [:]).values.map { $0 as NSError }
        guard !itemErrors.isEmpty else { return nil }

        // A batch fails as a whole: records that were fine are reported
        // as `batchRequestFailed`, and only the others say what was wrong.
        let causes = itemErrors.filter { !isBatchRequestFailed($0) }
        let reported = causes.isEmpty ? itemErrors : causes

        var counts: [String: Int] = [:]
        for error in reported {
            counts[describe(error), default: 0] += 1
        }
        // Most common first, so the reason behind most of the failures
        // leads. Ties are alphabetical because dictionary order isn't
        // stable between runs.
        let reasons = counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs] ?? 0
            let rhsCount = counts[rhs] ?? 0
            return lhsCount == rhsCount ? lhs < rhs : lhsCount > rhsCount
        }

        var lines = reasons.prefix(maximumListedItemReasons).map { reason in
            let count = counts[reason] ?? 1
            return "\(count) record\(count == 1 ? "" : "s"): \(reason)"
        }
        let unlisted = reasons.count - maximumListedItemReasons
        if unlisted > 0 {
            lines.append("\(unlisted) other reason\(unlisted == 1 ? "" : "s").")
        }
        return lines.joined(separator: "\n")
    }

    private static func isBatchRequestFailed(_ error: NSError) -> Bool {
        ((error as Error) as? CKError)?.code == .batchRequestFailed
    }

    /// The error's own description, the CloudKit server's message when it
    /// gave one (that is where a schema problem is named), and the domain
    /// and code, which are what to search for.
    private static func describe(_ error: NSError) -> String {
        var text = error.localizedDescription
        if let serverMessage = error.userInfo["ServerErrorDescription"] as? String,
           !serverMessage.isEmpty, !text.contains(serverMessage) {
            text += " — \(serverMessage)"
        }
        return "\(text) (\(error.domain) \(error.code))"
    }
}

/// What this process has seen of one kind of CloudKit event since launch:
/// the last one to finish, and one still running if there is one. The
/// finished result is kept while a retry runs, so a failure stays on screen
/// until something actually replaces it rather than flickering away each
/// time CloudKit tries again.
nonisolated struct CloudSyncActivity: Equatable, Sendable {
    private(set) var lastFinished: CloudSyncEvent?
    private(set) var inProgress: CloudSyncEvent?

    mutating func record(_ event: CloudSyncEvent) {
        if event.isFinished {
            lastFinished = event
            if inProgress?.id == event.id {
                inProgress = nil
            }
        } else if lastFinished?.id != event.id {
            // A start delivered after its own end is stale.
            inProgress = event
        }
    }
}
