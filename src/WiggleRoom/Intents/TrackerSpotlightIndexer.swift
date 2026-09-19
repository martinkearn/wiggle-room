//
//  TrackerSpotlightIndexer.swift
//  WiggleRoom
//

import AppIntents
import CoreSpotlight

/// Keeps Spotlight's index of trackers (`TrackerEntity` is an `IndexedEntity`)
/// matching the store. Replaces the whole set each time rather than diffing —
/// there are only ever a handful of trackers, and it makes deletes and
/// renames correct for free.
enum TrackerSpotlightIndexer {
    @MainActor
    static func reindex() {
        guard let trackers = try? IntentDataStore.fetchAllTrackers() else { return }
        let entities = trackers.map { TrackerEntity(id: $0.id, name: $0.name) }
        Task {
            let index = CSSearchableIndex.default()
            try? await index.deleteAppEntities(ofType: TrackerEntity.self)
            try? await index.indexAppEntities(entities)
        }
    }
}
