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
/// real constraint, so this tracks a rolling 24h request count **local to
/// this device/process** and refuses new requests once close to the daily
/// cap, rather than waiting to be hit with 429s. Also records a cool-down
/// whenever the server itself returns 429 with `Retry-After`.
///
/// One instance is meant to be shared across every `StarlingAPIClient` made
/// for the same connected source, so the count reflects that source's
/// actual daily usage rather than resetting per call site. Deliberately
/// in-memory only (resets on relaunch) — this is a same-device safety net
/// against a single runaway process, not the number shown to the user; see
/// `onRequestLogged` below for the user-visible, cross-device count.
///
/// **This budget alone cannot know the real, account-wide usage of a
/// token.** Starling's API exposes no endpoint or response header
/// reporting how many requests have been made against a token overall, and
/// a personal access token can be (and, once synced via CloudKit like
/// every other piece of `ConnectedSource` data, typically will be) used
/// from more than one of the user's own devices at once — each device's
/// own `StarlingRequestBudget` instance only ever sees its own requests.
/// The user-visible "Starling Requests Today" figure (`GeneralSettingsView`
/// /`AddSourceView`) is therefore backed by a separate, genuinely
/// cross-device mechanism — `StarlingRequestLogEntry`, a CloudKit-synced
/// record inserted via `onRequestLogged` below, queried live wherever it's
/// displayed — not by this actor's own local count.
actor StarlingRequestBudget {
    struct BudgetExceeded: Error, Equatable {
        let resetsAt: Date
    }

    /// Starling's own documented personal-access-token daily cap — exposed
    /// statically so display code (`GeneralSettingsView`/`AddSourceView`,
    /// showing "X / 1000" against the synced request log) doesn't need a
    /// live instance just to read a constant.
    static let dailyLimit = 1000

    /// Shared verbatim by `GeneralSettingsView` (macOS, Settings → General)
    /// and `AddSourceView` (iOS, the only place this insight is surfaced at
    /// all there — iOS has no equivalent Settings scene, §7.2) — kept here
    /// rather than on either view so both platforms can reference it
    /// without one platform-gated view depending on the other.
    static let requestCaption = "Counts requests from all your devices. Resets at midnight."

    private let dailyLimit: Int
    private let warningThreshold: Int
    private var requestTimestamps: [Date] = []
    private var cooldownUntil: Date?
    private let now: @Sendable () -> Date
    /// `@MainActor`-isolated — `StarlingRequestLogger.record(at:)` touches
    /// a `ModelContainer`, and this project defaults every unannotated
    /// declaration to `@MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`),
    /// so matching that here (rather than forcing `StarlingRequestLogger`
    /// to opt out of it) is what keeps this a plain, ordinary function
    /// reference at the call site instead of an isolation mismatch. Costs
    /// one extra actor hop per real Starling request (not per app tick),
    /// which is negligible.
    private let onRequestLogged: (@MainActor @Sendable (Date) -> Void)?

    init(
        dailyLimit: Int = StarlingRequestBudget.dailyLimit,
        warningThreshold: Int = 900,
        now: @escaping @Sendable () -> Date = Date.init,
        onRequestLogged: (@MainActor @Sendable (Date) -> Void)? = nil
    ) {
        self.dailyLimit = dailyLimit
        self.warningThreshold = warningThreshold
        self.now = now
        self.onRequestLogged = onRequestLogged
    }

    /// Call before every outgoing request. Throws rather than making a call
    /// that would tip the daily count past `warningThreshold`, or during an
    /// active 429 cool-down. On success, also fires `onRequestLogged` — the
    /// hook `StarlingProvider.sharedBudget` uses to record the request into
    /// the synced, cross-device log (see the type-level note above).
    func consumeSlot() async throws {
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
        await onRequestLogged?(current)
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

    /// Surfaced in Settings → General and the Connected Source detail
    /// screen (§5.3's request-budget mitigations) — currently just the
    /// active cool-down, if any; the request *count* itself now comes from
    /// `StarlingRequestLogEntry` (a live `@Query`, see those views) rather
    /// than from here, since only a synced log can reflect every device's
    /// usage, not just this process's own.
    struct Status {
        let cooldownUntil: Date?
    }

    var status: Status {
        get async {
            let current = now()
            return Status(cooldownUntil: cooldownUntil.flatMap { $0 > current ? $0 : nil })
        }
    }
}
