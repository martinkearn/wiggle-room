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
    var tracker: Tracker?

    init(value: Decimal, date: Date) {
        self.value = value
        self.date = date
    }
}

// `@Model` also synthesises an `Identifiable` (persistentModelID); declare it explicitly
// so `ForEach`/`.sheet(item:)` use this stored `id` unambiguously.
extension ValueSnapshot: Identifiable {}
