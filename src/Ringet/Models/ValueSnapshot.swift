//
//  ValueSnapshot.swift
//  Ringet
//

import Foundation

/// A single timestamped reading obtained from a provider, auto-fetched or
/// manually logged. See spec §4.6 — history (not a single overwritten
/// current value) is required so later zoom levels and trend charts can ask
/// "what was the value at the start of this sub-period?".
struct ValueSnapshot: Codable, Equatable {
    let value: Decimal
    let date: Date
}
