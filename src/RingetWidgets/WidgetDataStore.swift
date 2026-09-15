//
//  WidgetDataStore.swift
//  RingetWidgets
//

import Foundation
import SwiftData
import os

/// The widget extension's own read access to the same CloudKit-synced
/// SwiftData store the main app uses (§6 of the build spec) — widgets run in
/// a separate process, so they open their own `ModelContainer` against the
/// same `iCloud.martinkearn.Ringet` container rather than sharing the app's
/// in-memory one. No App Group is needed for this: CloudKit sync (not a
/// shared local file) is what keeps the two processes' data consistent.
enum WidgetDataStore {
    private static let logger = Logger(subsystem: "martinkearn.Ringet.RingetWidgets", category: "WidgetDataStore")

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

    @MainActor
    static func fetchAllTrackers() throws -> [Tracker] {
        do {
            let container = try makeContainer()
            let descriptor = FetchDescriptor<Tracker>(sortBy: [SortDescriptor(\.name)])
            return try container.mainContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch trackers: \(error, privacy: .public)")
            throw error
        }
    }

    @MainActor
    static func fetchTracker(id: UUID) throws -> Tracker? {
        try fetchAllTrackers().first { $0.id == id }
    }
}
