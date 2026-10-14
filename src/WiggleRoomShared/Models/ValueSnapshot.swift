//
//  ValueSnapshot.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// A single timestamped reading obtained from a provider, auto-fetched or
/// manually logged. See spec §4.6 — history (not a single overwritten
/// current value) is required so the trend chart (§3.5) can plot how a
/// tracker's value actually moved over time.
@Model
final class ValueSnapshot {
    var id: UUID = UUID()
    var value: Decimal = 0
    var date: Date = Date.now
    /// Optional short comment on a reading, such as what a big jump was for.
    var note: String = ""
    var tracker: Tracker?

    init(id: UUID = UUID(), value: Decimal, date: Date, note: String = "") {
        self.id = id
        self.value = value
        self.date = date
        self.note = note
    }
}
