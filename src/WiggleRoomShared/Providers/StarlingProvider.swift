//
//  StarlingProvider.swift
//  WiggleRoom
//

import Foundation

enum StarlingProviderError: Error, Equatable {
    /// No token could be resolved for this connection — either it was
    /// never connected, or `credentialToken` has gone missing (e.g. the
    /// `ConnectedSource` record was edited outside the app).
    case notConnected
    /// Starling is read-only in this app (§9 — no payment/write scopes) so
    /// there's nothing to override; a manual correction reading should be
    /// logged directly via `TrackerStore.logReading`, not through this
    /// provider.
    case manualLoggingNotSupported
}

/// The Starling source provider (§5.3) — real bank-balance auto-fetch,
/// backed directly by `StarlingAPIClient`.
///
/// Each instance is created for one specific `ConnectedSource` (its
/// personal access token lives on that record's own `credentialToken`
/// field — synced via CloudKit like everything else, not the Keychain, so
/// it reaches every device the same way the rest of the user's data does)
/// — see `TrackerStore.provider(for:)`, which resolves the right instance
/// for a given tracker. `listAvailableTargets` takes its own `connection`
/// argument rather than relying on that binding, since it also needs to
/// work against a not-yet-persisted draft connection during Add Source
/// setup (§5.2), before anything is bound to it.
@MainActor
final class StarlingProvider: SourceProvider {
    nonisolated let providerId = "starling"
    nonisolated let displayName = "Starling"
    nonisolated let requiresConnection = true

    /// Shared by every `StarlingProvider` instance created with the default
    /// argument, so the daily request count is tracked app-wide rather than
    /// resetting every time `TrackerStore.provider(for:)` hands back a fresh
    /// instance for the same connection. Resets on app relaunch (in-memory
    /// only, not persisted) — an accepted simplification for v1, since it
    /// still catches the case this exists for (heavy same-session polling),
    /// just not a genuinely 24h-spanning count across app restarts.
    private static let sharedBudget = StarlingRequestBudget()

    private let boundConnection: ConnectedSource?
    private let budget: StarlingRequestBudget

    /// `budget` defaults to `nil` rather than resolving `sharedBudget`
    /// directly as a default argument value — under this project's default
    /// main-actor isolation, a default-argument expression runs in the
    /// caller's (non-isolated) context rather than this initializer's, so
    /// resolving it here in the (main-actor-isolated) body instead avoids
    /// an isolation error.
    init(connection: ConnectedSource? = nil, budget: StarlingRequestBudget? = nil) {
        self.boundConnection = connection
        self.budget = budget ?? Self.sharedBudget
    }

    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget] {
        let client = try makeClient(for: connection)
        let accounts = try await client.fetchAccounts()
        return accounts.map { SourceTarget(id: $0.accountUid, displayName: $0.name ?? "Starling Account") }
    }

    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal {
        guard let boundConnection else { throw StarlingProviderError.notConnected }
        let client = try makeClient(for: boundConnection)
        return try await client.fetchBalance(accountUid: target.id)
    }

    func logManualReading(target: SourceTarget, value: Decimal, date: Date) async throws {
        throw StarlingProviderError.manualLoggingNotSupported
    }

    private func makeClient(for connection: ConnectedSource) throws -> StarlingAPIClient {
        guard let token = connection.credentialToken, !token.isEmpty else {
            throw StarlingProviderError.notConnected
        }
        return StarlingAPIClient(token: token, budget: budget)
    }
}
