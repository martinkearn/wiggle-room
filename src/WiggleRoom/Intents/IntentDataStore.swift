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
/// container each time, rather than trying to share the app's in-memory one.
enum IntentDataStore {
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func fetchAllTrackers() throws -> [Tracker] {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<Tracker>(sortBy: [SortDescriptor(\.name)])
        return try container.mainContext.fetch(descriptor)
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
