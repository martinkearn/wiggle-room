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

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tracker"
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
    /// type: this needs the same generous CloudKit wait as
    /// `suggestedEntities()` below, not the short one meant for the
    /// timeline provider's own render budget.
    @MainActor
    func entities(for identifiers: [TrackerEntity.ID]) async throws -> [TrackerEntity] {
        let real = try await WidgetDataStore.fetchAllTrackersForConfiguration()
            .filter { identifiers.contains($0.id) }
            .map { TrackerEntity(id: $0.id, name: $0.name) }
        return identifiers.contains(TrackerEntity.placeholder.id) ? [TrackerEntity.placeholder] + real : real
    }

    @MainActor
    func suggestedEntities() async throws -> [TrackerEntity] {
        try await WidgetDataStore.fetchAllTrackersForConfiguration().map { TrackerEntity(id: $0.id, name: $0.name) }
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
