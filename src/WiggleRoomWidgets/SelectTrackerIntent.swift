//
//  SelectTrackerIntent.swift
//  WiggleRoomWidgets
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
    /// Resolves the tracker(s) a widget is *already* configured with — the
    /// call the system makes to show the current selection's real name
    /// (both in the "Edit Widget" sheet and the widget gallery summary)
    /// rather than the placeholder "Tracker" text. This needs the same
    /// generous CloudKit wait as `suggestedEntities()` below, not the
    /// short one `fetchAllTrackers()` gives the timeline provider — that
    /// shorter wait exists to protect WidgetKit's own render budget, which
    /// doesn't apply to this interactive, already-"Loading"-aware UI, and
    /// using it here was resolving too fast, before CloudKit had actually
    /// synced the tracker down to this extension's own local store, and
    /// falling back to the unresolved placeholder instead.
    @MainActor
    func entities(for identifiers: [TrackerEntity.ID]) async throws -> [TrackerEntity] {
        try await WidgetDataStore.fetchAllTrackersForConfiguration()
            .filter { identifiers.contains($0.id) }
            .map { TrackerEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TrackerEntity] {
        try await WidgetDataStore.fetchAllTrackersForConfiguration().map { TrackerEntity(id: $0.id, name: $0.name) }
    }
}

/// Per-widget-instance configuration: which tracker this particular widget
/// (Home Screen, Lock Screen, or Desktop instance) shows. Multiple widget
/// instances can each be configured independently, per the overnight brief —
/// e.g. one widget pinned to a money tracker, another to a mileage tracker.
struct SelectTrackerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a Tracker"
    static var description = IntentDescription("Choose which tracker this widget shows.")

    @Parameter(title: "Choose a tracker")
    var tracker: TrackerEntity?

    /// Renders the picker row as "Tracker: <name>" — or "Tracker: Choose a
    /// tracker" while nothing's selected (the parameter's own title is what
    /// the system shows as the unset placeholder).
    static var parameterSummary: some ParameterSummary {
        Summary("Tracker: \(\.$tracker)")
    }
}
