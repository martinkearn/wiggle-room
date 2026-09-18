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
    /// A tracker's `sourceTargetId` parsed as a Space (§5.3), but neither
    /// that account's savings goals nor its spending spaces contain a
    /// matching id any more — the Space was likely deleted/archived at
    /// Starling since the tracker was created.
    case targetNotFound
}

/// A `SourceTarget.id` for a Starling Space (a savings goal or spending
/// space) encodes which account it belongs to alongside the space's own
/// id — unlike a plain top-level account target (just its bare
/// `accountUid`), fetching a Space's current value needs the account id
/// too (`StarlingAPIClient.fetchSpaces(accountUid:)` is scoped per
/// account, there's no standalone "fetch this one space" endpoint). Kept
/// as a plain encoded string rather than changing `SourceTarget` itself
/// (shared by every provider, §5.1) to carry provider-specific structure.
private enum StarlingSpaceTargetID {
    private static let prefix = "space:"

    static func encode(accountUid: String, spaceUid: String) -> String {
        "\(accountUid)#\(prefix)\(spaceUid)"
    }

    /// `nil` for a plain top-level-account target id (no `#space:` suffix).
    static func decode(_ id: String) -> (accountUid: String, spaceUid: String)? {
        guard let hashIndex = id.firstIndex(of: "#"), id[id.index(after: hashIndex)...].hasPrefix(prefix) else {
            return nil
        }
        let accountUid = String(id[..<hashIndex])
        let spaceUid = String(id[id.index(hashIndex, offsetBy: 1 + prefix.count)...])
        return (accountUid, spaceUid)
    }
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
    /// only, not persisted) — an accepted simplification for v1 for this
    /// local safety-net count specifically (see `StarlingRequestBudget`'s
    /// own doc comment for why the *displayed* count doesn't rely on this
    /// at all). `onRequestLogged: StarlingRequestLogger.record` is what
    /// makes every real request from this device show up in the synced,
    /// cross-device "Starling Requests Today" figure. Not `private`:
    /// `GeneralSettingsView` reads `sharedBudget.status` to surface the
    /// active cool-down (§5.3) in Settings.
    static let sharedBudget = StarlingRequestBudget(onRequestLogged: StarlingRequestLogger.record)

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

    /// Flat list, one entry per pickable target — a plain top-level
    /// account ("Personal · Main Account") plus every *active* Space
    /// within it ("Personal · Holiday Fund"), rather than a separate
    /// account-then-space drill-down step. A tracker can point at either
    /// kind identically from here on; only `fetchCurrentValue` needs to
    /// know which is which (via `StarlingSpaceTargetID`).
    ///
    /// A given account's Spaces are fetched best-effort (`try?`) rather
    /// than letting one account's failure abort the whole picker — an
    /// account with no `space:read`-equivalent access, say, still
    /// contributes its own main-account entry.
    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget] {
        let client = try makeClient(for: connection)
        let accounts = try await client.fetchAccounts()
        var targets: [SourceTarget] = []
        for account in accounts {
            let accountName = account.name ?? "Starling Account"
            targets.append(SourceTarget(id: account.accountUid, displayName: "\(accountName) \u{00B7} Main Account"))
            guard let spaces = try? await client.fetchSpaces(accountUid: account.accountUid) else { continue }
            for goal in spaces.savingsGoals where goal.state == "ACTIVE" {
                let id = StarlingSpaceTargetID.encode(accountUid: account.accountUid, spaceUid: goal.savingsGoalUid)
                targets.append(SourceTarget(id: id, displayName: "\(accountName) \u{00B7} \(goal.name)"))
            }
            for space in spaces.spendingSpaces where space.state == "ACTIVE" {
                let id = StarlingSpaceTargetID.encode(accountUid: account.accountUid, spaceUid: space.spaceUid)
                targets.append(SourceTarget(id: id, displayName: "\(accountName) \u{00B7} \(space.name)"))
            }
        }
        return targets
    }

    /// Coalesced across every tracker pointed at the same account/Space
    /// (`StarlingBalanceCache`, §5.3 mitigation 2) — two trackers sharing
    /// one target no longer each cost their own request on every poll
    /// tick, which real usage showed was a real contributor to hitting the
    /// daily/burst rate limit more than expected.
    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal {
        guard let boundConnection else { throw StarlingProviderError.notConnected }
        if let cached = await StarlingBalanceCache.shared.cachedValue(for: target.id) {
            return cached
        }
        let client = try makeClient(for: boundConnection)
        let value: Decimal
        if let (accountUid, spaceUid) = StarlingSpaceTargetID.decode(target.id) {
            let spaces = try await client.fetchSpaces(accountUid: accountUid)
            if let goal = spaces.savingsGoals.first(where: { $0.savingsGoalUid == spaceUid }) {
                value = Decimal(goal.totalSaved.minorUnits) / 100
            } else if let space = spaces.spendingSpaces.first(where: { $0.spaceUid == spaceUid }) {
                value = Decimal(space.balance.minorUnits) / 100
            } else {
                throw StarlingProviderError.targetNotFound
            }
        } else {
            value = try await client.fetchBalance(accountUid: target.id)
        }
        await StarlingBalanceCache.shared.store(value, for: target.id)
        return value
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
