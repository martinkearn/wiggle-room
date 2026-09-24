//
//  MenuBarStatusView.swift
//  WiggleRoom
//

#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// `UserDefaults` key for the user's chosen menu-bar tracker (§7.2) — a
/// per-Mac UI preference, not synced data, so it's a plain `@AppStorage`
/// value rather than anything routed through SwiftData/CloudKit. Not
/// `private`: `GeneralSettingsView` reads/writes the same key, since
/// choosing the menu bar tracker now lives in Settings (§7.2's 2026-09-18
/// "everything configurable belongs in Settings" pass) rather than in a
/// submenu inside the status item's own dropdown.
let menuBarTrackerIDKey = "menuBarTrackerID"

/// Resolves the tracker the menu bar should show: the user's explicit pin
/// if it still exists, falling back to the most-recently-started tracker
/// (the old, unconfigurable default) if nothing's pinned yet or the pinned
/// tracker was since deleted.
private func resolveMenuBarTracker(pinnedID: String, in trackers: [Tracker]) -> Tracker? {
    trackers.first(where: { $0.id.uuidString == pinnedID }) ?? trackers.first
}

/// macOS menu bar item (§7.2): the same two-ring visual as the iOS
/// dashboard/`TrackerDetailView`, plus the ahead/behind figure, for one
/// tracker. Defaults to the most recently started tracker; which tracker to
/// pin instead is chosen in **Settings → General** (`GeneralSettingsView`),
/// not from a submenu here — a glanceable status-item dropdown shouldn't
/// double as a configuration surface, and every other configurable thing in
/// the app (Connected Sources) already lives in Settings, so this matches.
///
/// Presented via `.menuBarExtraStyle(.window)` (`WiggleRoomApp.swift`), not
/// `.menu` — `.menu` renders this as a real AppKit `NSMenu`, which (a)
/// forces any non-control content (the plain Text/VStack rows below) into
/// AppKit's dimmed "informational item" style, reported 2026-09-18 as
/// "everything's greyed out", and (b) can't host an arbitrary custom view
/// like `RingsView` at all. `.window` content is genuine SwiftUI in a
/// floating panel, so both render normally.
struct MenuBarStatusView: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""

    private var tracker: Tracker? {
        resolveMenuBarTracker(pinnedID: pinnedTrackerID, in: trackers)
    }

    private var pace: TrackerPace? {
        guard let tracker else { return nil }
        return tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: PaceClock.shared.now)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let tracker, let pace {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TrackerBadge(tracker: tracker, size: 26)
                        Text(tracker.name)
                            .font(WiggleRoomFont.headline(17, weight: 650))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    // showsStatusLabel: false — the status word ("JUST OVER
                    // BUDGET") is redundant here since it's repeated in the
                    // rows directly below the ring, but the number itself
                    // isn't shown anywhere else in this compact dropdown,
                    // so it stays.
                    RingsView(tracker: tracker, now: PaceClock.shared.now, lineWidth: 14, showsStatusLabel: false)
                        .frame(width: 132, height: 132)
                        .padding(8)
                        .background(
                            Circle().fill(RadialGradient(
                                colors: [tracker.accentColor.opacity(0.24), .clear],
                                center: .center, startRadius: 20, endRadius: 100
                            ))
                        )
                    VStack(spacing: 6) {
                        HStack {
                            Text(tracker.terminology.currentFigure)
                                .font(WiggleRoomFont.cardLabel)
                            Spacer()
                            Text(tracker.formattedValue(pace.currentValue))
                                .font(.wiggleNumber(size: 13, weight: .bold))
                                .foregroundStyle(pace.status.color)
                        }
                        HStack {
                            Text(tracker.terminology.paceFigure)
                                .font(WiggleRoomFont.cardLabel)
                            Spacer()
                            Text(tracker.formattedValue(pace.targetValueToday))
                                .font(.wiggleNumber(size: 13, weight: .bold))
                        }
                    }
                    .padding(10)
                    .trackerCard(tracker, variant: 1)
                }
                .padding(16)
            } else {
                VStack(spacing: 10) {
                    EmptyRingsMark(size: 72)
                    Text("No trackers yet")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }

            Divider()

            // Each row is explicitly stretched to the full width and
            // left-aligned — a Button/Menu's own label otherwise just sizes
            // to fit its text and centers within that, so the VStack's
            // `alignment: .leading` alone doesn't produce the flush-left,
            // native-menu-like look these rows are going for.
            VStack(alignment: .leading, spacing: 2) {
                Button("Open Wiggle Room") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .frame(width: 240)
    }
}

/// The menu bar's own label — separate from the dropdown content above,
/// since `MenuBarExtra`'s label is evaluated outside the menu itself.
struct MenuBarStatusLabel: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""

    var body: some View {
        if let tracker = resolveMenuBarTracker(pinnedID: pinnedTrackerID, in: trackers) {
            let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: PaceClock.shared.now)
            Text(pace.displayDifference(for: tracker))
        } else {
            Text("Wiggle Room")
        }
    }
}
#endif
