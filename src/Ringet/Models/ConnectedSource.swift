//
//  ConnectedSource.swift
//  Ringet
//

import Foundation
import SwiftData

/// A configured instance of a provider — e.g. "My Starling account" — kept
/// separate from individual trackers so multiple trackers can share one
/// connection. See spec §5.2.
@Model
final class ConnectedSource {
    var id: UUID = UUID()
    var providerId: String = ""
    var displayName: String = ""
    var credentialKeychainKey: String?

    /// Every tracker currently pointed at this source. CloudKit requires
    /// every relationship to declare its inverse — this is the other side
    /// of `Tracker.connectedSource`. Optional array for CloudKit
    /// compatibility, per SwiftData's requirements.
    @Relationship(inverse: \Tracker.connectedSource)
    var trackers: [Tracker]? = []

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
