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
struct GeneralSettingsView: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""

    var body: some View {
        Form {
            Section {
                if trackers.isEmpty {
                    Text("Add a tracker to choose one for the menu bar.")
                        .foregroundStyle(.secondary)
                } else {
                    // Empty-string tag matches `resolveMenuBarTracker`'s own
                    // fallback rule (`MenuBarStatusView.swift`): no tracker
                    // id is ever the empty string, so this option always
                    // means "fall back to most-recently-started" rather
                    // than pinning a specific tracker.
                    Picker("Show in Menu Bar", selection: $pinnedTrackerID) {
                        Text("Most Recently Started").tag("")
                        ForEach(trackers) { tracker in
                            Text(tracker.name).tag(tracker.id.uuidString)
                        }
                    }
                }
            } footer: {
                Text("Choose which tracker's rings and figures appear in the menu bar dropdown.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 200)
    }
}

#Preview {
    GeneralSettingsView()
        .modelContainer(PreviewData.container)
}
#endif
