//
//  TrackerEntity.swift
//  Ringet
//

import AppIntents

/// The picker entry for a `Tracker` used by the app's own Shortcuts/Siri
/// intents. A separate, identically-shaped type exists in the RingetWidgets
/// extension (different module, same idea) — App Intents entities aren't
/// shared across extension boundaries, so each target that needs one
/// defines its own thin wrapper around the same underlying `Tracker` model.
struct TrackerEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tracker"
    static var defaultQuery = TrackerEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TrackerEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [TrackerEntity.ID]) async throws -> [TrackerEntity] {
        try IntentDataStore.fetchAllTrackers()
            .filter { identifiers.contains($0.id) }
            .map { TrackerEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TrackerEntity] {
        try IntentDataStore.fetchAllTrackers().map { TrackerEntity(id: $0.id, name: $0.name) }
    }
}
