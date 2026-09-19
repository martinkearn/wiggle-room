//
//  TrackerOrdering.swift
//  WiggleRoomShared
//

import Foundation

/// UserDefaults/`@AppStorage` key for the chosen `TrackerSortOption`
/// (per-device, like the menu bar tracker choice).
let trackerSortOptionKey = "trackerSortOption"

/// How the All Trackers list is ordered (Settings → Tracker Order).
/// `.custom` uses each tracker's synced `sortOrder`, set by drag-to-reorder.
enum TrackerSortOption: String, CaseIterable, Identifiable {
    case newestFirst, oldestFirst, endingSoonest, nameAscending, nameDescending, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        case .endingSoonest: "Ending Soonest"
        case .nameAscending: "Name (A–Z)"
        case .nameDescending: "Name (Z–A)"
        case .custom: "Custom"
        }
    }

    func sorted(_ trackers: [Tracker]) -> [Tracker] {
        switch self {
        case .newestFirst:
            trackers.sorted { $0.startDate > $1.startDate }
        case .oldestFirst:
            trackers.sorted { $0.startDate < $1.startDate }
        case .endingSoonest:
            trackers.sorted { $0.endDate < $1.endDate }
        case .nameAscending:
            trackers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending:
            trackers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .custom:
            // New trackers start at sortOrder 0, tying with the current
            // first item — newest start date wins, so they land on top.
            trackers.sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.startDate > $1.startDate }
        }
    }
}
