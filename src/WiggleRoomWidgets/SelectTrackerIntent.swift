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
        // The placeholder needs no fetch — return it immediately so the picker
        // never waits on (or fails with) a CloudKit-backed lookup just to
        // say "Choose a tracker".
        if identifiers == [TrackerEntity.placeholder.id] { return [TrackerEntity.placeholder] }
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

/// Per-widget-instance configuration: which tracker this particular widget
/// (Home Screen, Lock Screen, or Desktop instance) shows. Multiple widget
/// instances can each be configured independently, per the overnight brief —
/// e.g. one widget pinned to a money tracker, another to a mileage tracker.
struct SelectTrackerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a Tracker"
    static var description = IntentDescription("Choose which tracker this widget shows.")

    @Parameter(title: "Tracker", default: TrackerEntity.placeholder)
    var tracker: TrackerEntity?

}
