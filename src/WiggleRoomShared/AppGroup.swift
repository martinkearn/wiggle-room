//
//  AppGroup.swift
//  WiggleRoom
//

import Foundation

/// The shared container every process's `ModelContainer` opens its local
/// SwiftData store inside, instead of each target's own private sandbox.
/// CloudKit still syncs data *across devices* exactly as before — this is
/// what makes processes *on the same device* (the phone app and its widget
/// extension; the watch app and its complication) read and write the
/// literal same on-disk file, so a change made in one is visible to the
/// other the instant it's asked for, with no CloudKit round-trip needed for
/// same-device freshness. Requires the matching
/// `com.apple.security.application-groups` entitlement on every target that
/// touches the store (`WiggleRoom`, `WiggleRoomWidgets`, `WiggleRoomWatch`,
/// `WiggleRoomComplication`) and the group registered against the Apple
/// Developer account.
enum AppGroup {
    static let identifier = "group.martinkearn.WiggleRoom"
}
