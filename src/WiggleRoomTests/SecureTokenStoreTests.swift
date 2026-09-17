//
//  SecureTokenStoreTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

/// Covers `InMemoryTokenStore` only — the real `KeychainTokenStore` needs
/// actual Keychain access (a signed test bundle with the right entitlement),
/// which isn't reliably available outside a real simulator/device run. See
/// progress-notes.md for this session's build-verification caveats.
final class SecureTokenStoreTests: XCTestCase {

    func testSaveThenLoad_returnsTheSameToken() throws {
        let store = InMemoryTokenStore()

        try store.save(token: "abc123", for: "starling.source-1")

        XCTAssertEqual(try store.loadToken(for: "starling.source-1"), "abc123")
    }

    func testLoad_unknownKey_returnsNil() throws {
        let store = InMemoryTokenStore()

        XCTAssertNil(try store.loadToken(for: "no-such-key"))
    }

    func testSave_overwritesExistingTokenForSameKey() throws {
        let store = InMemoryTokenStore()
        try store.save(token: "old", for: "starling.source-1")

        try store.save(token: "new", for: "starling.source-1")

        XCTAssertEqual(try store.loadToken(for: "starling.source-1"), "new")
    }

    func testDelete_removesToken() throws {
        let store = InMemoryTokenStore()
        try store.save(token: "abc123", for: "starling.source-1")

        try store.deleteToken(for: "starling.source-1")

        XCTAssertNil(try store.loadToken(for: "starling.source-1"))
    }

    func testDifferentKeys_areIndependent() throws {
        let store = InMemoryTokenStore()
        try store.save(token: "token-a", for: "starling.source-a")
        try store.save(token: "token-b", for: "starling.source-b")

        XCTAssertEqual(try store.loadToken(for: "starling.source-a"), "token-a")
        XCTAssertEqual(try store.loadToken(for: "starling.source-b"), "token-b")
    }
}
