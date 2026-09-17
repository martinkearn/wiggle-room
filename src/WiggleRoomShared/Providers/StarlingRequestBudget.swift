//
//  StarlingRequestBudget.swift
//  WiggleRoom
//

import Foundation

/// Client-side guard against Starling's personal-access-token rate limits
/// (researched for §5.3/§12: 5 requests/second, 1000 requests/day, as of
/// the research done alongside this decision — re-confirm against
/// developer.starlingbank.com/faq at build time in case they've changed).
/// 5 req/s is trivially safe at this app's polling cadence; 1000/day is the
/// real constraint, so this tracks a rolling 24h request count and refuses
/// new requests once close to the daily cap, rather than waiting to be hit
/// with 429s. Also records a cool-down whenever the server itself returns
/// 429 with `Retry-After`.
///
/// One instance is meant to be shared across every `StarlingAPIClient` made
/// for the same connected source, so the count reflects that source's
/// actual daily usage rather than resetting per call site.
actor StarlingRequestBudget {
    struct BudgetExceeded: Error, Equatable {
        let resetsAt: Date
    }

    private let dailyLimit: Int
    private let warningThreshold: Int
    private var requestTimestamps: [Date] = []
    private var cooldownUntil: Date?
    private let now: @Sendable () -> Date

    init(dailyLimit: Int = 1000, warningThreshold: Int = 900, now: @escaping @Sendable () -> Date = Date.init) {
        self.dailyLimit = dailyLimit
        self.warningThreshold = warningThreshold
        self.now = now
    }

    /// Call before every outgoing request. Throws rather than making a call
    /// that would tip the daily count past `warningThreshold`, or during an
    /// active 429 cool-down.
    func consumeSlot() throws {
        let current = now()
        if let cooldownUntil, current < cooldownUntil {
            throw BudgetExceeded(resetsAt: cooldownUntil)
        }
        requestTimestamps.removeAll { current.timeIntervalSince($0) > 86400 }
        guard requestTimestamps.count < warningThreshold else {
            let oldestStillCounted = requestTimestamps.min() ?? current
            throw BudgetExceeded(resetsAt: oldestStillCounted.addingTimeInterval(86400))
        }
        requestTimestamps.append(current)
    }

    /// Records a server-side 429 — future requests back off until
    /// `retryAfter` seconds from now (or a conservative default if the
    /// server didn't send one).
    func recordRateLimited(retryAfter: TimeInterval?) {
        cooldownUntil = now().addingTimeInterval(retryAfter ?? 60)
    }

    /// For diagnostics/tests only.
    var requestCountInLast24Hours: Int {
        get async {
            let current = now()
            return requestTimestamps.filter { current.timeIntervalSince($0) <= 86400 }.count
        }
    }
}
