//
//  TrackerUpdateScheduling.swift
//  WiggleRoom
//

import Foundation

/// A single, shared answer to "when should figures next be recomputed?" —
/// used to drive the app's live-updating dashboard/list timers and the
/// widget/complication timeline reload policy alike, so both are governed by
/// the same rule rather than each picking its own interval. Deliberately a
/// pure function with no dependency on `Timer`/`WidgetKit`/SwiftUI: this is
/// also the scheduling shape a future background fetch (for a real connected
/// source like Starling or Tesla — "when should we next poll?") can reuse
/// directly.
enum TrackerUpdateScheduling {
    static let defaultWidgetFarInterval: TimeInterval = 300

    /// The next moment a display should refresh, walking backward from
    /// `endDate` in `interval`-second steps rather than forward from `now` —
    /// so ticks are anchored to *when the tracker ends*, and the very last
    /// tick always lands exactly on `endDate` instead of possibly
    /// overshooting it by up to `interval` seconds. Returns `endDate` itself
    /// once `now` is at or past it (nothing left to align to).
    static func nextUpdateDate(after now: Date, until endDate: Date, interval: TimeInterval = 60) -> Date {
        guard now < endDate, interval > 0 else { return endDate }
        let remaining = endDate.timeIntervalSince(now)
        let ticksRemaining = (remaining / interval).rounded(.up)
        let candidate = endDate.addingTimeInterval(-(ticksRemaining - 1) * interval)
        // Guards against floating-point rounding landing the candidate at or
        // before `now` (e.g. `remaining` a hair above an exact multiple of
        // `interval`) — always make forward progress.
        return max(candidate, now.addingTimeInterval(0.001))
    }

    /// The next reload moment for a widget/complication timeline: a
    /// budget-friendly cadence while the tracker still has plenty of time
    /// left, tightening to `interval` once inside the final hour so the last
    /// reload coincides with the tracker's own end — matching the in-app
    /// experience instead of a flat "always an hour away" ceiling. App Group
    /// storage keeps same-device app/widget data fresh; `farInterval` controls
    /// the periodic reload policy, especially for cross-device CloudKit updates
    /// and elapsed-time recomputes when no explicit reload was triggered.
    static func nextWidgetReloadDate(after now: Date, until endDate: Date, farInterval: TimeInterval = defaultWidgetFarInterval, nearInterval: TimeInterval = 60) -> Date {
        let interval = endDate.timeIntervalSince(now) <= 3600 ? nearInterval : farInterval
        return nextUpdateDate(after: now, until: endDate, interval: interval)
    }
}
