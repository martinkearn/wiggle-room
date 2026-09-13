//
//  TrackerStore.swift
//  Ringet
//

import Foundation
import Observation

/// App-wide, in-memory state: created trackers and the connected sources
/// they can point at. Not yet backed by persistence — that lands with the
/// SwiftData/CloudKit phase (§6), at which point this becomes a thin
/// wrapper over a `ModelContext` rather than an in-memory array.
@Observable
final class TrackerStore {
    private(set) var trackers: [Tracker] = []

    let manualProvider = ManualEntryProvider()

    /// The single, fixed "Manual Entry" pseudo-source. Picking it for a
    /// tracker means the user logs its readings themselves rather than the
    /// app reading them from anywhere — it isn't a real connection, just
    /// the provider-abstraction plumbing (§5.1) a `Tracker.connectedSourceId`
    /// needs to point at. Unlike a real connected source it is never listed
    /// in Settings → Connected Sources (§5.2) and there is exactly one of
    /// it — never user-creatable, never duplicated.
    let manualEntrySource: ConnectedSource

    /// Real external connections the user has added (Starling, Tesla, …).
    /// Starts empty — no such provider is implemented yet (§9); these are
    /// the only entries Settings → Connected Sources lists or lets the user
    /// add to.
    private(set) var addedSources: [ConnectedSource] = []

    init() {
        manualEntrySource = ConnectedSource(providerId: manualProvider.providerId, displayName: "Manual Entry")
    }

    /// The connected source a tracker should point at, given a source
    /// picker selection that may be the fixed manual entry id or one of
    /// `addedSources`.
    func source(withId id: UUID) -> ConnectedSource? {
        if id == manualEntrySource.id { return manualEntrySource }
        return addedSources.first { $0.id == id }
    }

    func addTracker(_ tracker: Tracker) {
        trackers.append(tracker)
    }
}
