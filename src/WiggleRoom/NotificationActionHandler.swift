//
//  NotificationActionHandler.swift
//  WiggleRoom
//

import Foundation
import UserNotifications

/// Handles the inline "Log Reading" text-input action on a manual tracker's
/// reminder notification (§5.4), so a reading can be logged straight from the
/// notification without opening the app.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActionHandler()

    func register() {
        let logAction = UNTextInputNotificationAction(
            identifier: ReminderScheduler.logActionIdentifier,
            title: "Log Reading",
            options: [],
            textInputButtonTitle: "Log",
            textInputPlaceholder: "Current value"
        )
        let category = UNNotificationCategory(
            identifier: ReminderScheduler.categoryIdentifier,
            actions: [logAction],
            intentIdentifiers: []
        )
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category])
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == ReminderScheduler.logActionIdentifier,
              let text = (response as? UNTextInputNotificationResponse)?.userText,
              let value = Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: .current),
              let idString = response.notification.request.content.userInfo[ReminderScheduler.trackerIdKey] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run {
            guard let tracker = try? IntentDataStore.fetchTracker(id: id),
                  tracker.isManualEntry, !tracker.isCompleted(),
                  let store = try? IntentDataStore.store() else { return }
            store.logReading(value: value, date: .now, for: tracker)
        }
    }
}
