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
    @AppStorage(appThemePreferenceKey) private var appThemePreferenceRawValue = AppThemePreference.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    /// Guards the `.active` housekeeping below to once per app session —
    /// see its own call site for why.
    @State private var hasRunActivationHousekeeping = false
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self, StarlingRequestLogEntry.self])

        // Full cross-device sync via CloudKit (§6), now that the paid Apple
        // Developer Program account is active and the iCloud capability is
        // registered (see `WiggleRoom/WiggleRoom.entitlements` and the project's
        // CODE_SIGN_ENTITLEMENTS build setting). Falls back to local-only
        // storage if CloudKit is ever unavailable (e.g. no iCloud account
        // signed in on this device) rather than hard-crashing the app.
        //
        // `groupContainer: .identifier(AppGroup.identifier)` puts the local
        // store inside the shared App Group container instead of this
        // target's own private one — the widget extension (`WidgetDataStore`)
        // opens the exact same file, so a reading logged here is visible to
        // the widget instantly, with no CloudKit round-trip needed for
        // same-device freshness. CloudKit is still what syncs across
        // different devices.
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            CloudSyncDiagnostics.shared.recordCloudKitStore()
        } catch {
            CloudSyncDiagnostics.shared.recordLocalFallback(error: error)
            let localConfiguration = ModelConfiguration(schema: schema, groupContainer: .identifier(AppGroup.identifier))
            guard let localContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
                fatalError("Could not create a ModelContainer")
            }
            modelContainer = localContainer
        }

        let trackerStore = TrackerStore(modelContext: modelContainer.mainContext)
        _store = State(initialValue: trackerStore)
        CloudSyncWidgetRefresher.start(modelContainer: modelContainer)
        NotificationActionHandler.shared.register()
        StarlingRequestLogger.configure(container: modelContainer)

        #if os(iOS)
        WiggleRoomFont.installNavigationBarAppearance()
        // §5.3's 5-minute background refresh for Starling (and any future
        // auto-fetch provider) — registering the handler must happen here,
        // before the app finishes launching, not from anywhere later.
        BackgroundRefreshScheduler.register(container: modelContainer)
        BackgroundRefreshScheduler.scheduleNext()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(deepLinkRouter)
                .environment(appCommands)
                .tint(WiggleRoomColors.brand)
                // Nunito as the app-wide default; Fraunces is applied
                // explicitly to names and headlines.
                .font(.wiggleText(.body))
                .preferredColorScheme(selectedTheme.colorScheme)
                .task {
                    TrackerSpotlightIndexer.reindex()
                    await store.performManualEntryHousekeeping(after: .seconds(10))
                }
                .onOpenURL { url in
                    deepLinkRouter.handle(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Once per session, not every foreground — the
                    // duplicates this cleans up are a one-time artifact of
                    // a device's pre-CloudKit-import state (see
                    // `consolidateManualEntrySources`'s own doc comment),
                    // so there's nothing to gain from re-running it on
                    // every single activation, only repeated exposure to a
                    // real crash: a SwiftData/CloudKit race inside its
                    // plain `modelContext.fetch()`, hit and confirmed via a
                    // TestFlight crash report (`_assertionFailure` inside
                    // `ModelContext.register`, triggered from here). The
                    // `.task` above already covers the real "just launched"
                    // case with its own 10s delay.
                    guard newPhase == .active, !hasRunActivationHousekeeping else { return }
                    hasRunActivationHousekeeping = true
                    Task {
                        await store.performManualEntryHousekeeping(after: .seconds(3))
                    }
                }
                #if os(iOS)
                .onChange(of: scenePhase) { _, newPhase in
                    // A fired/expired background task doesn't reschedule
                    // itself, and only one request can be pending at a time
                    // — re-request on every backgrounding, which also
                    // covers the very first background after launch.
                    if newPhase == .background {
                        BackgroundRefreshScheduler.scheduleNext()
                        TrackerSpotlightIndexer.reindex()
                    }
                    // A tracker entering its final stretch by time alone has
                    // no reading to trigger its Live Activity (§8.5).
                    if newPhase == .active {
                        let trackers = (try? modelContainer.mainContext.fetch(FetchDescriptor<Tracker>())) ?? []
                        TrackerLiveActivity.syncAll(trackers)
                        // Apple Health is read from this device, once a day
                        // in the evening. `BGAppRefreshTask` may never fire,
                        // so activation is what makes that day's reading
                        // actually arrive — a local read with no network,
                        // rate limit or permission prompt behind it.
                        Task { await store.refreshDueDailySources() }
                    }
                }
                #endif
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
        // Every configurable thing in the app lives here — General (which
        // tracker the menu bar item shows) and Connected Sources both, as
        // of 2026-09-18 — rather than splitting configuration between
        // Settings and a submenu tucked inside the menu bar dropdown.
        // SettingsRootView is a fixed sidebar + inline content pane
        // (System Settings' own modern convention), replacing an earlier
        // icon-tab-bar TabView the same day, per explicit design direction.
        Settings {
            Group {
                if store.isResettingData {
                    ProgressView("Resetting app data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SettingsRootView()
                }
            }
                .font(.wiggleText(.body))
                .preferredColorScheme(selectedTheme.colorScheme)
                .environment(store)
                .modelContainer(modelContainer)
        }
        #endif

        #if os(macOS)
        MenuBarExtra {
            Group {
                if store.isResettingData {
                    ProgressView("Resetting…")
                        .padding()
                } else {
                    MenuBarStatusView()
                }
            }
                .font(.wiggleText(.body))
                .preferredColorScheme(selectedTheme.colorScheme)
                .environment(store)
                .modelContainer(modelContainer)
        } label: {
            Group {
                if store.isResettingData {
                    Text("Wiggle Room")
                } else {
                    MenuBarStatusLabel()
                }
            }
                .modelContainer(modelContainer)
        }
        // `.window`, not `.menu`: `.menu` renders this dropdown as a real
        // AppKit NSMenu, which forces any content that isn't a
        // Button/Toggle/Menu control (plain Text/VStack rows, here) into
        // AppKit's dimmed "informational item" style — the "everything's
        // greyed out" look reported 2026-09-18 — and can't host an
        // arbitrary custom view like RingsView at all. `.window` presents
        // genuine SwiftUI content in a floating panel instead, so both the
        // text and the rings render normally.
        .menuBarExtraStyle(.window)
        #endif
    }

    private var selectedTheme: AppThemePreference {
        AppThemePreference.resolved(from: appThemePreferenceRawValue)
    }
}
