//
//  StarlingRequestLogEntry.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// One timestamped record of a single real Starling API request made by
/// this app, from any of the user's own devices — synced via CloudKit
/// exactly like every other piece of data (§6), so "Starling Requests
/// Today" (Settings → General on macOS, the Connected Source detail
/// screen on iOS) reflects usage across every device signed into the same
/// iCloud account and sharing the same synced Starling token, not just
/// whichever device happens to be open right now.
///
/// Deliberately a separate record per request, inserted and never
/// mutated, rather than a single counter field incremented in place — a
/// shared mutable counter is exactly the shape of data CloudKit's
/// last-writer-wins conflict resolution silently corrupts: two devices
/// each incrementing their own local copy at nearly the same moment would
/// resolve to whichever write landed last, quietly dropping the other
/// device's requests from the total. A set of independent inserts merges
/// additively instead, with no conflict possible — the same reasoning
/// `ValueSnapshot` already relies on for reading history (§4.6/§6).
///
/// Queried live via `@Query` wherever it's displayed (never through an
/// actor round-trip) so the figure updates automatically as CloudKit sync
/// delivers another device's requests, the same idiomatic pattern every
/// other list in this app already uses.
@Model
final class StarlingRequestLogEntry {
    var date: Date = Date.now

    init(date: Date = .now) {
        self.date = date
    }
}
