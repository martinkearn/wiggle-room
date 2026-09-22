//
//  SelectTrackerIntent.swift
//  WiggleRoomComplication
//

import AppIntents

/// The picker entry for a `Tracker` in the complication's edit-widget
/// configuration UI — a separate, identically-shaped type from the one in
/// `WiggleRoomWidgets` (different module, same idea): App Intents entities
/// aren't shared across extension boundaries, so each target that needs one
/// defines its own thin wrapper around the same underlying `Tracker` model.
struct TrackerEntity: AppEntity {
    let id: UUID
    let name: String

    /// What the system falls back to showing in the picker's value while it
    /// hasn't (or can't yet) resolve the selected entity — so "Choose a
    /// tracker", never the bare type name.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Choose a tracker"
    static var defaultQuery = TrackerEntityQuery()

    /// Stands in for "nothing chosen yet" so the picker row reads "Tracker:
    /// Choose a tracker" — the row's label is the parameter title, which has
    /// to be plain "Tracker". Never matches a real tracker; providers treat it
    /// like no selection (`selectedId`).
    static let placeholder = TrackerEntity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "Choose a tracker")
    static func selectedId(_ entity: TrackerEntity?) -> UUID? {
        entity.flatMap { $0.id == placeholder.id ? nil : $0.id }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TrackerEntityQuery: EntityQuery {
    /// Resolves the tracker(s) a complication is *already* configured
    /// with — see the matching comment in `WiggleRoomWidgets`' copy of this
    /// type. Tries the shared picker cache (`TrackerListCache`) first, since
    /// this is what resolves the current selection's real name in the "Edit
    /// Complication" UI, and the placeholder unresolved name is a worse
    /// result than a cached-but-possibly-slightly-stale one. Only falls back
    /// to the full CloudKit wait when the requested id(s) aren't in the
    /// cache yet (e.g. a tracker picked on another device moments ago).
    @MainActor
    func entities(for identifiers: [TrackerEntity.ID]) async throws -> [TrackerEntity] {
        // The placeholder needs no fetch — return it immediately so the picker
        // never waits on (or fails with) a CloudKit-backed lookup just to
        // say "Choose a tracker".
        if identifiers == [TrackerEntity.placeholder.id] { return [TrackerEntity.placeholder] }
        let requestedIds = identifiers.filter { $0 != TrackerEntity.placeholder.id }
        let cachedMatches = TrackerListCache.load()
            .filter { requestedIds.contains($0.id) }
            .map { TrackerEntity(id: $0.id, name: $0.name) }
        let real: [TrackerEntity]
        if cachedMatches.count == requestedIds.count {
            Task.detached(priority: .utility) {
                _ = try? await WidgetDataStore.fetchAllTrackersForConfiguration()
            }
            real = cachedMatches
        } else {
            real = try await WidgetDataStore.fetchAllTrackersForConfiguration()
                .filter { requestedIds.contains($0.id) }
                .map { TrackerEntity(id: $0.id, name: $0.name) }
        }
        return identifiers.contains(TrackerEntity.placeholder.id) ? [TrackerEntity.placeholder] + real : real
    }

    /// Cache-first: see `WidgetDataStore.fetchTrackerListForConfiguration()`
    /// for why this no longer blocks the picker on a full CloudKit wait.
    @MainActor
    func suggestedEntities() async throws -> [TrackerEntity] {
        try await WidgetDataStore.fetchTrackerListForConfiguration().map { TrackerEntity(id: $0.id, name: $0.name) }
    }
}

/// Which tracker a given complication instance shows — the watch face lets a
/// user place multiple instances of this complication, each independently
/// configured, same idea as the phone/Mac widgets (§8.1).
struct SelectTrackerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a Tracker"
    static var description = IntentDescription("Choose which tracker this complication shows.")

    @Parameter(title: "Tracker", default: TrackerEntity.placeholder)
    var tracker: TrackerEntity?

}
