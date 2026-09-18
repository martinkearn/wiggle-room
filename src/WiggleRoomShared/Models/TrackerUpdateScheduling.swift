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

    /// `BackgroundRefreshScheduler`'s three time-of-day cadence bands
    /// (§5.3) — foreground polling (`TrackerDetailView`) deliberately does
    /// *not* use this: a foreground session is short-lived by nature, so
    /// it just polls on load and every 45s flat, no time-of-day or trend
    /// logic. Background refresh is where the smarter scheduling lives,
    /// since it's the thing that would otherwise poll around the clock
    /// regardless of whether anyone's likely to be transacting.
    enum RefreshBand {
        /// 08:00–17:00 local — most transactions happen during the day.
        case peak
        /// 00:00–06:00 local — genuinely unlikely to see activity asleep.
        case offPeak
        /// Everything else (06:00–08:00, 17:00–24:00).
        case standard

        var interval: TimeInterval {
            switch self {
            case .peak: 5 * 60
            case .standard: 15 * 60
            case .offPeak: 60 * 60
            }
        }
    }

    /// Fixed clock windows, not anything adaptive/personalized — a blunt
    /// but predictable default.
    static func refreshBand(at date: Date = .now) -> RefreshBand {
        switch Calendar.current.component(.hour, from: date) {
        case 8..<17: .peak
        case 0..<6: .offPeak
        default: .standard
        }
    }

    /// More than one reading logged within the trailing `window` counts as
    /// an active burst (someone genuinely out and spending right now) —
    /// deliberately a real trailing time window, not "the last two polls
    /// happened to both find a change," since two transactions 20 minutes
    /// apart with several no-change polls in between are just as much a
    /// burst as two back-to-back ones. A tracker in a burst is scheduled
    /// at `RefreshBand.peak`'s cadence regardless of the actual time of
    /// day (§5.3) — on the reasoning that a real detected change is
    /// stronger evidence than the general time-of-day prior, even at
    /// 3am — but this only affects *that* tracker's own next-due
    /// calculation, never any other tracker's.
    static func isBursting(readings: [ValueSnapshot], asOf now: Date = .now, window: TimeInterval = 30 * 60) -> Bool {
        readings.filter { now.timeIntervalSince($0.date) <= window }.count > 1
    }

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
