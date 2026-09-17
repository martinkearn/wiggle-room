//
//  StarlingRequestBudgetTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

/// A settable clock to hand to `StarlingRequestBudget`'s `now` closure — a
/// small reference type rather than capturing a mutable local `var`
/// directly, since the closure is called from actor-isolated code and a
/// captured `var` wouldn't satisfy `@Sendable` under strict concurrency.
private final class TestClock: @unchecked Sendable {
    var current: Date
    init(_ date: Date) { current = date }
}

final class StarlingRequestBudgetTests: XCTestCase {

    func testConsumeSlot_underLimit_succeeds() async throws {
        let budget = StarlingRequestBudget(dailyLimit: 1000, warningThreshold: 900)
        try await budget.consumeSlot()
        let count = await budget.requestCountInLast24Hours
        XCTAssertEqual(count, 1)
    }

    func testConsumeSlot_atWarningThreshold_throwsBudgetExceeded() async {
        // A tiny threshold so the test doesn't need to make 900 real calls.
        let budget = StarlingRequestBudget(dailyLimit: 3, warningThreshold: 2)
        try? await budget.consumeSlot()
        try? await budget.consumeSlot()

        do {
            try await budget.consumeSlot()
            XCTFail("expected the third call to exceed the (test) warning threshold of 2")
        } catch is StarlingRequestBudget.BudgetExceeded {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testConsumeSlot_oldRequestsAgeOutAfter24Hours() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let budget = StarlingRequestBudget(dailyLimit: 3, warningThreshold: 2, now: { clock.current })

        try await budget.consumeSlot()
        try await budget.consumeSlot()
        // Two slots used, at the (test) threshold — a third right now would
        // throw. Move the clock forward 25 hours so both age out first.
        clock.current = clock.current.addingTimeInterval(25 * 3600)

        try await budget.consumeSlot()
        let count = await budget.requestCountInLast24Hours
        XCTAssertEqual(count, 1, "only the just-made request should still be counted")
    }

    func testRecordRateLimited_blocksUntilRetryAfterElapses() async {
        let clock = TestClock(Date(timeIntervalSince1970: 0))
        let budget = StarlingRequestBudget(dailyLimit: 1000, warningThreshold: 900, now: { clock.current })

        await budget.recordRateLimited(retryAfter: 30)

        do {
            try await budget.consumeSlot()
            XCTFail("expected the cool-down to still be active")
        } catch let exceeded as StarlingRequestBudget.BudgetExceeded {
            XCTAssertEqual(exceeded.resetsAt, clock.current.addingTimeInterval(30))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        clock.current = clock.current.addingTimeInterval(31)
        try? await budget.consumeSlot()
        let count = await budget.requestCountInLast24Hours
        XCTAssertEqual(count, 1, "should succeed once the cool-down has elapsed")
    }
}
