//
//  ReminderScheduler.swift
//  WiggleRoom
//

import Foundation
import UserNotifications

/// Schedules/cancels the lightweight "log a new reading" local-notification
/// reminder a manual-entry tracker can opt into (§5.5), on a user-set
/// cadence (`Tracker.reminderCadenceMinutes`). Called from `TrackerStore`
/// whenever a tracker is added, edited, or deleted, so the scheduled
/// notification always reflects the tracker's current setting rather than
/// whatever it was when first created.
///
/// One repeating request per tracker, keyed by the tracker's own id, so
/// re-scheduling naturally replaces rather than duplicates a prior request.
enum ReminderScheduler {
    /// The OS-enforced floor for a repeating `UNTimeIntervalNotificationTrigger`
    /// — a request below this is silently coerced up to it, so "Every minute"
    /// sits right at the limit rather than under it.
    private static let minimumIntervalSeconds: TimeInterval = 60

    /// Category/action ids for the reminder's inline "Log Reading" text-input
    /// action, registered and handled by the app (`NotificationActionHandler`).
    static let categoryIdentifier = "TRACKER_REMINDER"
    static let logActionIdentifier = "LOG_READING"
    static let trackerIdKey = "trackerId"

    private static func identifier(for tracker: Tracker) -> String {
        "reminder-\(tracker.id.uuidString)"
    }

    /// Reflects `tracker.reminderCadenceMinutes` in the notification center:
    /// schedules a repeating reminder if a cadence is set (requesting
    /// notification authorization first, if not already determined),
    /// cancels any existing one otherwise. Only meaningful for a manual
    /// tracker that hasn't finished yet — a real provider's readings arrive
    /// on their own, and a completed tracker no longer accepts updates.
    static func sync(_ tracker: Tracker) {
        guard tracker.isManualEntry, !tracker.isCompleted(),
              let minutes = tracker.reminderCadenceMinutes, minutes > 0 else {
            cancel(tracker)
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = tracker.name
            content.body = "Time to update your current value."
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = [trackerIdKey: tracker.id.uuidString]

            // A calendar trigger can't express an arbitrary "every N minutes"
            // cadence (only regular calendar-component repeats like daily/
            // weekly), so a repeating time-interval trigger is used instead
            // — it re-fires every `minutes` minutes from whenever it's
            // scheduled.
            let interval = max(TimeInterval(minutes) * 60, minimumIntervalSeconds)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
            let request = UNNotificationRequest(identifier: identifier(for: tracker), content: content, trigger: trigger)

            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier(for: tracker)])
            center.add(request)
        }
    }

    /// Removes any scheduled reminder for this tracker — called on delete,
    /// or when `sync` finds no cadence set.
    static func cancel(_ tracker: Tracker) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: tracker)])
    }
}
