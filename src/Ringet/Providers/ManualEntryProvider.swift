//
//  ManualEntryProvider.swift
//  Ringet
//

import Foundation

enum ManualEntryProviderError: Error, Equatable {
    /// `fetchCurrentValue` was called for a target that has never had a
    /// reading logged against it.
    case noReadingsLogged(targetId: String)
}

/// The manual-entry source provider (§5.5) — used for anything without an
/// API. `actualValue` is always the most recently logged reading; there is
/// no automatic refresh.
///
/// A manual `ConnectedSource` starts with a single implicit target (a plain
/// "Reading" log), usable with no setup, satisfying §5.1's "manual returns
/// a single implicit target (or a user-named log)". Additional named logs
/// can be registered per connection via `addTarget`.
///
/// Backed by an in-memory store — readings do not yet survive relaunch;
/// that lands with the SwiftData/CloudKit persistence phase (§6).
actor ManualEntryProvider: SourceProvider {
    nonisolated let providerId = "manual"
    nonisolated let displayName = "Manual entry"
    nonisolated let requiresConnection = false

    /// User-named targets registered per connection, in the order added.
    /// The implicit default target is never stored here — it's derived on
    /// demand so a fresh connection needs no setup.
    private var namedTargetsByConnection: [UUID: [SourceTarget]] = [:]

    /// Logged readings by target id. `fetchCurrentValue`/`logManualReading`
    /// only carry a target (§5.1), not its owning connection, so a target's
    /// id alone must be enough to find its readings — true for both the
    /// implicit target (its id embeds the connection id) and named targets
    /// (freshly-generated UUIDs).
    private var readingsByTargetId: [String: [ValueSnapshot]] = [:]

    /// The always-available implicit target for a manual connection.
    nonisolated static func implicitTarget(for connection: ConnectedSource) -> SourceTarget {
        SourceTarget(id: "implicit:\(connection.id.uuidString)", displayName: "Reading")
    }

    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget] {
        let named = namedTargetsByConnection[connection.id] ?? []
        return [Self.implicitTarget(for: connection)] + named
    }

    /// Registers an additional named log for a connection (e.g. "Car A
    /// mileage" vs. "Car B mileage" on the same manual connected source),
    /// so it appears in future `listAvailableTargets` calls.
    @discardableResult
    func addTarget(displayName: String, to connection: ConnectedSource) -> SourceTarget {
        let target = SourceTarget(id: UUID().uuidString, displayName: displayName)
        namedTargetsByConnection[connection.id, default: []].append(target)
        return target
    }

    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal {
        guard let latest = latestReading(for: target) else {
            throw ManualEntryProviderError.noReadingsLogged(targetId: target.id)
        }
        return latest.value
    }

    func logManualReading(target: SourceTarget, value: Decimal, date: Date) async throws {
        readingsByTargetId[target.id, default: []].append(ValueSnapshot(value: value, date: date))
    }

    /// All readings logged for a target, oldest first. Not part of the
    /// `SourceProvider` protocol — the timestamped history this store
    /// already keeps (§4.6) is exposed here for zoom levels and trend
    /// charts to read from later.
    func readings(for target: SourceTarget) async -> [ValueSnapshot] {
        (readingsByTargetId[target.id] ?? []).sorted { $0.date < $1.date }
    }

    private func latestReading(for target: SourceTarget) -> ValueSnapshot? {
        readingsByTargetId[target.id]?.max { $0.date < $1.date }
    }
}
