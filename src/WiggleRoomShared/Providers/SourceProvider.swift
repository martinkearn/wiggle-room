//
//  SourceProvider.swift
//  WiggleRoom
//

import Foundation

/// The common interface every data source (Starling, Tesla, manual entry,
/// and any future source) implements, isolated from tracker/calculation
/// logic. See spec §5.1.
protocol SourceProvider {
    /// Identifies the provider type, e.g. `"starling"`, `"manual"`.
    var providerId: String { get }

    /// User-facing name, e.g. "Starling", "Manual entry".
    var displayName: String { get }

    /// Whether this provider needs an auth/setup step before use (true for
    /// Starling, false for manual).
    var requiresConnection: Bool { get }

    /// The targets currently available within a connected instance of this
    /// provider — e.g. Starling's accounts/Spaces, or a manual source's
    /// named logs.
    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget]

    /// The current value for a target — a live read for auto-fetch
    /// providers, or the latest logged reading for manual ones.
    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal

    /// Records a manually-entered reading for a target. Supported by
    /// manual-type providers, and usable as an override/correction path
    /// even for auto-fetch providers.
    func logManualReading(target: SourceTarget, value: Decimal, date: Date) async throws
}
