//
//  TrackerOrdering.swift
//  WiggleRoomShared
//

import Foundation

/// The All Trackers list order is one synced value per tracker
/// (`Tracker.sortOrder`), so a chosen order appears on every device.
/// Trackers that have never been arranged all have 0 and fall back to
/// newest-first; a brand new tracker (0) therefore lands on top.
enum TrackerOrdering {
    static func ordered(_ trackers: [Tracker]) -> [Tracker] {
        trackers.sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.startDate > $1.startDate }
    }
}

/// One-tap ways to arrange the list (Settings → Tracker Order); applying one
/// rewrites every tracker's synced `sortOrder`, after which drag-to-reorder
/// fine-tunes it.
enum TrackerArrangement: String, CaseIterable, Identifiable {
    case newestFirst, oldestFirst, endingSoonest, nameAscending, nameDescending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        case .endingSoonest: "Ending Soonest"
        case .nameAscending: "Name (A–Z)"
        case .nameDescending: "Name (Z–A)"
        }
    }

    func sorted(_ trackers: [Tracker]) -> [Tracker] {
        switch self {
        case .newestFirst: trackers.sorted { $0.startDate > $1.startDate }
        case .oldestFirst: trackers.sorted { $0.startDate < $1.startDate }
        case .endingSoonest: trackers.sorted { $0.endDate < $1.endDate }
        case .nameAscending: trackers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending: trackers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        }
    }
}
