//
//  WiggleRoomApp.swift
//  WiggleRoom
//
//  Created by Martin Kearn on 13/09/2026.
//

import SwiftUI
import SwiftData

@main
struct WiggleRoomApp: App {
    let modelContainer: ModelContainer
    @State private var store: TrackerStore
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var appCommands = AppCommands()

    init() {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])

        // Full cross-device sync via CloudKit (§6), now that the paid Apple
        // Developer Program account is active and the iCloud capability is
        // registered (see `WiggleRoom/WiggleRoom.entitlements` and the project's
        // CODE_SIGN_ENTITLEMENTS build setting). Falls back to local-only
        // storage if CloudKit is ever unavailable (e.g. no iCloud account
        // signed in on this device) rather than hard-crashing the app.
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

        #if os(iOS)
        WiggleRoomFont.installNavigationBarAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(deepLinkRouter)
                .environment(appCommands)
                .tint(WiggleRoomColors.brand)
                .onOpenURL { url in
                    deepLinkRouter.handle(url)
                }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tracker") {
                    appCommands.requestNewTracker()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            ConnectedSourcesView()
                .environment(store)
                .modelContainer(modelContainer)
        }
        #endif

        #if os(macOS)
        MenuBarExtra {
            MenuBarStatusView()
                .environment(store)
                .modelContainer(modelContainer)
        } label: {
            MenuBarStatusLabel()
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}
