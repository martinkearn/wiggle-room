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
                        ZoomIndicator(tracker: tracker, now: PaceClock.shared.now)
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
///
/// The tracker's badge — its glyph in its own colour — and no figure. A
/// number sitting permanently in the menu bar is both the least glanceable
/// place to read one (no label, no context, and it changes width as it
/// changes) and the most conspicuous: every other app's status item is a
/// small icon. The figures are all still one click away in the dropdown,
/// which is where they have room to be labelled. This also drops the label's
/// dependency on `PaceClock`, so the status item no longer redraws on the
/// clock's tick — only when the tracker itself changes.
struct MenuBarStatusLabel: View {
    @Query(sort: \Tracker.startDate, order: .reverse) private var trackers: [Tracker]
    @AppStorage(menuBarTrackerIDKey) private var pinnedTrackerID: String = ""
    @Environment(\.colorScheme) private var colorScheme

    /// About the height AppKit allows a status item's image.
    private static let side: CGFloat = 18

    var body: some View {
        // The same `modelContext` guard the rest of the app carries: this
        // view is driven by a `@Query`, which republishes asynchronously
        // relative to a delete, so the resolved tracker can already be
        // detached — and reading a property of one is a hard SwiftData
        // crash rather than a catchable error.
        if let tracker = resolveMenuBarTracker(pinnedID: pinnedTrackerID, in: trackers),
           tracker.modelContext != nil,
           let badge = badgeImage(for: tracker) {
            Image(nsImage: badge)
                .accessibilityLabel("\(tracker.name), Wiggle Room")
        } else {
            // No trackers yet, or the badge could not be rendered — an empty
            // status item would look broken, so name the app instead.
            Text("Wiggle Room")
        }
    }

    /// Renders the tracker's badge to a bitmap rather than handing
    /// `MenuBarExtra` the SwiftUI view directly. A `MenuBarExtra` label is
    /// hosted by AppKit as a status item image, which is treated as a
    /// template — filled flat with the menu bar's own foreground colour —
    /// so the badge's colour, the whole point of showing it, would be lost.
    /// An `NSImage` with `isTemplate = false` keeps it.
    ///
    /// Deliberately not cached: the only inputs are the tracker's colour,
    /// glyph and the current appearance, this view redraws rarely now that
    /// it no longer follows the clock, and rendering an 18-point image is
    /// far cheaper than the invalidation a cache would need to get right.
    private func badgeImage(for tracker: Tracker) -> NSImage? {
        let renderer = ImageRenderer(
            content: TrackerBadge(tracker: tracker, size: Self.side)
                // `Color.dynamic` resolves against the appearance in force
                // while the image is being rendered, which is not the menu
                // bar's. Passing the scheme through explicitly — and reading
                // it from the environment above, so a change to it redraws
                // this view — keeps the badge matched to the menu bar it is
                // drawn in.
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}
#endif
