//
//  StarlingAPIClientTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

/// Stubs every request through a handler set per-test, rather than hitting
/// the real network — `StarlingAPIClient` is given a `URLSession`
/// configured to route through this protocol.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class StarlingAPIClientTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(budget: StarlingRequestBudget = StarlingRequestBudget()) -> StarlingAPIClient {
        StarlingAPIClient(token: "test-token", budget: budget, session: StubURLProtocol.makeSession())
    }

    func testFetchAccounts_decodesAccountList() async throws {
        let json = """
        { "accounts": [ { "accountUid": "abc-123", "name": "Personal", "currency": "GBP" } ] }
        """.data(using: .utf8)!
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/accounts")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let accounts = try await makeClient().fetchAccounts()

        XCTAssertEqual(accounts, [StarlingAccount(accountUid: "abc-123", name: "Personal", currency: "GBP")])
    }

    func testFetchBalance_convertsMinorUnitsToDecimal() async throws {
        let json = """
        { "effectiveBalance": { "currency": "GBP", "minorUnits": 123456 } }
        """.data(using: .utf8)!
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/accounts/abc-123/balance")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let balance = try await makeClient().fetchBalance(accountUid: "abc-123")

        // Built from a string, not a Double literal — `Decimal(1234.56)`
        // would round-trip through Double first and not compare exactly
        // equal to the client's pure-decimal `minorUnits / 100` division.
        XCTAssertEqual(balance, Decimal(string: "1234.56")!)
    }

    func testUnauthorized_throwsInvalidToken() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await makeClient().fetchAccounts()
            XCTFail("expected invalidToken")
        } catch StarlingAPIError.invalidToken {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRateLimited_throwsWithRetryAfterAndRecordsCooldown() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "42"])!, Data())
        }
        let budget = StarlingRequestBudget()

        do {
            _ = try await makeClient(budget: budget).fetchAccounts()
            XCTFail("expected rateLimited")
        } catch StarlingAPIError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 42)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        // The cool-down should now block a further call even against a
        // handler that would otherwise succeed.
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "{\"accounts\":[]}".data(using: .utf8)!)
        }
        do {
            _ = try await makeClient(budget: budget).fetchAccounts()
            XCTFail("expected budgetExceeded from the recorded cool-down")
        } catch StarlingAPIError.budgetExceeded {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDailyBudgetExceeded_throwsWithoutMakingRequest() async {
        var requestWasMade = false
        StubURLProtocol.handler = { request in
            requestWasMade = true
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "{\"accounts\":[]}".data(using: .utf8)!)
        }
        let exhaustedBudget = StarlingRequestBudget(dailyLimit: 1, warningThreshold: 0)

        do {
            _ = try await makeClient(budget: exhaustedBudget).fetchAccounts()
            XCTFail("expected budgetExceeded")
        } catch StarlingAPIError.budgetExceeded {
            XCTAssertFalse(requestWasMade, "should refuse before making the network call at all")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
