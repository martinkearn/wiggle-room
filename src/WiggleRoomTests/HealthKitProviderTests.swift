//
//  HealthKitProviderTests.swift
//  WiggleRoomTests
//

import XCTest
@testable import WiggleRoom

/// A stand-in Health store. The provider's own rules — which unit it asks
/// for, rounding, the single measurement it offers, what "no weight" means —
/// are testable without a real Health store, a device, or the HealthKit
/// entitlement.
@MainActor
private final class FakeBodyMassSource: BodyMassSource {
    var isAvailable: Bool
    var reading: SourceReading?
    /// The unit the provider actually asked for, so a test can assert the
    /// tracker's own unit reached HealthKit rather than a default.
    private(set) var requestedUnits: [TrackerUnit] = []
    private(set) var authorizationRequestCount = 0

    init(isAvailable: Bool = true, reading: SourceReading? = nil) {
        self.isAvailable = isAvailable
        self.reading = reading
    }

    func requestReadAuthorization() async throws {
        authorizationRequestCount += 1
    }

    func latestBodyMass(in unit: TrackerUnit) async throws -> SourceReading? {
        requestedUnits.append(unit)
        return reading
    }
}

@MainActor
final class HealthKitProviderTests: XCTestCase {
    private func makeProvider(
        isAvailable: Bool = true,
        value: Decimal? = nil,
        date: Date = Date()
    ) -> (HealthKitProvider, FakeBodyMassSource) {
        let source = FakeBodyMassSource(
            isAvailable: isAvailable,
            reading: value.map { SourceReading(value: $0, date: date) }
        )
        return (HealthKitProvider(source: source), source)
    }

    func testIdentity_backsWeightLossOnlyAndNamesItsTargetAMeasurement() {
        let (provider, _) = makeProvider()

        XCTAssertEqual(provider.providerId, "healthkit")
        XCTAssertEqual(provider.displayName, "Apple Health")
        XCTAssertTrue(provider.requiresConnection)
        XCTAssertEqual(provider.supportedTrackerTypes, [.weightLoss])
        XCTAssertEqual(provider.targetLabel, "Measurement")
    }

    func testListAvailableTargets_isAlwaysTheSingleWeightMeasurement() async throws {
        // Unavailable on purpose: the target list is a static value with no
        // HealthKit call behind it, so it still resolves on a Mac — which is
        // what keeps a tracker's caption reading "Apple Health · Weight"
        // there instead of the raw `bodyMass` id.
        let (provider, _) = makeProvider(isAvailable: false)
        let connection = ConnectedSource(providerId: "healthkit", displayName: "Apple Health")

        let targets = try await provider.listAvailableTargets(for: connection)

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, "bodyMass")
        XCTAssertEqual(targets.first?.displayName, "Weight")
    }

    func testFetchCurrentReading_asksForTheTargetsOwnUnit() async throws {
        let (provider, source) = makeProvider(value: Decimal(string: "84.6")!)
        let target = SourceTarget(id: "bodyMass", displayName: "Weight", unit: TrackerUnit.pounds.rawValue)

        _ = try await provider.fetchCurrentReading(target: target)

        XCTAssertEqual(source.requestedUnits, [.pounds])
    }

    func testFetchCurrentReading_withNoUnitRequested_readsKilograms() async throws {
        let (provider, source) = makeProvider(value: Decimal(string: "84.6")!)

        _ = try await provider.fetchCurrentReading(target: HealthKitProvider.weightTarget)

        XCTAssertEqual(source.requestedUnits, [.kilograms])
    }

    func testFetchCurrentReading_roundsKilogramsToOneDecimalPlace() async throws {
        // Health stores weight as a double, so a scale reading of 84.6 kg can
        // arrive with a tail of decimals the app never displays.
        let (provider, _) = makeProvider(value: Decimal(string: "84.63999")!)
        let target = SourceTarget(id: "bodyMass", displayName: "Weight", unit: TrackerUnit.kilograms.rawValue)

        let reading = try await provider.fetchCurrentReading(target: target)

        XCTAssertEqual(reading.value, Decimal(string: "84.6")!)
    }

    func testFetchCurrentReading_roundsPoundsToAWholeNumber() async throws {
        let (provider, _) = makeProvider(value: Decimal(string: "186.4")!)
        let target = SourceTarget(id: "bodyMass", displayName: "Weight", unit: TrackerUnit.pounds.rawValue)

        let reading = try await provider.fetchCurrentReading(target: target)

        // A zero-precision unit rounds up, as it does everywhere else.
        XCTAssertEqual(reading.value, 187)
    }

    func testFetchCurrentReading_keepsTheSamplesOwnTimestamp() async throws {
        let weighIn = Date().addingTimeInterval(-13 * 3600)
        let (provider, _) = makeProvider(value: Decimal(string: "84.6")!, date: weighIn)

        let reading = try await provider.fetchCurrentReading(target: HealthKitProvider.weightTarget)

        XCTAssertEqual(reading.date, weighIn)
    }

    func testFetchCurrentReading_withNoWeightRecorded_throwsNoReadings() async {
        let (provider, _) = makeProvider(value: nil)

        do {
            _ = try await provider.fetchCurrentReading(target: HealthKitProvider.weightTarget)
            XCTFail("expected noReadings")
        } catch HealthKitProviderError.noReadings {
            // Expected — an empty Health store and refused access look
            // identical, deliberately, and neither is a failure.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnavailableDevice_reportsUnavailableAndRefusesToFetch() async {
        let (provider, _) = makeProvider(isAvailable: false, value: Decimal(string: "84.6")!)

        XCTAssertFalse(provider.isAvailableOnThisDevice)
        do {
            _ = try await provider.fetchCurrentReading(target: HealthKitProvider.weightTarget)
            XCTFail("expected notAvailable")
        } catch HealthKitProviderError.notAvailable {
            // Expected — `TrackerStore.refreshFromSource` never gets this
            // far, because it checks `isAvailableOnThisDevice` first.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAvailableDevice_reportsAvailable() {
        let (provider, _) = makeProvider()

        XCTAssertTrue(provider.isAvailableOnThisDevice)
    }

    func testLogManualReading_isNotSupported() async {
        let (provider, _) = makeProvider()

        do {
            try await provider.logManualReading(target: HealthKitProvider.weightTarget, value: 84, date: Date())
            XCTFail("expected manualLoggingNotSupported")
        } catch HealthKitProviderError.manualLoggingNotSupported {
            // Expected — the app asks for no write access, so a weight typed
            // by hand stays in Wiggle Room and is never pushed into Health.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRequestAuthorization_asksTheStoreOnce() async throws {
        let (provider, source) = makeProvider()

        try await provider.requestAuthorization()

        XCTAssertEqual(source.authorizationRequestCount, 1)
    }
}
