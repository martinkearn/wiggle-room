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

    /// All connected sources (§5.2), for the Settings → Connected Sources
    /// screen. A manual entry connection needs no auth/setup step
    /// (`requiresConnection == false`, §5.1), so one is provisioned
    /// automatically here rather than requiring a user-facing "add a
    /// source" step — that step is only meaningful once Starling/Tesla
    /// exist, since only those require an actual account connection.
    private(set) var connectedSources: [ConnectedSource]

    /// The manual connection every manual tracker is created against for
    /// now. Always the first entry in `connectedSources`.
    var defaultManualSource: ConnectedSource { connectedSources[0] }

    init() {
        connectedSources = [ConnectedSource(providerId: manualProvider.providerId, displayName: "Manual entries")]
    }

    func addTracker(_ tracker: Tracker) {
        trackers.append(tracker)
    }
}
