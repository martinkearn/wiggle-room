//
//  AutoUpdateTicker.swift
//  WiggleRoom
//

import Foundation
import Observation
import Combine

/// Drives a view's "now" forward on a schedule aligned to the tracker(s) it's
/// showing (see `TrackerUpdateScheduling`), replacing the several ad hoc
/// `Timer.publish(every: 60...)` instances that used to live separately in
/// the dashboard, tracker list, watch detail view, and Mac root view. Each of
/// those ticked on a flat interval from whenever the view happened to
/// appear; this instead recomputes its next fire from the nearest relevant
/// tracker end date every time it fires, so the very last tick before a
/// tracker completes always lands exactly on that tracker's `endDate`.
///
/// Still polls once a second under the hood — the same trick the old
/// dashboard timer used (see the comment this replaced): a `let`-stored
/// `Timer.publish` is recreated on every SwiftUI body re-evaluation, so
/// anything longer than the interval between those recreations silently
/// never fires. A 1-second poll comparing against a stored "next aligned
/// fire" date sidesteps that without needing a live-updating timer at all.
@Observable
final class AutoUpdateTicker {
    private(set) var now = Date.now
    private(set) var secondsUntilNextUpdate = 0

    /// Supplies the end date(s) to align to, re-read every time the ticker
    /// reschedules — so it stays correct if the tracker(s) being shown
    /// change while the ticker is running. Empty means "nothing to align
    /// to," which falls back to a flat cadence of `interval` seconds.
    var endDatesProvider: () -> [Date] = { [] }

    /// The base cadence between updates, in seconds. Defaults to 60
    /// (display-recompute only, the prior behavior) — a caller that also
    /// fetches fresh data on every tick sets this to 30 (§5.3's decided
    /// foreground poll cadence, currently only the tracker detail screens).
    /// Widened automatically under Low Power Mode; see `effectiveInterval`.
    var interval: TimeInterval = 60

    /// `interval`, widened under Low Power Mode (§5.3's decided backoff) so
    /// a network-fetching ticker polls less aggressively on a low-battery
    /// device — display-only tickers (the default 60s interval, no fetch)
    /// still widen too, which is harmless since they have no network cost
    /// to save on, just a slightly less frequent display recompute.
    private var effectiveInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? interval * 3 : interval
    }

    /// Called every time `now` actually advances (not every second-poll) —
    /// the hook for side effects like a "just updated" flip animation or a
    /// completion check, which should only fire on a genuine update.
    var onUpdate: ((Date) -> Void)?

    private var nextUpdateAt = Date.now
    private var cancellable: AnyCancellable?

    init() {
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.poll(date) }
    }

    /// Call from `.onAppear` — sets `now` immediately and computes the first
    /// aligned fire from this exact moment, rather than from whatever
    /// default value existed before the view became visible.
    func start(now startDate: Date = .now) {
        now = startDate
        reschedule(after: startDate)
    }

    private func poll(_ date: Date) {
        secondsUntilNextUpdate = max(0, Int(nextUpdateAt.timeIntervalSince(date).rounded()))
        guard date >= nextUpdateAt else { return }
        now = date
        reschedule(after: date)
        onUpdate?(date)
    }

    private func reschedule(after date: Date) {
        let upcomingEndDates = endDatesProvider().filter { $0 > date }
        guard let nearestEnd = upcomingEndDates.min() else {
            nextUpdateAt = date.addingTimeInterval(effectiveInterval)
            return
        }
        nextUpdateAt = TrackerUpdateScheduling.nextUpdateDate(after: date, until: nearestEnd, interval: effectiveInterval)
    }
}
