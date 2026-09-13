//
//  Tracker.swift
//  Ringet
//

import Foundation

/// Whether a tracker's value depletes from a starting value (e.g. a bank
/// balance) or accumulates upward from a baseline (e.g. odometer mileage).
enum TrackerDirection: String, Codable, Equatable {
    case decreasing
    case increasing
}

/// Placeholder for the recurrence rule design in spec §4.4, which is a later
/// build phase. Present now only so `Tracker.recurrence` has a concrete type.
struct RecurrenceRule: Codable, Equatable {
}

/// A single tracker: a quantity that should move from `startingValue` toward
/// an end-of-period target at a steady pace. See spec §4.1.
struct Tracker: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var unit: String
    var direction: TrackerDirection
    var connectedSourceId: UUID
    var sourceTargetId: String?
    var startDate: Date
    var endDate: Date
    var startingValue: Decimal
    var totalAllowance: Decimal
    var recurrence: RecurrenceRule?

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        direction: TrackerDirection,
        connectedSourceId: UUID,
        sourceTargetId: String? = nil,
        startDate: Date,
        endDate: Date,
        startingValue: Decimal,
        totalAllowance: Decimal,
        recurrence: RecurrenceRule? = nil
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.direction = direction
        self.connectedSourceId = connectedSourceId
        self.sourceTargetId = sourceTargetId
        self.startDate = startDate
        self.endDate = endDate
        self.startingValue = startingValue
        self.totalAllowance = totalAllowance
        self.recurrence = recurrence
    }
}
