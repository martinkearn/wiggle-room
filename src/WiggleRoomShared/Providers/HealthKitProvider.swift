//
//  HealthKitProvider.swift
//  WiggleRoom
//

import Foundation
#if os(iOS)
import HealthKit
#endif

enum HealthKitProviderError: Error, Equatable {
    /// HealthKit can't be read on this device at all — every platform but
    /// iOS and iPadOS, or an iOS-family device with no Health store.
    case notAvailable
    /// Health holds no body-mass sample. Not a failure: either nothing has
    /// ever been recorded, or read access was refused, and HealthKit
    /// deliberately doesn't say which (see `HealthKitProvider`).
    case noReadings
    /// Apple Health is read-only in this app — nothing is ever written back
    /// to Health, so a correction is logged as an ordinary reading via
    /// `TrackerStore.logReading` instead.
    case manualLoggingNotSupported
}

/// The reading side of Apple Health, behind a protocol so the provider's own
/// rules — which unit to ask for, rounding, the single measurement it
/// offers — are testable without a real Health store, a device, or the
/// HealthKit entitlement.
protocol BodyMassSource {
    /// Whether this device can be read at all.
    var isAvailable: Bool { get }

    /// Asks Health for read access to body mass. Health answers by showing
    /// its own permission sheet; it never reports the decision back.
    func requestReadAuthorization() async throws

    /// The most recently recorded body mass in `unit`, or `nil` when Health
    /// holds none.
    func latestBodyMass(in unit: TrackerUnit) async throws -> SourceReading?
}

/// Stands in wherever HealthKit isn't read: macOS, which has no HealthKit at
/// all, and watchOS, which has it but deliberately doesn't read it in this
/// version (a watch would need its own entitlement and its own
/// authorisation). Everything it backs reports unavailable, which
/// `TrackerStore.refreshFromSource` turns into a silent no-op rather than an
/// error — the read-only view of a Health-backed tracker on those platforms.
@MainActor
final class UnavailableBodyMassSource: BodyMassSource {
    static let shared = UnavailableBodyMassSource()

    nonisolated var isAvailable: Bool { false }

    func requestReadAuthorization() async throws {
        throw HealthKitProviderError.notAvailable
    }

    func latestBodyMass(in unit: TrackerUnit) async throws -> SourceReading? {
        throw HealthKitProviderError.notAvailable
    }
}

#if os(iOS)
/// The real thing: one `HKHealthStore` for the process (HealthKit
/// discourages creating them freely), a read-only body-mass authorisation,
/// and a single-sample query for the latest weight.
@MainActor
final class HealthKitBodyMassSource: BodyMassSource {
    static let shared = HealthKitBodyMassSource()

    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)

    nonisolated var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// `toShare` is deliberately empty: the app asks for read access only,
    /// and there is no `NSHealthUpdateUsageDescription` in the Info.plist to
    /// support writing even if some future call tried to.
    func requestReadAuthorization() async throws {
        guard isAvailable else { throw HealthKitProviderError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: [bodyMass])
    }

    /// The most recent sample, whatever recorded it — a smart scale, the
    /// Health app, or another app entirely. Samples aren't filtered by
    /// source: the latest recorded weight is the answer regardless of which
    /// device wrote it.
    ///
    /// `end: .now` excludes a future-dated sample, which would otherwise win
    /// the sort and report a weight that hasn't happened yet.
    func latestBodyMass(in unit: TrackerUnit) async throws -> SourceReading? {
        guard isAvailable else { throw HealthKitProviderError.notAvailable }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                .quantitySample(
                    type: bodyMass,
                    predicate: HKQuery.predicateForSamples(withStart: nil, end: .now)
                )
            ],
            sortDescriptors: [SortDescriptor<HKQuantitySample>(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        let value = sample.quantity.doubleValue(for: Self.healthKitUnit(for: unit))
        return SourceReading(value: Decimal(value), date: sample.endDate)
    }

    private static func healthKitUnit(for unit: TrackerUnit) -> HKUnit {
        switch unit {
        case .pounds: .pound()
        default: .gramUnit(with: .kilo)
        }
    }
}
#endif

