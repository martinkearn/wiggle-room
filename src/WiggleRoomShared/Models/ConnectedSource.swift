//
//  ConnectedSource.swift
//  WiggleRoom
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

    /// The provider's auth token (a Starling personal access token, a
    /// future Tesla OAuth token, …), stored directly on this record rather
    /// than in the Keychain — deliberately, so it syncs via the exact same
    /// CloudKit private-database sync as every other piece of the user's
    /// own data (§6, §11), instead of relying on iCloud Keychain, a
    /// separate sync system with its own on/off toggle per device that can
    /// lag CloudKit noticeably or never sync at all if a device hasn't
    /// enabled it. Still scoped to the user's own private CloudKit
    /// database under their own Apple ID — never transmitted anywhere but
    /// Starling itself and Apple's own sync infrastructure.
    var credentialToken: String?

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
        credentialToken: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.displayName = displayName
        self.credentialToken = credentialToken
    }
}
