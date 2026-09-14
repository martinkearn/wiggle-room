//
//  Tracker.swift
//  Ringet
//

import Foundation
import SwiftData

/// Whether a tracker's value depletes from a starting value (e.g. a bank
/// balance) or accumulates upward from a baseline (e.g. odometer mileage).
enum TrackerDirection: String, Codable, Hashable {
    case decreasing
    case increasing
}

/// A single tracker: a quantity that should move from `startingValue` toward
/// an end-of-period target at a steady pace. See spec §4.1.
///
/// Persisted via SwiftData with CloudKit sync (§6). CloudKit requires every
/// attribute to be optional or have a default, and every relationship to be
/// optional — hence the `= ...` defaults below even where a real tracker
/// always has a real value.
@Model
final class Tracker {
    var id: UUID = UUID()
    var name: String = ""
    var unit: String = ""
    var direction: TrackerDirection = TrackerDirection.decreasing
    var connectedSource: ConnectedSource?
    var sourceTargetId: String?
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var startingValue: Decimal = 0
    var totalAllowance: Decimal = 0

    /// Every reading ever logged for this tracker (§4.6 — timestamped
    /// history, not a single overwritten current value). Optional array for
    /// CloudKit compatibility; use `sortedReadings`/`latestReading` rather
    /// than reading this directly.
    @Relationship(deleteRule: .cascade, inverse: \ValueSnapshot.tracker)
    var readings: [ValueSnapshot]? = []

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        direction: TrackerDirection,
        connectedSource: ConnectedSource,
        sourceTargetId: String? = nil,
        startDate: Date,
        endDate: Date,
        startingValue: Decimal,
        totalAllowance: Decimal
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.direction = direction
        self.connectedSource = connectedSource
        self.sourceTargetId = sourceTargetId
        self.startDate = startDate
        self.endDate = endDate
        self.startingValue = startingValue
        self.totalAllowance = totalAllowance
        self.readings = []
    }
}

extension Tracker {
    /// All logged readings, oldest first.
    var sortedReadings: [ValueSnapshot] {
        (readings ?? []).sorted { $0.date < $1.date }
    }

    /// The most recently logged reading, if any.
    var latestReading: ValueSnapshot? {
        sortedReadings.last
    }
}

extension Tracker {
    /// Units that read as currency (symbol prefixed directly onto the
    /// number, e.g. "£1,234.56") rather than a suffix unit (e.g.
    /// "1,234 miles"). Anything not in this list is treated as a suffix
    /// unit.
    private static let currencySymbols: Set<String> = [
        "£", "$", "€", "¥", "₹", "₩", "₽", "₺", "₪", "R$", "kr", "Fr"
    ]

    var isCurrencyUnit: Bool {
        Tracker.currencySymbols.contains(unit)
    }

    /// Formats a value in this tracker's unit, placing a currency symbol on
    /// the left with no space (e.g. "£1,234.56") or any other unit on the
    /// right with a space (e.g. "1,234 miles"). `signed` prefixes a "+" for
    /// non-negative values (negative values always show their own "-").
    func formattedValue(_ value: Decimal, signed: Bool = false) -> String {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(0...2)))
        let sign: String
        if value < 0 {
            sign = "-"
        } else if signed {
            sign = "+"
        } else {
            sign = ""
        }
        return isCurrencyUnit ? "\(sign)\(unit)\(magnitude)" : "\(sign)\(magnitude) \(unit)"
    }
}
