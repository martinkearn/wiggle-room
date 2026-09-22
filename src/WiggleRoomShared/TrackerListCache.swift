//
//  TrackerListCache.swift
//  WiggleRoomShared
//

import Foundation

/// A tiny "last known good" snapshot of every tracker's id + name, written to
/// the shared App Group container so the interactive "choose a tracker"
/// picker (the widget/complication configuration UI, via `WidgetDataStore`)
/// can show a list instantly instead of always blocking behind
/// `fetchAllTrackersForConfiguration()`'s CloudKit import wait — the cause of
/// the picker's long "Loading" state and, on watchOS, the system's own
/// picker timeout bouncing the user back to the edit screen before that wait
/// finishes. Not a source of truth: every process that already does a real
/// fetch (the main app on a mutation, the watch app, either widget/
/// complication extension) refreshes it opportunistically, so it's usually
/// only stale by however long it's been since the last such fetch anywhere.
enum TrackerListCache {
    struct Entry: Codable, Equatable {
        let id: UUID
        let name: String
    }

    private static let fileName = "tracker-list-cache.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent(fileName)
    }

    /// Best-effort and silent on failure — a missed cache write just means
    /// the next picker open falls back to the full CloudKit wait, not a
    /// correctness problem, so this deliberately never throws.
    static func save(_ trackers: [Tracker]) {
        guard let fileURL, !trackers.isEmpty else { return }
        let entries = trackers.map { Entry(id: $0.id, name: $0.name) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Empty when no process has ever written a non-empty snapshot yet (a
    /// fresh install, or a fresh Simulator/App Group container) — callers
    /// fall back to a real fetch in that case.
    static func load() -> [Entry] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
