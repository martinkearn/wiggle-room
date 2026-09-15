//
//  MenuBarStatusView.swift
//  WiggleRoom
//

#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// macOS menu bar item (§7.2): a compact ahead/behind figure for one
/// tracker, color-coded per §3.2. With several trackers, shows the most
/// recently started one — a single pinned/default tracker rather than a
/// submenu, the simpler of the two options the spec leaves to the build's
/// judgment, good enough until real usage shows a submenu is worth it.
struct MenuBarStatusView: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    private var tracker: Tracker? { trackers.first }

    private var pace: TrackerPace? {
        guard let tracker else { return nil }
        return tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
    }

    var body: some View {
        if let tracker, let pace {
            VStack(alignment: .leading, spacing: 8) {
                Text(tracker.name)
                    .font(.headline)
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
                HStack {
                    Text(pace.status.label(for: tracker))
                    Spacer()
                    Text(pace.displayDifference(for: tracker))
                }
                .foregroundStyle(pace.status.color)
            }
            .font(.system(size: 12))
            .padding(12)
            .frame(width: 220)

            Divider()
        } else {
            Text("No trackers yet")
        }
        Button("Open Wiggle Room") {
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit Wiggle Room") {
            NSApp.terminate(nil)
        }
    }
}

/// The menu bar's own label — separate from the dropdown content above,
/// since `MenuBarExtra`'s label is evaluated outside the menu itself.
struct MenuBarStatusLabel: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]

    var body: some View {
        if let tracker = trackers.first {
            let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue)
            Text(pace.displayDifference(for: tracker))
        } else {
            Text("Wiggle Room")
        }
    }
}
#endif
