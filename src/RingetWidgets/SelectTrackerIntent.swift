//
//  SelectTrackerIntent.swift
//  RingetWidgets
//

import AppIntents

/// The picker entry for a `Tracker` in the widget's edit-widget configuration
/// UI — App Intents needs its own lightweight entity type here rather than
/// exposing the `@Model` class directly.
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
        try await WidgetDataStore.fetchAllTrackers()
            .filter { identifiers.contains($0.id) }
            .map { TrackerEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TrackerEntity] {
        try await WidgetDataStore.fetchAllTrackers().map { TrackerEntity(id: $0.id, name: $0.name) }
    }
}

/// Per-widget-instance configuration: which tracker this particular widget
/// (Home Screen, Lock Screen, or Desktop instance) shows. Multiple widget
/// instances can each be configured independently, per the overnight brief —
/// e.g. one widget pinned to a money tracker, another to a mileage tracker.
struct SelectTrackerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Tracker"
    static var description = IntentDescription("Choose which tracker this widget shows.")

    @Parameter(title: "Tracker")
    var tracker: TrackerEntity?
}
