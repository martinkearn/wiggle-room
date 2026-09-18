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
/// value rather than anything routed through SwiftData/CloudKit.
private let menuBarTrackerIDKey = "menuBarTrackerID"

/// Resolves the tracker the menu bar should show: the user's explicit pin
/// if it still exists, falling back to the most-recently-started tracker
/// (the old, unconfigurable default) if nothing's pinned yet or the pinned
/// tracker was since deleted.
private func resolveMenuBarTracker(pinnedID: String, in trackers: [Tracker]) -> Tracker? {
    trackers.first(where: { $0.id.uuidString == pinnedID }) ?? trackers.first
}

/// macOS menu bar item (§7.2): the same two-ring visual as the iOS
/// dashboard/`TrackerDetailView`, plus the ahead/behind figure, for one
/// tracker. Defaults to the most recently started tracker, but the user can
/// pin a specific one via the "Show in Menu Bar" submenu below — a single
/// pinned tracker rather than a submenu of full dashboards, the simpler of
/// the two options the spec leaves to the build's judgment, good enough
/// until real usage shows more is needed.
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
        return tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let tracker, let pace {
                VStack(spacing: 12) {
                    Text(tracker.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    RingsView(tracker: tracker, now: .now, lineWidth: 14)
                        .frame(width: 132, height: 132)

                    // No separate status-label/difference row here — the
                    // ring's own center content (RingsView) already shows
                    // both, so repeating them below would just duplicate
                    // what's already on screen a few pixels up.
                    VStack(spacing: 6) {
                        HStack {
                            Text(tracker.currentValueLabel)
                            Spacer()
                            Text(tracker.formattedValue(pace.currentValue))
                        }
                        HStack {
                            Text("Target Right Now")
                            Spacer()
                            Text(tracker.formattedValue(pace.targetValueToday))
                        }
                    }
                    .font(.system(size: 12))
                }
                .padding(16)
            } else {
                Text("No trackers yet")
                    .foregroundStyle(.secondary)
                    .padding(16)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                if trackers.count > 1 {
                    Menu("Show in Menu Bar") {
                        ForEach(trackers) { candidate in
                            Button {
                                pinnedTrackerID = candidate.id.uuidString
                            } label: {
                                if candidate.id == tracker?.id {
                                    Label(candidate.name, systemImage: "checkmark")
                                } else {
                                    Text(candidate.name)
                                }
                            }
                        }
                    }
                }
                Button("Open Wiggle Room") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Quit Wiggle Room") {
                    NSApp.terminate(nil)
                }
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
            let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
            Text(pace.displayDifference(for: tracker))
        } else {
            Text("Wiggle Room")
        }
    }
}
#endif
