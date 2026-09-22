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
    /// rather than the placeholder "Tracker" text. Tries the shared picker
    /// cache (`TrackerListCache`) first — a cached-but-possibly-slightly-
    /// stale name is still a better result than blocking this interactive
    /// UI on a full CloudKit wait — and only falls back to that wait when
    /// the requested id(s) aren't in the cache yet (e.g. a tracker picked on
    /// another device moments ago that hasn't synced down here yet).
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
