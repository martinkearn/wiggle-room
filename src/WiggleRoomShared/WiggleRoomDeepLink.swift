//
//  WiggleRoomDeepLink.swift
//  WiggleRoomShared
//

import Foundation

/// The single source of truth for the `wiggleroom://tracker/<uuid>` URL
/// format used to deep-link straight into a specific tracker's dashboard —
/// built by a Home Screen/Lock Screen widget's `.widgetURL`, and parsed by
/// the main app's `.onOpenURL`. Kept in one place so the two sides can never
/// drift out of sync on the scheme/host/path shape.
enum WiggleRoomDeepLink {
    private static let scheme = "wiggleroom"
    private static let trackerHost = "tracker"

    static func url(forTrackerId id: UUID) -> URL {
        URL(string: "\(scheme)://\(trackerHost)/\(id.uuidString)")!
    }

    /// Returns the tracker id encoded in a `wiggleroom://tracker/<uuid>`
    /// URL, or `nil` if this isn't one of ours (a different scheme, a
    /// malformed id, etc.) — callers should silently ignore a `nil` rather
    /// than treat it as an error.
    static func trackerId(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == trackerHost else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
