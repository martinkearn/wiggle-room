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
    /// experience instead of a flat "always an hour away" ceiling. `farInterval`
    /// is deliberately as tight as WidgetKit's shared per-app reload budget
    /// reasonably allows (5 minutes, not the original 15) — there's no App
    /// Group here (see `WidgetDataStore`), so this periodic reload plus the
    /// explicit `WidgetCenter.reloadAllTimelines()` triggers on every data
    /// change are the only two ways a widget ever catches up with the app;
    /// tightening this is the most impactful lever available without that
    /// larger architecture change.
    static func nextWidgetReloadDate(after now: Date, until endDate: Date, farInterval: TimeInterval = 300, nearInterval: TimeInterval = 60) -> Date {
        let interval = endDate.timeIntervalSince(now) <= 3600 ? nearInterval : farInterval
        return nextUpdateDate(after: now, until: endDate, interval: interval)
    }
}
