//
//  SourceTarget.swift
//  WiggleRoom
//

import Foundation

/// A specific target within a `ConnectedSource` that a tracker can read
/// from — e.g. a Starling `accountUid`, a named manual log, or Apple
/// Health's body-mass measurement. See spec §5.1.
struct SourceTarget: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String

    /// The unit the caller wants this target's value in, as a
    /// `TrackerUnit` raw value — `nil` when the provider's values have only
    /// one possible unit, which is every provider except Apple Health.
    ///
    /// Health stores one body mass that can be read as kilograms or pounds,
    /// and a tracker's unit is editable after creation (kg ↔ lb is an
    /// ordinary edit on the Weight loss type), so the unit can't be encoded
    /// into `Tracker.sourceTargetId` the way Starling encodes an account and
    /// Space — it would go stale the moment the tracker was edited. It
    /// travels with the request instead. Optional and defaulted so Starling
    /// and Manual Entry are unaffected, and so an encoded target from an
    /// older build still decodes.
    let unit: String?

    init(id: String, displayName: String, unit: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
    }
}
