//
//  SharedPreviewData.swift
//  WiggleRoomShared
//

import Foundation
import SwiftData

/// Minimal in-memory preview fixture for shared views (`RingsView`) that
/// need a real `Tracker` but must not depend on `TrackerStore` — the app
/// target's store isn't part of this shared target, and widgets/watch build
/// their own lightweight fetches rather than using it. See `PreviewData` in
/// the main app target for the fuller equivalent used by app-only views.
enum SharedPreviewData {
    @MainActor
    static let container: ModelContainer = {
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self, StarlingRequestLogEntry.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    @MainActor
    @discardableResult
    static func makeSampleTracker() -> Tracker {
        let context = container.mainContext
        let source = ConnectedSource(providerId: "manual", displayName: "Manual")
        context.insert(source)

        let tracker = Tracker(
            name: "Joint account — September",
            type: .spendingMoney,
            unit: .sterling,
            connectedSource: source,
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
