//
//  IntentDataStore.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// Shortcuts/Siri can invoke an intent while the app isn't running, so
/// intents can't rely on the live `TrackerStore`/`ModelContainer` the app's
/// own `WindowGroup` builds — same reasoning as `WidgetDataStore` in the
/// widget extension. Opens its own container against the same CloudKit
/// container (once per process, then reused — see `cachedContainer`), rather
/// than trying to share the app's in-memory one.
enum IntentDataStore {
    /// One container kept alive for the life of the process. A `Tracker`
    /// fetched from a container that has since been deallocated is
    /// *detached*, and reading any property on it is a hard SwiftData crash
    /// ("backing data was detached from a context") — which is exactly what
    /// happened when this was a fresh container per call and callers such as
    /// `TrackerSpotlightIndexer` read `tracker.id` after it had gone.
    @MainActor
    private static var cachedContainer: ModelContainer?

    @MainActor
    static func makeContainer() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        // Must stay identical to every other process's schema for this same
        // store (`WiggleRoomApp`, `WidgetDataStore`, `WiggleRoomWatchApp`) —
        // a mismatched schema between processes sharing one on-disk/CloudKit
        // store is a real corruption risk, not just a compile-time detail.
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self, StarlingRequestLogEntry.self])
        // Shared App Group container (see `AppGroup`) — same store the app
        // and widget extension use, so a Shortcut logging a reading is
        // reflected everywhere instantly rather than waiting on CloudKit.
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .automatic
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        cachedContainer = container
        return container
    }

    @MainActor
    static func fetchAllTrackers() throws -> [Tracker] {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<Tracker>(sortBy: [SortDescriptor(\.name)])
        let trackers = try container.mainContext.fetch(descriptor)
        // Shortcuts/Siri can run in their own process with no `TrackerStore`
        // mutation involved (e.g. just reading trackers) — keep the shared
        // picker cache (`TrackerListCache`) current here too.
        TrackerListCache.save(trackers)
        return trackers
    }

    @MainActor
    static func fetchTracker(id: UUID) throws -> Tracker? {
        try fetchAllTrackers().first { $0.id == id }
    }

    @MainActor
    static func store() throws -> TrackerStore {
        let container = try makeContainer()
        return TrackerStore(modelContext: container.mainContext)
    }
}
