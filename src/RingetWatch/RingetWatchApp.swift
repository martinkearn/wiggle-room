//
//  RingetWatchApp.swift
//  RingetWatch
//

import SwiftUI
import SwiftData

/// The watch companion app (§7.3) — a proper product surface, not a shrunk
/// iPhone screen: a tracker list, a glanceable detail view built from the
/// same `RingsView` the phone uses, and (since manual entry is the only
/// provider in scope tonight) the ability to log a reading right from the
/// wrist. Talks to the same CloudKit container as the phone/Mac (§6)
/// independently — it does not require the phone nearby.
@main
struct RingetWatchApp: App {
    let modelContainer: ModelContainer
    @State private var store: TrackerStore

    init() {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])
        let cloudConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            modelContainer = container
        } else {
            let localConfiguration = ModelConfiguration(schema: schema)
            guard let localContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
                fatalError("Could not create a ModelContainer")
            }
            modelContainer = localContainer
        }
        _store = State(initialValue: TrackerStore(modelContext: modelContainer.mainContext))
        CloudSyncWidgetRefresher.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchTrackerListView()
                .environment(store)
        }
        .modelContainer(modelContainer)
    }
}
