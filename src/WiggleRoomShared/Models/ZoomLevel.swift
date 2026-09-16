//
//  ZoomLevel.swift
//  WiggleRoom
//

import Foundation

/// A read-only lens on one unchanging tracker, re-scoping the ahead/behind
/// question to a shorter, calendar-aligned grain (§4.5). A long-running
/// tracker (e.g. a 3-year lease) has an outer pace ring that barely moves
/// day to day, so zoom levels let "how am I doing this month?" be asked
/// without redefining the tracker itself. Never creates or modifies a
/// `Tracker` record — see `Tracker.pace(actualValue:asOf:zoomLevel:)` and
/// `Tracker.subPeriod(for:asOf:)`.
enum ZoomLevel: String, CaseIterable, Identifiable, Codable {
    case overall
    case thisYear
    case thisMonth
    case thisWeek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overall: return "Overall"
        case .thisYear: return "This Year"
        case .thisMonth: return "This Month"
        case .thisWeek: return "This Week"
        }
    }
}