/// The Apple Health source provider: body mass, read-only, for Weight loss
/// trackers.
///
/// Read-only in the strongest sense — the app asks for no write access, so a
/// weight typed by hand in Balance History stays in Wiggle Room and is never
/// pushed back into Health. HealthKit only ever exposes the Health store of
/// the person signed in on the device; there is no API for anyone else's
/// health data and none is sought.
///
/// Unlike Starling there is **no credential**: `ConnectedSource
/// .credentialToken` stays `nil` for a Health source and is never read.
/// Authorisation lives in the system's own Health permissions, per device,
/// and cannot be synced or inspected by the app. HealthKit deliberately
/// never reports read permission back — a refusal is indistinguishable from
/// an empty Health store — so nothing in the app claims to know whether
/// access was granted. Both outcomes look the same here: no samples, no
/// error, no reading logged.
///
/// Exactly one Health source is ever created (it is the device owner's own
/// Health store, so a second would mean nothing); `AddSourcePickerView`
/// hides the option once one exists, including one that arrived by CloudKit
/// sync from another device.
@MainActor
final class HealthKitProvider: SourceProvider {
    nonisolated let providerId = "healthkit"
    nonisolated let displayName = "Apple Health"
    /// Authorisation is a real setup step, even with no credential to store.
    nonisolated let requiresConnection = true
    /// Body mass backs a weight tracker and nothing else. The plain-number
    /// types could technically hold a weight, but a source that promises
    /// "weight" should only be offered where the tracker means it.
    nonisolated let supportedTrackerTypes: Set<TrackerType> = [.weightLoss]
    nonisolated let targetLabel = "Measurement"

    private let source: BodyMassSource

    /// `source` defaults to `nil` rather than resolving the platform's own
    /// source as a default argument — under this project's default
    /// main-actor isolation a default-argument expression runs in the
    /// caller's context rather than this initializer's, so it's resolved
    /// here in the body instead (the same reason `StarlingProvider` resolves
    /// its budget this way).
    init(source: BodyMassSource? = nil) {
        if let source {
            self.source = source
        } else {
            #if os(iOS)
            self.source = HealthKitBodyMassSource.shared
            #else
            self.source = UnavailableBodyMassSource.shared
            #endif
        }
    }

    var isAvailableOnThisDevice: Bool { source.isAvailable }

    /// One target, always — the body-mass measurement. A plain static value
    /// with no HealthKit call behind it, so it resolves on every platform:
    /// that is what keeps a Health-backed tracker's caption reading
    /// "Apple Health · Weight" on a Mac instead of falling back to the raw
    /// `bodyMass` id.
    func listAvailableTargets(for connection: ConnectedSource) async throws -> [SourceTarget] {
        [Self.weightTarget]
    }

    /// The target every Health-backed tracker binds to. Its `unit` is filled
    /// in per request by whoever is asking (see `SourceTarget.unit`).
    static let weightTarget = SourceTarget(id: "bodyMass", displayName: "Weight")

    func fetchCurrentValue(target: SourceTarget) async throws -> Decimal {
        try await fetchCurrentReading(target: target).value
    }

    /// Rounded at the requested unit's own precision before it leaves here.
    /// Health stores a weight as a double, so an 84.6 kg reading can arrive
    /// as 84.63999…; unrounded, that counts as a change on every single poll
    /// and churns the reading history at a precision the app never displays.
    func fetchCurrentReading(target: SourceTarget) async throws -> SourceReading {
        guard source.isAvailable else { throw HealthKitProviderError.notAvailable }
        let unit = target.unit.flatMap(TrackerUnit.init(rawValue:)) ?? .kilograms
        guard let reading = try await source.latestBodyMass(in: unit) else {
            throw HealthKitProviderError.noReadings
        }
        return SourceReading(value: unit.rounded(reading.value), date: reading.date)
    }

    func logManualReading(target: SourceTarget, value: Decimal, date: Date) async throws {
        throw HealthKitProviderError.manualLoggingNotSupported
    }

    /// Called only from the connect screen (`AddHealthSourceView`). No
    /// polling path ever asks for authorisation: a query made without it
    /// simply returns no samples, so opening a tracker can never trigger a
    /// permission sheet.
    func requestAuthorization() async throws {
        try await source.requestReadAuthorization()
    }
}
