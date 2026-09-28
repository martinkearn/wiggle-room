//
//  IntentDataStore.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// The store that intents, Spotlight indexing and notification actions use.
///
/// Inside the app, that is the app's own container and `TrackerStore`,
/// which `WiggleRoomApp` registers as it launches (`useAppStore`). Only one
/// CloudKit-mirrored container may exist per store per process: a second
/// one fails CloudKit setup ("There is another instance of this persistent
/// store actively syncing with CloudKit in this process", Cocoa error
/// 134422) and competes with the first for the same export activity.
///
/// Where nothing has been registered, such as a process in which
/// `WiggleRoomApp` never ran, this opens its own container against the same
/// App Group store and CloudKit container, once per process.
enum IntentDataStore {
    /// One container kept alive for the life of the process. A `Tracker`
    /// fetched from a container that has since been deallocated is
    /// *detached*, and reading any property on it is a hard SwiftData crash
    /// ("backing data was detached from a context") — which is exactly what
    /// happened when this was a fresh container per call and callers such as
    /// `TrackerSpotlightIndexer` read `tracker.id` after it had gone.
    @MainActor
    private static var cachedContainer: ModelContainer?

    /// The app's own store, when running inside the app.
    @MainActor
    private static var appStore: TrackerStore?

    /// Makes every later call use the app's container and store instead of
    /// opening a second container. Call it as soon as the app's container
    /// exists, before anything can reach this type.
    @MainActor
    static func useAppStore(_ store: TrackerStore, container: ModelContainer) {
        assert(
            cachedContainer == nil || cachedContainer === container,
            "IntentDataStore opened its own container before the app registered one"
        )
        cachedContainer = container
        appStore = store
    }

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
        if let appStore { return appStore }
        let container = try makeContainer()
        return TrackerStore(modelContext: container.mainContext)
    }
}
