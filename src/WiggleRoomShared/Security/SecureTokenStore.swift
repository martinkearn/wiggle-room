//
//  SecureTokenStore.swift
//  WiggleRoom
//

import Foundation
import Security

/// Where a connected source's auth token (a Starling personal access token,
/// a future Tesla OAuth token, …) is read and written. Abstracted behind a
/// protocol so provider code can be unit-tested against `InMemoryTokenStore`
/// without touching the real Keychain, which isn't available in a plain
/// XCTest/SPM test run.
protocol SecureTokenStore {
    func save(token: String, for key: String) throws
    func loadToken(for key: String) throws -> String?
    func deleteToken(for key: String) throws
}

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case unexpectedData
}

/// Keychain-backed secure token storage (§5.3/§11) — `kSecAttrSynchronizable`
/// is set so a token syncs via iCloud Keychain across the user's own
/// devices without needing re-entry per device. Never stores a token in
/// UserDefaults or a plain file.
///
/// `nonisolated`: plain synchronous Keychain/Security calls, with no
/// reason to be confined to the main actor — explicit rather than left to
/// this project's default main-actor isolation, so it's safe to call from
/// any context (this type's methods satisfy `SecureTokenStore`'s
/// synchronous, non-`async` requirements, which a main-actor-isolated
/// conformance couldn't).
nonisolated final class KeychainTokenStore: SecureTokenStore {
    private let service: String

    init(service: String = "martinkearn.WiggleRoom.connectedSource") {
        self.service = service
    }

    func save(token: String, for key: String) throws {
        // Clear out any existing item first — SecItemAdd fails on a
        // duplicate rather than overwriting, and a token can legitimately be
        // re-saved (e.g. reconnecting after revoking the old one).
        try? deleteToken(for: key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func loadToken(for key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return token
    }

    func deleteToken(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: true
        ]
    }
}

/// In-memory stand-in for previews and unit tests — never used for a real
/// token, since nothing here is actually secure storage. `nonisolated` for
/// the same reason as `KeychainTokenStore` above.
nonisolated final class InMemoryTokenStore: SecureTokenStore {
    private var storage: [String: String] = [:]

    func save(token: String, for key: String) throws {
        storage[key] = token
    }

    func loadToken(for key: String) throws -> String? {
        storage[key]
    }

    func deleteToken(for key: String) throws {
        storage.removeValue(forKey: key)
    }
}
