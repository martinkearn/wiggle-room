//
//  ValueSnapshot.swift
//  Ringet
//

import Foundation
import SwiftData

/// A single timestamped reading obtained from a provider, auto-fetched or
/// manually logged. See spec §4.6 — history (not a single overwritten
/// current value) is required so later zoom levels and trend charts can ask
/// "what was the value at the start of this sub-period?".
@Model
final class ValueSnapshot {
    var id: UUID = UUID()
    var value: Decimal = 0
    var date: Date = Date.now
    var tracker: Tracker?

    init(value: Decimal, date: Date) {
        self.value = value
        self.date = date
    }
}
