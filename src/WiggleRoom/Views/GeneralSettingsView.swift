//
//  GeneralSettingsView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

private let appThemePreferenceDescription: LocalizedStringKey =
    "Choose whether Wiggle Room follows the system appearance or always uses light or dark mode."

/// Settings → General (§7): configuration that isn't tied to a specific
/// tracker or connected source. On macOS it also owns which tracker the
/// menu bar item pins — moved here (2026-09-18) from a "Show in Menu Bar"
/// submenu inside the menu bar dropdown itself.
///
/// Plain content laid directly into `SettingsRootView`'s sidebar-detail
/// pane — no `Form`/`NavigationStack` chrome of its own, since that scene
/// structure moved to `SettingsRootView` when the window switched from a
/// `TabView` to a fixed sidebar (2026-09-18). On iOS this same view is
/// pushed from `SettingsView` and renders as a standard settings `Form`.
struct GeneralSettingsView: View {
    @AppStorage(appThemePreferenceKey) private var appThemePreferenceRawValue = AppThemePreference.system.rawValue
    #if os(macOS)
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""
    #endif

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(WiggleRoomFont.headline(22, weight: 650))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Appearance")
                    Spacer()
                    themePicker
                        .labelsHidden()
                        .frame(width: 240)
                }
                themeDescription
            }

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

            Spacer()
        }
        #else
        Form {
            Section {
                themePicker
            } footer: {
                themeDescription
            }
        }
        .navigationTitle("General")
        .inlineNavigationBarIfAvailable()
        #endif
    }

    private var themePicker: some View {
        Picker("Appearance", selection: $appThemePreferenceRawValue) {
            ForEach(AppThemePreference.allCases) { theme in
                Text(theme.displayName).tag(theme.rawValue)
            }
        }
    }

    private var themeDescription: some View {
        Text(appThemePreferenceDescription)
            .font(.wiggleText(.caption))
            .foregroundStyle(.secondary)
    }
}

#if os(macOS)
#Preview {
    GeneralSettingsView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .frame(width: 640, height: 440)
}
#endif
