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
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""
    @State private var starlingStatus: StarlingRequestBudget.Status?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("General")
                .font(.title2.weight(.semibold))

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
                    Text("Choose which tracker's rings and figures appear in the menu bar dropdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            starlingRateLimitSection

            Spacer()
        }
        .task { await refreshStarlingStatus() }
    }

    /// Rate-limit insight (§5.3/§12) — the budget itself (`StarlingRequestBudget`,
    /// shared app-wide across every Starling connection, not per-source)
    /// was previously invisible short of a paused-refresh error on whatever
    /// tracker happened to be open when it hit. Real usage showed the rate
    /// limit being hit more than expected, with no way to see why.
    private var starlingRateLimitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Starling Requests Today")
                Spacer()
                if let starlingStatus {
                    Text("\(starlingStatus.requestsInLast24Hours) / \(starlingStatus.dailyLimit)")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await refreshStarlingStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            if let cooldownUntil = starlingStatus?.cooldownUntil {
                Text("Paused until \(cooldownUntil.formatted(Self.timeFormatter)) after hitting Starling's rate limit.")
                    .font(.caption)
                    .foregroundStyle(WiggleRoomColors.warning)
            } else {
                Text("Counts every request across all Starling-connected trackers over the last 24 hours (resets when the app relaunches, not a true rolling 24h count).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let timeFormatter: Date.FormatStyle = .init().hour().minute()

    private func refreshStarlingStatus() async {
        starlingStatus = await StarlingProvider.sharedBudget.status
    }
}

#Preview {
    GeneralSettingsView()
        .modelContainer(PreviewData.container)
        .frame(width: 640, height: 440)
}
#endif
