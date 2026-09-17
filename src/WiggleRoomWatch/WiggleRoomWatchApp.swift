//
//  WiggleRoomWatchApp.swift
//  WiggleRoomWatch
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
struct WiggleRoomWatchApp: App {
    let modelContainer: ModelContainer
    @State private var store: TrackerStore

    init() {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])
        // Shared App Group container (see `AppGroup`) so the complication
        // extension (`WidgetDataStore`, embedded alongside this app on the
        // same Watch) reads the exact same on-disk store instead of its own
        // separate copy — same reasoning as the phone app/widgets pairing.
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .automatic
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            modelContainer = container
        } else {
            let localConfiguration = ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier))
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
