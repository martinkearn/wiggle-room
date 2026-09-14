//
//  WidgetDataStore.swift
//  RingetWidgets
//

import Foundation
import SwiftData

/// The widget extension's own read access to the same CloudKit-synced
/// SwiftData store the main app uses (§6 of the build spec) — widgets run in
/// a separate process, so they open their own `ModelContainer` against the
/// same `iCloud.martinkearn.Ringet` container rather than sharing the app's
/// in-memory one. No App Group is needed for this: CloudKit sync (not a
/// shared local file) is what keeps the two processes' data consistent.
///
/// A fresh `ModelContainer` is opened on every call rather than cached —
/// simplest correct thing for a process that's spun up briefly per timeline
/// refresh; worth revisiting if widget refreshes ever show up as slow.
enum WidgetDataStore {
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
}
