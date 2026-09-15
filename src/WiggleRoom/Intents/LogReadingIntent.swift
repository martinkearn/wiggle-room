//
//  LogReadingIntent.swift
//  WiggleRoom
//

import AppIntents
import Foundation
import SwiftData

enum LogReadingIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notManualEntry(name: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notManualEntry(let name):
            return "\"\(name)\" isn't a manual tracker, so it can't be updated from Shortcuts."
        }
    }
}

/// Lets Siri/Shortcuts log a reading for a manual tracker (§5.5) without
/// opening the app — the same action as the in-app "Update" button, exposed
/// as an `AppIntent` so it can be triggered by voice, a Shortcuts automation,
/// or (later) a Home Screen/Lock Screen widget button.
struct LogReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Reading"
    static var description = IntentDescription("Logs a new value for one of your trackers.")

    @Parameter(title: "Tracker")
    var tracker: TrackerEntity

    @Parameter(title: "Value")
    var value: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try IntentDataStore.makeContainer()
        let store = TrackerStore(modelContext: container.mainContext)
        let trackerId = tracker.id
        let descriptor = FetchDescriptor<Tracker>(predicate: #Predicate { $0.id == trackerId })
        guard let liveTracker = try container.mainContext.fetch(descriptor).first,
              liveTracker.isManualEntry else {
            throw LogReadingIntentError.notManualEntry(name: tracker.name)
        }

        store.logReading(value: Decimal(value), date: .now, for: liveTracker)

        let pace = liveTracker.pace(actualValue: Decimal(value), asOf: .now)
        let dialog = "Logged \(liveTracker.formattedValue(Decimal(value))) for \(liveTracker.name). \(pace.status.label(for: liveTracker))."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
