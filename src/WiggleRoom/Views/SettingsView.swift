//
//  SettingsView.swift
//  WiggleRoom
//

#if !os(macOS)
import SwiftUI
import SwiftData

/// iOS Settings (§7.1): a List-based settings screen mirroring macOS's
/// sidebar structure (`SettingsRootView` — General + Connected Sources) so
/// admin/configuration features have one consistent home on both platforms
/// instead of accumulating on whichever screen happens to be nearby.
/// Added 2026-09-18 replacing a direct `ConnectedSourcesView` sheet —
/// Connected Sources is now one row within this screen rather than the
/// screen itself, matching macOS's own General/Connected Sources split.
///
/// Pushed (not a sheet) from `TrackerListView`'s toolbar gear icon, so it
/// gets the standard back arrow like the deeper Settings screens.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TrackerStore.self) private var store
    @State private var isPresentingResetConfirmation = false

    var body: some View {
        Group {
            List {
                Section {
                    NavigationLink {
                        ConnectedSourcesView()
                    } label: {
                        SettingsLabel(title: "Connected Sources", symbol: "point.3.filled.connected.trianglepath.dotted", colorIndex: 3)
                    }
                    NavigationLink {
                        TrackerOrderView()
                    } label: {
                        SettingsLabel(title: "Tracker Order", symbol: "arrow.up.arrow.down", colorIndex: 1)
                    }
                    NavigationLink {
                        SiriPhrasesView()
                    } label: {
                        SettingsLabel(title: "Siri Phrases", symbol: "waveform", colorIndex: 4)
                    }
                }

                Section {
                    Button("Reset App Data…", role: .destructive) {
                        isPresentingResetConfirmation = true
                    }
                } header: {
                    Text("Danger Zone")
                        .font(WiggleRoomFont.headline(15, weight: 650))
                } footer: {
                    // Same reasoning as macOS's copy of this feature
                    // (`GeneralSettingsView`) — see `TrackerStore
                    // .resetAllData()`'s own doc comment for why this
                    // exists at all.
                    Text("Permanently deletes every tracker, reading, and connected source — synced to every device. Cannot be undone.")
                }

                Section {
                    // Confirms this device is running the exact same code
                    // as another — see `AppBuildInfo`'s own doc comment for
                    // why this is a git commit hash, not a build date/time
                    // or version number.
                    LabeledContent("Build", value: AppBuildInfo.gitCommitDescription)
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .inlineNavigationBarIfAvailable()
        }
        .confirmationDialog(
            "Reset All App Data?",
            isPresented: $isPresentingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                store.resetAllData()
                dismiss()
            }
        } message: {
            Text("Deletes every tracker, reading, and connected source, on every device signed into this iCloud account. This can't be undone.")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
#endif
