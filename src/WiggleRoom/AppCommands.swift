//
//  AppCommands.swift
//  WiggleRoom
//

import Observation

/// Backs the macOS menu bar's File > New Tracker command (§7.2 parity —
/// macOS users expect a keyboard-driven "new item" the same way they'd get
/// one in Mail or Notes). Menu commands live at the `Scene` level, outside
/// any specific window's view hierarchy, so there's no view state to bind
/// the menu item to directly; `MacRootView` observes this instead.
///
/// An ever-incrementing count rather than a `Bool` — mirrors
/// `TrackerDetailView`'s `targetFlipCount` for the same reason: a second
/// request before the first sheet has dismissed must still register as a
/// distinct trigger, not silently no-op because the flag was already true.
@Observable
final class AppCommands {
    var newTrackerRequestCount = 0

    func requestNewTracker() {
        newTrackerRequestCount += 1
    }
}
