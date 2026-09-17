//
//  StarlingProviderTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

@MainActor
final class StarlingProviderTests: XCTestCase {

    func testProviderIdentity() {
        let provider = StarlingProvider()

        XCTAssertEqual(provider.providerId, "starling")
        XCTAssertEqual(provider.displayName, "Starling")
        XCTAssertTrue(provider.requiresConnection)
    }

    func testFetchCurrentValue_withNoBoundConnection_throwsNotConnected() async {
        let provider = StarlingProvider(connection: nil)
        let target = SourceTarget(id: "abc-123", displayName: "Personal")

        do {
            _ = try await provider.fetchCurrentValue(target: target)
            XCTFail("expected notConnected")
        } catch StarlingProviderError.notConnected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchCurrentValue_connectionWithNoStoredToken_throwsNotConnected() async {
        let source = ConnectedSource(providerId: "starling", displayName: "My Starling", credentialToken: nil)
        let provider = StarlingProvider(connection: source)
        let target = SourceTarget(id: "abc-123", displayName: "Personal")

        do {
            _ = try await provider.fetchCurrentValue(target: target)
            XCTFail("expected notConnected")
        } catch StarlingProviderError.notConnected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testListAvailableTargets_connectionWithNoStoredToken_throwsNotConnected() async {
        let source = ConnectedSource(providerId: "starling", displayName: "My Starling", credentialToken: nil)
        let provider = StarlingProvider()

        do {
            _ = try await provider.listAvailableTargets(for: source)
            XCTFail("expected notConnected")
        } catch StarlingProviderError.notConnected {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLogManualReading_isNotSupported() async {
        let provider = StarlingProvider()
        let target = SourceTarget(id: "abc-123", displayName: "Personal")

        do {
            try await provider.logManualReading(target: target, value: 100, date: .now)
            XCTFail("expected manualLoggingNotSupported")
        } catch StarlingProviderError.manualLoggingNotSupported {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
