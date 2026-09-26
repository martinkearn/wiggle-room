//
//  SourceProvider.swift
//  WiggleRoom
//

import Foundation

/// The common interface every data source (Starling, Tesla, manual entry,
/// and any future source) implements, isolated from tracker/calculation
/// logic. See spec §5.1.
///
/// Class-constrained because every conformer is a `final class` and
/// `TrackerStore`'s tests rely on `===` identity to confirm `provider(for:)`
/// resolved to its shared `manualProvider` instance rather than a new one.
protocol SourceProvider: AnyObject {
    /// Identifies the provider type, e.g. `"starling"`, `"manual"`.
    var providerId: String { get }

    /// User-facing name, e.g. "Starling", "Manual entry".
    var displayName: String { get }

    /// Whether this provider needs an auth/setup step before use (true for
    /// Starling, false for manual).
    var requiresConnection: Bool { get }

    /// The tracker types this provider can actually back. Declared by the
    /// provider rather than hard-coded per type, so adding a vehicle or
    /// health source later is a change in one file: Starling can only
    /// sensibly supply a money balance, a future Tesla source only mileage,
    /// while manual entry suits every type. Add Tracker filters its source
    /// list through this once a type is chosen.
    var supportedTrackerTypes: Set<TrackerType> { get }

    /// The word a screen should use for one of this provider's targets.
    /// "Account" fits a bank; Apple Health offers a measurement rather than
    /// an account, and a weight tracker reporting its "Account" as "Weight"
    /// reads as a mistake. Defaulted, so only a provider that needs another
    /// word says so.
    var targetLabel: String { get }

    /// Whether this provider can actually be read on the device running
    /// right now. False for a device-bound provider on a platform that has
    /// no such device data: Apple Health does not exist on macOS at all, and
    /// this version deliberately doesn't read it on the watch either.
    ///
    /// `TrackerStore.refreshFromSource` skips an unavailable provider
    /// entirely — no attempt, no error — which is what lets a Mac show a
    /// Health-backed tracker as a calm read-only view of readings its owner's
    /// iPhone fetched, rather than a tracker that permanently fails to
    /// update. Defaulted to true, since every network-backed provider works
    /// anywhere.
    var isAvailableOnThisDevice: Bool { get }

    /// The targets currently available within a connected instance of this
    /// provider — e.g. Starling's accounts/Spaces, or a manual source's
    /// named logs.
    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget]

    /// The current value for a target — a live read for auto-fetch
    /// providers, or the latest logged reading for manual ones.
    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal

    /// The current value for a target together with the moment it belongs
    /// to. Defaulted to `fetchCurrentValue` dated now, which is the truth
    /// for a live-balance provider; a provider that reports historic
    /// readings (Apple Health) overrides it with the reading's own
    /// timestamp.
    func fetchCurrentReading(target: SourceTarget) async throws -> SourceReading

    /// Records a manually-entered reading for a target. Supported by
    /// manual-type providers, and usable as an override/correction path
    /// even for auto-fetch providers.
    func logManualReading(target: SourceTarget, value: Decimal, date: Date) async throws
}

extension SourceProvider {
    var targetLabel: String { "Account" }

    var isAvailableOnThisDevice: Bool { true }

    func fetchCurrentReading(target: SourceTarget) async throws -> SourceReading {
        let value = try await fetchCurrentValue(target: target)
        return SourceReading(value: value, date: .now)
    }
}
