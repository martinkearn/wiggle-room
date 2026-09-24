import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

struct TrackerArchive: Codable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let sources: [Source]
    let trackers: [ArchivedTracker]

    struct Source: Codable, Identifiable, Hashable {
        let id: UUID
        let providerId: String
        let displayName: String
    }

    struct ArchivedTracker: Codable, Identifiable {
        let id: UUID
        let name: String
        let unit: String
        let direction: TrackerDirection
        let sourceId: UUID?
        let sourceTargetId: String?
        let startDate: Date
        let endDate: Date
        let startingValue: String
        let totalAllowance: String
        let reminderCadenceMinutes: Int?
        let lastAutoFetchAttempt: Date?
        let lastCheckedDate: Date?
        let hasCelebratedCompletion: Bool
        let sortOrder: Int
        let colorIndex: Int
        let glyph: String
        let readings: [Reading]
    }

    struct Reading: Codable, Identifiable {
        let id: UUID
        let value: String
        let date: Date
    }

    var externalSources: [Source] {
        sources.filter { $0.providerId != "manual" }
    }
}

enum TrackerArchiveError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidDecimal
    case duplicateTracker
    case duplicateName(String)
    case invalidSourceMapping

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "This archive uses unsupported format version \(version)."
        case .invalidDecimal:
            "The archive contains an invalid number."
        case .duplicateTracker:
            "A tracker in this archive has already been imported."
        case .duplicateName(let name):
            "A tracker named “\(name)” already exists."
        case .invalidSourceMapping:
            "A selected connected source has the wrong type."
        }
    }
}

@MainActor
enum TrackerArchiveService {
    static func makeArchive(trackers: [Tracker]) -> TrackerArchive {
        let sources = Dictionary(
            uniqueKeysWithValues: trackers.compactMap(\.connectedSource).map { source in
                (source.id, TrackerArchive.Source(
                    id: source.id,
                    providerId: source.providerId,
                    displayName: source.displayName
                ))
            }
        )
        return TrackerArchive(
            version: TrackerArchive.currentVersion,
            exportedAt: .now,
            sources: sources.values.sorted { $0.id.uuidString < $1.id.uuidString },
            trackers: trackers.map { tracker in
                TrackerArchive.ArchivedTracker(
                    id: tracker.id,
                    name: tracker.name,
                    unit: tracker.unit,
                    direction: tracker.direction,
                    sourceId: tracker.connectedSource?.id,
                    sourceTargetId: tracker.sourceTargetId,
                    startDate: tracker.startDate,
                    endDate: tracker.endDate,
                    startingValue: NSDecimalNumber(decimal: tracker.startingValue).stringValue,
                    totalAllowance: NSDecimalNumber(decimal: tracker.totalAllowance).stringValue,
                    reminderCadenceMinutes: tracker.reminderCadenceMinutes,
                    lastAutoFetchAttempt: tracker.lastAutoFetchAttempt,
                    lastCheckedDate: tracker.lastCheckedDate,
                    hasCelebratedCompletion: tracker.hasCelebratedCompletion,
                    sortOrder: tracker.sortOrder,
                    colorIndex: tracker.colorIndex,
                    glyph: tracker.glyph,
                    readings: tracker.sortedReadings.map {
                        TrackerArchive.Reading(
                            id: $0.id,
                            value: NSDecimalNumber(decimal: $0.value).stringValue,
                            date: $0.date
                        )
                    }
                )
            }
        )
    }

    static func encode(_ archive: TrackerArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> TrackerArchive {
        let archive = try JSONDecoder().decode(TrackerArchive.self, from: data)
        guard archive.version == TrackerArchive.currentVersion else {
            throw TrackerArchiveError.unsupportedVersion(archive.version)
        }
        return archive
    }

    @discardableResult
    static func importArchive(
        _ archive: TrackerArchive,
        sourceMappings: [UUID: ConnectedSource],
        store: TrackerStore,
        modelContext: ModelContext
    ) throws -> Int {
        guard archive.version == TrackerArchive.currentVersion else {
            throw TrackerArchiveError.unsupportedVersion(archive.version)
        }

        let existing = try modelContext.fetch(FetchDescriptor<Tracker>())
        let existingIDs = Set(existing.map(\.id))
        let existingNames = existing.map(\.name)
        let archiveSourceByID = Dictionary(uniqueKeysWithValues: archive.sources.map { ($0.id, $0) })

        for tracker in archive.trackers {
            guard Decimal(string: tracker.startingValue) != nil,
                  Decimal(string: tracker.totalAllowance) != nil,
                  tracker.readings.allSatisfy({ Decimal(string: $0.value) != nil })
            else { throw TrackerArchiveError.invalidDecimal }
            guard !existingIDs.contains(tracker.id) else {
                throw TrackerArchiveError.duplicateTracker
            }
            guard !existingNames.contains(where: {
                $0.caseInsensitiveCompare(tracker.name) == .orderedSame
            }) else {
                throw TrackerArchiveError.duplicateName(tracker.name)
            }
            if let sourceId = tracker.sourceId,
               let archivedSource = archiveSourceByID[sourceId],
               archivedSource.providerId != "manual",
               let mappedSource = sourceMappings[sourceId],
               mappedSource.providerId != archivedSource.providerId {
                throw TrackerArchiveError.invalidSourceMapping
            }
        }

        for archived in archive.trackers {
            let archivedSource = archived.sourceId.flatMap { archiveSourceByID[$0] }
            let source: ConnectedSource?
            if archivedSource?.providerId == "manual" {
                source = store.manualEntrySource
            } else if let sourceId = archived.sourceId {
                source = sourceMappings[sourceId]
            } else {
                source = nil
            }

            let tracker = Tracker(
                id: archived.id,
                name: archived.name,
                unit: archived.unit,
                direction: archived.direction,
                connectedSource: source,
                sourceTargetId: archived.sourceTargetId,
                startDate: archived.startDate,
                endDate: archived.endDate,
                startingValue: Decimal(string: archived.startingValue)!,
                totalAllowance: Decimal(string: archived.totalAllowance)!,
                reminderCadenceMinutes: archived.reminderCadenceMinutes
            )
            tracker.lastAutoFetchAttempt = archived.lastAutoFetchAttempt
            tracker.lastCheckedDate = archived.lastCheckedDate
            tracker.hasCelebratedCompletion = archived.hasCelebratedCompletion
            tracker.sortOrder = archived.sortOrder
            tracker.colorIndex = archived.colorIndex
            tracker.glyph = archived.glyph
            modelContext.insert(tracker)

            for archivedReading in archived.readings {
                let reading = ValueSnapshot(
                    id: archivedReading.id,
                    value: Decimal(string: archivedReading.value)!,
                    date: archivedReading.date
                )
                reading.tracker = tracker
                modelContext.insert(reading)
            }
            ReminderScheduler.sync(tracker)
        }

        do {
            try modelContext.save()
            store.saveChanges()
            return archive.trackers.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

struct TrackerArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
