//
//  GeneralSettingsView.swift
//  WiggleRoom
//

#if os(macOS)
import SwiftUI
import SwiftData

/// Settings → General (§7.2): macOS configuration that isn't tied to a
/// specific tracker or connected source. Currently just which tracker the
/// menu bar item pins — moved here (2026-09-18) from a "Show in Menu Bar"
/// submenu inside the menu bar dropdown itself, so every configurable
/// thing in the app lives in one place (Settings), the same way Connected
/// Sources already does, rather than a glanceable status-item dropdown
/// also doubling as a settings surface.
///
/// Plain content laid directly into `SettingsRootView`'s sidebar-detail
/// pane — no `Form`/`NavigationStack` chrome of its own, since that scene
/// structure moved to `SettingsRootView` when the window switched from a
/// `TabView` to a fixed sidebar (2026-09-18).
struct GeneralSettingsView: View {
    @Environment(TrackerStore.self) private var store
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""
    @State private var isPresentingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(WiggleRoomFont.headline(22, weight: 650))

            if trackers.isEmpty {
                Text("Add a tracker to choose one for the menu bar.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Show in Menu Bar")
                        Spacer()
                        // Empty-string tag matches `resolveMenuBarTracker`'s
                        // own fallback rule (`MenuBarStatusView.swift`): no
                        // tracker id is ever the empty string, so this
                        // option always means "fall back to
                        // most-recently-started" rather than pinning a
                        // specific tracker.
                        Picker("", selection: $pinnedTrackerID) {
                            Text("Most Recently Started").tag("")
                            ForEach(trackers) { tracker in
                                Text(tracker.name).tag(tracker.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    Text("Choose which tracker shows in the menu bar.")
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            dangerZoneSection

            Divider()

            buildInfoSection

            Spacer()
        }
        .confirmationDialog(
            "Reset All App Data?",
            isPresented: $isPresentingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                Task { await store.resetAllData() }
            }
        } message: {
            Text("Clears everything on every device signed in to this iCloud account. This can't be undone.")
        }
        .alert("Reset Failed", isPresented: resetErrorBinding) {
            Button("OK") { store.clearResetError() }
        } message: {
            Text(store.resetErrorDescription ?? "The app data could not be reset.")
        }
    }

    /// A deliberate, explicit escape hatch — see `TrackerStore.resetAllData()`'s
    /// own doc comment for why this exists at all (a real data-corruption
    /// incident, 2026-09-18) rather than being a routine feature.
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Danger Zone")
                .font(WiggleRoomFont.headline(15, weight: 650))
                .foregroundStyle(WiggleRoomColors.error)
            Button("Reset App Data…", role: .destructive) {
                isPresentingResetConfirmation = true
            }
            Text("Clears every tracker, reading and source on all your devices. This can't be undone.")
                .font(.wiggleText(.caption))
                .foregroundStyle(.secondary)
        }
    }

    /// Confirms this device is running the exact same code as another —
    /// see `AppBuildInfo`'s own doc comment for why this is a git commit
    /// hash, not a build date/time or version number.
    private var buildInfoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Build \(AppBuildInfo.gitCommitDescription)")
                .font(.wiggleText(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private var resetErrorBinding: Binding<Bool> {
        Binding(
            get: { store.resetErrorDescription != nil },
            set: { if !$0 { store.clearResetError() } }
        )
    }
}

#Preview {
    GeneralSettingsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .frame(width: 640, height: 440)
}
#endif
