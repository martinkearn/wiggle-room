//
//  ConnectedSource.swift
//  Ringet
//

import Foundation

/// A configured instance of a provider — e.g. "My Starling account" — kept
/// separate from individual trackers so multiple trackers can share one
/// connection. See spec §5.2.
struct ConnectedSource: Identifiable, Codable, Equatable {
    var id: UUID
    var providerId: String
    var displayName: String
    var credentialKeychainKey: String?

    init(
        id: UUID = UUID(),
        providerId: String,
        displayName: String,
        credentialKeychainKey: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.displayName = displayName
        self.credentialKeychainKey = credentialKeychainKey
    }
}
