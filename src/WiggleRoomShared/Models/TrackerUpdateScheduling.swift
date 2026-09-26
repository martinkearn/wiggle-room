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
/// also the scheduling shape a background fetch for a real connected source
/// reuses directly — "when should we next poll?" — per provider, via
/// `SourcePollPolicy`.
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
    static func refreshBand(at date: Date = .now, calendar: Calendar = .current) -> RefreshBand {
        switch calendar.component(.hour, from: date) {
        case 8..<17: .peak
        case 0..<6: .offPeak
        default: .standard
        }
    }

    /// How often a tracker's source should be polled in the background,
    /// chosen from the provider behind it rather than assumed. "As often as
    /// the bands allow" is right for a bank balance and wrong for a bathroom
    /// scale.
    enum SourcePollPolicy: Equatable {
        /// Starling, and any other source whose value can move at any
        /// moment: the time-of-day bands above, plus burst detection.
        case transactional
        /// Apple Health: once per local day, at or after `hour`. Most people
        /// weigh themselves in the morning, so one evening read catches the
        /// day's weight without polling around the clock in the hope of
        /// finding it.
        case dailyEvening(hour: Int)
    }

    /// The evening hour Apple Health is read at — late enough to have caught
    /// a morning weigh-in, early enough not to be tomorrow's reading.
    static let healthKitPollHour = 20

    static func pollPolicy(forProviderId providerId: String?) -> SourcePollPolicy {
        switch providerId {
        case "healthkit": .dailyEvening(hour: healthKitPollHour)
        default: .transactional
        }
    }

    /// Seconds until a tracker is next due for a background poll under
    /// `policy`, 0 when it's due right now. Never attempted before
    /// (`lastAttempt` is `nil`) counts as maximally overdue either way.
    static func timeUntilDue(
        policy: SourcePollPolicy,
        lastAttempt: Date?,
        readings: [ValueSnapshot],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> TimeInterval {
        switch policy {
        case .transactional:
            // This tracker's own effective band right now — `peak`'s cadence
            // while it's individually bursting, regardless of the actual time
            // of day, otherwise whatever the clock says.
            let band = isBursting(readings: readings, asOf: now) ? RefreshBand.peak : refreshBand(at: now, calendar: calendar)
            return max(0, band.interval - now.timeIntervalSince(lastAttempt ?? .distantPast))
        case .dailyEvening(let hour):
            // Due when the most recent daily slot at or before now hasn't
            // been claimed yet, which also handles catching up: a device
            // that was off for three days is due immediately rather than
            // waiting for the next evening to come round. Burst detection
            // deliberately plays no part — two weigh-ins half an hour apart
            // are no reason to start polling every five minutes.
            let slot = mostRecentDailySlot(hour: hour, asOf: now, calendar: calendar)
            guard (lastAttempt ?? .distantPast) >= slot else { return 0 }
            let nextSlot = calendar.date(byAdding: .day, value: 1, to: slot) ?? slot.addingTimeInterval(24 * 60 * 60)
            return max(0, nextSlot.timeIntervalSince(now))
        }
    }

    /// Today's `hour`:00 local once it has passed, otherwise yesterday's.
    ///
    /// Built from date components and `Calendar` arithmetic rather than
    /// 24-hour maths, so a daylight-saving change shifts the slot with the
    /// clock instead of sliding it an hour off. Deliberately not
    /// `date(bySettingHour:of:)`, which searches *forward* by default and so
    /// hands back tomorrow's slot when today's has already passed — the exact
    /// case this function exists to answer.
    static func mostRecentDailySlot(hour: Int, asOf now: Date = .now, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let today = calendar.date(from: components) else { return now }
        guard today > now else { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-24 * 60 * 60)
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
