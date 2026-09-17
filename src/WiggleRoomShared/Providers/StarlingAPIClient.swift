//
//  StarlingAPIClient.swift
//  WiggleRoom
//

import Foundation

/// A minimal, direct HTTPS client for Starling's v2 API (§5.3) — calls go
/// straight from this client to `api.starlingbank.com`, no intermediary
/// backend (§11). Only the accounts-list and balance endpoints are
/// implemented: the Spaces/savings-goals endpoint shape is still unverified
/// against current Starling docs (§12) and is deliberately left unbuilt
/// rather than guessed at — trackers pointed at a Space aren't supported
/// yet.
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
