//
//  WiggleRoomShortcuts.swift
//  WiggleRoom
//

import AppIntents

/// Registers Wiggle Room's App Intents as Siri/Shortcuts phrases (§ overnight
/// expansion — Shortcuts/Siri integration). Kept to the two actions that
/// make sense to trigger by voice/automation without the app open: logging
/// a reading, and checking a tracker's status.
struct WiggleRoomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogReadingIntent(),
            phrases: [
                "Log a reading in \(.applicationName)",
                "Update a tracker in \(.applicationName)",
            ],
            shortTitle: "Log a Reading",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ViewTrackerStatusIntent(),
            phrases: [
                "What's my \(.applicationName)",
                "What is my \(.applicationName)",
                "Check my \(.applicationName)",
                "How am I doing in \(.applicationName)",
                "Check my tracker in \(.applicationName)",
                "How's \(\.$tracker) in \(.applicationName)",
                "Check \(\.$tracker) in \(.applicationName)",
            ],
            shortTitle: "Check a Tracker",
            systemImageName: "circle.circle"
        )
    }
}
