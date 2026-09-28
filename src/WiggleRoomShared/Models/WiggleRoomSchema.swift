//
//  WiggleRoomSchema.swift
//  WiggleRoom
//

import SwiftData

/// The one SwiftData schema every process opens its store with.
///
/// Every process sharing the App Group store and its CloudKit container
/// (`WiggleRoomApp`, `WidgetDataStore`, `IntentDataStore`,
/// `WiggleRoomWatchApp`) must use the identical schema: a mismatch between
/// processes sharing one on-disk/CloudKit store is a real corruption risk,
/// not just a compile-time detail. `CloudKitSchemaTests` reads it too, to
/// check every synced field is in the committed `cloudkit/schema.ckdb`.
///
/// Adding or renaming a stored property on any of these models changes the
/// CloudKit schema: update `cloudkit/schema.ckdb` and deploy the change to
/// Production before shipping (see the build spec, §10).
nonisolated enum WiggleRoomSchema {
    static var schema: Schema {
        Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self, StarlingRequestLogEntry.self])
    }
}
