//
//  CloudKitSchemaTests.swift
//  WiggleRoomTests
//

import SwiftData
import XCTest
@testable import WiggleRoom

/// Checks every field SwiftData's CloudKit mirroring will write is in the
/// committed `cloudkit/schema.ckdb`, so a model change can't reach a
/// TestFlight build without the schema file (and so the Production gate in
/// the distribution workflows) knowing about it.
///
/// Compares names only. The distribution workflows compare the committed
/// file's types against a live export of Production.
final class CloudKitSchemaTests: XCTestCase {

    func testEveryModelFieldIsInTheCommittedSchema() throws {
        let committed = try committedSchema()
        var problems: [String] = []

        for entity in WiggleRoomSchema.schema.entities {
            let recordType = "CD_\(entity.name)"
            guard let fields = committed[recordType] else {
                problems.append("""
                    \(entity.name) has no record type \(recordType) in cloudkit/schema.ckdb. \(Self.remedy)
                    """)
                continue
            }
            for (property, field) in Self.expectedFields(for: entity) where !fields.contains(field) {
                problems.append("""
                    \(entity.name).\(property) has no \(field) in cloudkit/schema.ckdb. \(Self.remedy)
                    """)
            }
        }

        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    /// Guards the mapping itself, so a SwiftData API change can't make the
    /// test above quietly check nothing.
    func testExpectedFieldsFollowCloudKitMirroringRules() throws {
        let tracker = try XCTUnwrap(WiggleRoomSchema.schema.entities.first { $0.name == "Tracker" })
        let fields = Set(Self.expectedFields(for: tracker).map(\.field))

        XCTAssertTrue(fields.contains("CD_entityName"))
        XCTAssertTrue(fields.contains("CD_isZoomed"), "a stored attribute gets a field")
        XCTAssertTrue(fields.contains("CD_connectedSource"), "a to-one relationship gets a field")
        XCTAssertFalse(fields.contains("CD_readings"), "a to-many relationship gets no field")
        XCTAssertFalse(fields.contains("CD_sortedReadings"), "a computed property gets no field")
    }

    func testTheCommittedSchemaParses() throws {
        let committed = try committedSchema()
        XCTAssertEqual(committed["CD_Tracker"]?.contains("CD_name"), true)
        XCTAssertEqual(committed["CD_ValueSnapshot"]?.contains("CD_tracker"), true)
    }

    // MARK: - Expected fields

    private static let remedy = """
        Run a development build that saves a record so Development gains the field, export the \
        Development schema into cloudkit/schema.ckdb, and deploy it to Production before shipping.
        """

    /// The CloudKit fields SwiftData's mirroring writes for one model, as
    /// (Swift property, CloudKit field) pairs: `CD_entityName` on every
    /// record type, `CD_<name>` per stored attribute and per to-one
    /// relationship (holding the related record's name), and an extra
    /// `CD_<name>_ckAsset` for externally stored data. A to-many
    /// relationship has no field; the other side's to-one carries it.
    static func expectedFields(for entity: Schema.Entity) -> [(property: String, field: String)] {
        var fields = [(property: "(every record)", field: "CD_entityName")]
        for attribute in entity.attributes where !attribute.isTransient {
            fields.append((attribute.name, "CD_\(attribute.name)"))
            if attribute.options.contains(.externalStorage) {
                fields.append((attribute.name, "CD_\(attribute.name)_ckAsset"))
            }
        }
        for relationship in entity.relationships where relationship.isToOneRelationship && !relationship.isTransient {
            fields.append((relationship.name, "CD_\(relationship.name)"))
        }
        return fields.sorted { $0.field < $1.field }
    }

    // MARK: - Committed schema

    /// Record type name to field names, read from `cloudkit/schema.ckdb`
    /// at the repository root. Located from this source file's path, which
    /// the iOS Simulator can read straight from the checkout.
    private func committedSchema() throws -> [String: Set<String>] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WiggleRoomTests
            .deletingLastPathComponent() // src
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("cloudkit/schema.ckdb")

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            #if os(macOS)
            // The sandboxed macOS test host can't read the checkout. The
            // iOS Simulator run (which the build check uses) can.
            throw XCTSkip("Can't read \(url.path) from the sandboxed macOS test host: \(error)")
            #else
            throw error
            #endif
        }
        return Self.parse(text)
    }

    /// Enough of the `.ckdb` schema language for field names: a
    /// `RECORD TYPE name (` line opens a type, `)` closes it, and each line
    /// between starts with a field name (quoted for `___` system fields)
    /// or with `GRANT`.
    static func parse(_ text: String) -> [String: Set<String>] {
        var types: [String: Set<String>] = [:]
        var current: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("RECORD TYPE") {
                let name = trimmed.dropFirst("RECORD TYPE".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " (\""))
                current = name
                types[name, default: []] = []
            } else if trimmed.hasPrefix(")") {
                current = nil
            } else if let current, let token = trimmed.split(separator: " ").first {
                let field = token.trimmingCharacters(in: CharacterSet(charactersIn: "\","))
                if field != "GRANT" { types[current, default: []].insert(field) }
            }
        }
        return types
    }
}
