//
//  PaceCrossingNotifier.swift
//  WiggleRoom
//

import Foundation
import UserNotifications

/// Posts a local notification when a tracker crosses from ahead-of/on-pace
/// to behind-pace, or back again (§7.2 — macOS only for now, since that's
/// the platform without an always-visible widget/complication already
/// covering this at a glance).
///
/// Tracks each tracker's last-known side of the ahead/behind line purely
/// in memory — good enough for "the app noticed a change while running";
/// it isn't meant to reconstruct history across a relaunch, since the
/// point is a timely heads-up, not an audit trail (readings themselves are
/// the durable record, per §4.6).
@MainActor
final class PaceCrossingNotifier {
    static let shared = PaceCrossingNotifier()

    private var lastKnownGoodStatus: [UUID: Bool] = [:]

    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Compares each tracker's current pace status against what it was the
    /// last time this ran, and notifies on any crossing. Trackers with no
    /// readings yet are skipped — there's no pace to have crossed.
    func checkForCrossings(in trackers: [Tracker]) {
        for tracker in trackers {
            guard let reading = tracker.latestReading else { continue }
            let pace = tracker.pace(actualValue: reading.value)
            let isGoodNow = pace.status == .good

            defer { lastKnownGoodStatus[tracker.id] = isGoodNow }

            guard let wasGood = lastKnownGoodStatus[tracker.id], wasGood != isGoodNow else { continue }
            notify(tracker: tracker, pace: pace, becameBehind: wasGood)
        }
    }

    private func notify(tracker: Tracker, pace: TrackerPace, becameBehind: Bool) {
        let content = UNMutableNotificationContent()
        content.title = tracker.name
        content.body = becameBehind
            ? "\(pace.statusLine(for: tracker)) \(pace.displayDifference(for: tracker))"
            : "Back on pace — \(pace.status.label(for: tracker))"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
