//
//  WidgetDataStore.swift
//  WiggleRoomWidgets
//

import Foundation
import SwiftData
import os

/// The widget extension's own read access to the same CloudKit-synced
/// SwiftData store the main app uses (§6 of the build spec) — widgets run in
/// a separate process, so they open their own `ModelContainer` against the
/// same `iCloud.martinkearn.WiggleRoom` container rather than sharing the app's
/// in-memory one. No App Group is needed for this: CloudKit sync (not a
/// shared local file) is what keeps the two processes' data consistent.
enum WidgetDataStore {
    private static let logger = Logger(subsystem: "martinkearn.WiggleRoom.WiggleRoomWidgets", category: "WidgetDataStore")

    /// Created once and reused for the lifetime of the extension process —
    /// standing up a CloudKit-backed `ModelContainer` from scratch isn't
    /// free, and App Intents entity queries (the "choose a tracker" widget
    /// configuration UI in particular) have a short time budget before the
    /// picker just gives up and shows nothing, with no visible error.
    @MainActor
    private static var cachedContainer: ModelContainer?

    @MainActor
    static func makeContainer() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            cachedContainer = container
            return container
        } catch {
            logger.error("Failed to create CloudKit ModelContainer: \(error, privacy: .public)")
            throw error
        }
    }

    /// A plain, immediate fetch with no retry — for `placeholder(in:)`,
    /// which WidgetKit expects to return instantly and doesn't award any
    /// extra time budget to. Fine for it to come back empty on a cold
    /// extension process; the placeholder is a generic skeleton, not the
    /// figure a user is actually trying to read.
    @MainActor
    static func fetchAllTrackersImmediately() throws -> [Tracker] {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<Tracker>(sortBy: [SortDescriptor(\.name)])
        return try container.mainContext.fetch(descriptor)
    }

    /// The very first time this extension's sandboxed container talks to
    /// CloudKit (a fresh install, a fresh Simulator container), SwiftData's
    /// initial history import runs asynchronously in the background — the
    /// `ModelContainer` can finish initializing and a fetch can legitimately
    /// see zero rows before that import lands, even though the real data
    /// already exists in iCloud. Reported as the widget's "choose a
    /// tracker" picker flashing "Loading" and coming back empty. Polling
    /// briefly here (instead of accepting the first empty result) is a
    /// one-time cold-start cost per extension process — once
    /// `cachedContainer` above is warm, later calls return immediately.
    @MainActor
    static func fetchAllTrackers() async throws -> [Tracker] {
        do {
            var trackers = try fetchAllTrackersImmediately()
            guard trackers.isEmpty else { return trackers }
            for attempt in 1...8 {
                try await Task.sleep(nanoseconds: 500_000_000)
                trackers = try fetchAllTrackersImmediately()
                if !trackers.isEmpty {
                    logger.notice("Trackers appeared after waiting for initial CloudKit import (attempt \(attempt)).")
                    break
                }
            }
            return trackers
        } catch {
            logger.error("Failed to fetch trackers: \(error, privacy: .public)")
            throw error
        }
    }

    @MainActor
    static func fetchTracker(id: UUID) async throws -> Tracker? {
        try await fetchAllTrackers().first { $0.id == id }
    }

    /// Used only by the interactive "choose a tracker" widget configuration
    /// picker (`TrackerEntityQuery.suggestedEntities()`), which already
    /// shows its own "Loading" state, so a short wait here is expected
    /// rather than surprising. Unlike `fetchAllTrackers()` above, this keeps
    /// re-fetching for a few seconds even when the *first* result already
    /// has trackers in it — a tracker created moments ago in the main app
    /// still has to make a round trip through CloudKit and back down into
    /// this extension's own separate local store, which doesn't finish just
    /// because this container already had other trackers cached from
    /// before. Returns whichever fetch found the most trackers, on the
    /// assumption the local store only gains rows during this short window,
    /// never loses ones it already had.
    @MainActor
    static func fetchAllTrackersForConfiguration() async throws -> [Tracker] {
        do {
            var best = try fetchAllTrackersImmediately()
            let attempts = best.isEmpty ? 12 : 6
            for _ in 0..<attempts {
                try await Task.sleep(nanoseconds: 500_000_000)
                let latest = try fetchAllTrackersImmediately()
                if latest.count > best.count {
                    best = latest
                }
            }
            return best
        } catch {
            logger.error("Failed to fetch trackers for configuration: \(error, privacy: .public)")
            throw error
        }
    }
}
