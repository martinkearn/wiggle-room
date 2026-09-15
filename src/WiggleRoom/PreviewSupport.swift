//
//  PreviewSupport.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// Shared in-memory SwiftData stack for `#Preview` blocks — never used at
/// runtime. Avoids every preview repeating the same container/store setup.
enum PreviewData {
    @MainActor
    static let container: ModelContainer = {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    @MainActor
    static let store: TrackerStore = TrackerStore(modelContext: container.mainContext)

    /// Inserts one sample tracker with a few readings into the preview
    /// container, for previews that want to show real-looking data.
    @MainActor
    @discardableResult
    static func makeSampleTracker() -> Tracker {
        let context = container.mainContext
        let tracker = Tracker(
            name: "Joint account — September",
            unit: "£",
            direction: .decreasing,
            connectedSource: store.manualEntrySource,
            sourceTargetId: UUID().uuidString,
            startDate: Calendar.current.date(byAdding: .day, value: -10, to: .now) ?? .now,
            endDate: Calendar.current.date(byAdding: .day, value: 20, to: .now) ?? .now,
            startingValue: 3000,
            totalAllowance: 3000
        )
        context.insert(tracker)

        let reading = ValueSnapshot(value: 1800, date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        reading.tracker = tracker
        context.insert(reading)

        try? context.save()
        return tracker
    }
}
