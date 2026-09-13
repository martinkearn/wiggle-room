//
//  RingetApp.swift
//  Ringet
//
//  Created by Martin Kearn on 13/09/2026.
//

import SwiftUI
import SwiftData

@main
struct RingetApp: App {
    let modelContainer: ModelContainer
    @State private var store: TrackerStore

    init() {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])

        // Full cross-device sync via CloudKit is a hard requirement (§6),
        // but the iCloud capability isn't available on a free/personal
        // Apple Developer team — Xcode refuses to provision it at all
        // ("Personal development teams... do not support the iCloud
        // capability"). Storage is local-only until this account is
        // upgraded to the paid Apple Developer Program (§10, $99/year).
        //
        // To enable sync once upgraded: uncomment the cloud configuration
        // below, restore `Ringet/Ringet.entitlements` as this target's
        // CODE_SIGN_ENTITLEMENTS build setting (it already declares the
        // iCloud.martinkearn.Ringet container + CloudKit service — it's
        // just sitting unreferenced in the project for now), and add the
        // iCloud capability in Xcode's Signing & Capabilities tab so it
        // registers with the (now-paid) developer account.
        //
        // let cloudConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        // if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
        //     modelContainer = container
        // } else {
        let localConfiguration = ModelConfiguration(schema: schema)
        guard let localContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
            fatalError("Could not create a local ModelContainer")
        }
        modelContainer = localContainer
        // }

        _store = State(initialValue: TrackerStore(modelContext: modelContainer.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .modelContainer(modelContainer)
    }
}
