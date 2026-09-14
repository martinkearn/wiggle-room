//
//  SourceTarget.swift
//  Ringet
//

import Foundation

/// A specific target within a `ConnectedSource` that a tracker can read
/// from — e.g. a Starling `accountUid`, or a named manual log. See spec §5.1.
struct SourceTarget: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String
}
