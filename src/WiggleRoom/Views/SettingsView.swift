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
    var body: some View {
        List {
            // One Section holding every settings menu row — splitting these
            // into a Section apiece (as a prior change did) adds a full
            // section gap between each row, which reads as broken spacing
            // rather than deliberate grouping.
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
                NavigationLink {
                    CloudSyncDiagnosticsView()
                } label: {
                    SettingsLabel(title: "CloudKit Sync", symbol: "icloud", colorIndex: 5)
                }
                // Last in the list, own red glyph — see `DangerZoneView`'s
                // own doc comment for why it's a separate top-level menu
                // rather than living inline here.
                NavigationLink {
                    DangerZoneView()
                } label: {
                    SettingsLabel(title: "Danger Zone", symbol: "exclamationmark.triangle.fill", color: WiggleRoomColors.bad)
                }
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
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
#endif
