//
//  StarlingBalanceCache.swift
//  WiggleRoom
//

import Foundation

/// Coalesces balance requests across every tracker pointed at the same
/// Starling account (§4.4/§5.3 mitigation 2 — previously not built: "two
/// trackers on the same account still poll it independently"). Real usage
/// surfaced this as a genuine driver of hitting Starling's rate limit more
/// than expected, not just a theoretical concern.
///
/// A short-lived cache, not a long one: `ttl` is deliberately just under
/// the 30s foreground poll cadence (§5.3), so it only coalesces requests
/// that would have landed within roughly the same tick across multiple
/// trackers/screens — it never makes a single tracker's own figures look
/// more than one poll interval stale.
actor StarlingBalanceCache {
    static let shared = StarlingBalanceCache()

    private struct Entry {
        let value: Decimal
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(ttl: TimeInterval = 25, now: @escaping @Sendable () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    /// Returns a still-fresh cached balance for `accountUid`, or `nil` if
    /// there isn't one — the caller should fetch for real and call `store`.
    func cachedValue(for accountUid: String) -> Decimal? {
        guard let entry = entries[accountUid], now().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry.value
    }

    func store(_ value: Decimal, for accountUid: String) {
        entries[accountUid] = Entry(value: value, fetchedAt: now())
    }
}
