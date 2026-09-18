//
//  StarlingAPIClient.swift
//  WiggleRoom
//

import Foundation

/// A minimal, direct HTTPS client for Starling's v2 API (§5.3) — calls go
/// straight from this client to `api.starlingbank.com`, no intermediary
/// backend (§11). Accounts, account balance, and Spaces (savings goals +
/// spending spaces) are implemented; the Spaces response shape below was
/// verified directly against developer.starlingbank.com's own rendered API
/// reference (2026-09-18), not guessed at.
struct StarlingAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let token: String
    private let budget: StarlingRequestBudget

    init(
        token: String,
        budget: StarlingRequestBudget,
        baseURL: URL = URL(string: "https://api.starlingbank.com")!,
        session: URLSession = .shared
    ) {
        self.token = token
        self.budget = budget
        self.baseURL = baseURL
        self.session = session
    }

    func fetchAccounts() async throws -> [StarlingAccount] {
        let response: StarlingAccountsResponse = try await get("/api/v2/accounts")
        return response.accounts
    }

    /// The account's effective balance (cleared balance plus any pending
    /// transactions already accounted for), in the account's major currency
    /// unit — Starling reports `minorUnits` (pence/cents), converted here.
    func fetchBalance(accountUid: String) async throws -> Decimal {
        let response: StarlingBalanceResponse = try await get("/api/v2/accounts/\(accountUid)/balance")
        return Decimal(response.effectiveBalance.minorUnits) / 100
    }

    /// Every savings goal and spending space for `accountUid`, each
    /// already carrying its own current balance (`totalSaved`/`balance`)
    /// directly in this list response — unlike the top-level account,
    /// there's no separate per-space balance endpoint needed; refetching
    /// this list is the per-tick call for a tracker pointed at a Space.
    /// Note the singular `/account/` here, not the plural `/accounts/`
    /// `fetchAccounts()`/`fetchBalance` use — Starling's own convention for
    /// a specific account's sub-resources.
    func fetchSpaces(accountUid: String) async throws -> StarlingSpacesResponse {
        try await get("/api/v2/account/\(accountUid)/spaces")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        do {
            try await budget.consumeSlot()
        } catch let exceeded as StarlingRequestBudget.BudgetExceeded {
            throw StarlingAPIError.budgetExceeded(resetsAt: exceeded.resetsAt)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StarlingAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw StarlingAPIError.network("No HTTP response received")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw StarlingAPIError.invalidToken
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            await budget.recordRateLimited(retryAfter: retryAfter)
            throw StarlingAPIError.rateLimited(retryAfter: retryAfter)
        default:
            throw StarlingAPIError.http(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw StarlingAPIError.decoding
        }
    }
}

enum StarlingAPIError: Error, Equatable {
    case invalidToken
    case http(status: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case budgetExceeded(resetsAt: Date)
    case decoding
    case network(String)
}

struct StarlingAccountsResponse: Decodable {
    let accounts: [StarlingAccount]
}

struct StarlingAccount: Decodable, Equatable {
    let accountUid: String
    let name: String?
    let currency: String?
}

struct StarlingBalanceResponse: Decodable {
    let effectiveBalance: StarlingAmount
}

struct StarlingAmount: Decodable, Equatable {
    let currency: String
    let minorUnits: Int
}

/// Schema verified against developer.starlingbank.com's own API reference
/// (2026-09-18): `GET /api/v2/account/{accountUid}/spaces` returns both
/// kinds of space together. Only the fields this app actually uses are
/// decoded — both objects carry several more (sortOrder, target,
/// savedPercentage, cardAssociationUid, spendingSpaceType, …) that aren't
/// needed here.
struct StarlingSpacesResponse: Decodable {
    let savingsGoals: [StarlingSavingsGoal]
    let spendingSpaces: [StarlingSpendingSpace]
}

struct StarlingSavingsGoal: Decodable, Equatable {
    let savingsGoalUid: String
    let name: String
    let totalSaved: StarlingAmount
    /// e.g. "ACTIVE", "ARCHIVED" — only an `ACTIVE` goal is offered as a
    /// tracker target; an archived one is no longer a meaningful thing to
    /// track the pace of.
    let state: String
}

struct StarlingSpendingSpace: Decodable, Equatable {
    let spaceUid: String
    let name: String
    let balance: StarlingAmount
    /// Same `ACTIVE`/otherwise convention as `StarlingSavingsGoal.state`.
    let state: String
}
