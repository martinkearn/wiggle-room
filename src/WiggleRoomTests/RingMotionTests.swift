//
//  RingMotionTests.swift
//  WiggleRoomTests
//

import XCTest
import SwiftUI
@testable import WiggleRoom

final class RingMotionTests: XCTestCase {

    private let readingA = UUID()
    private let readingB = UUID()

    private func key(_ outer: Double, _ inner: Double, reading: UUID?) -> RingMotion.Key {
        RingMotion.Key(outer: outer, inner: inner, readingID: reading)
    }

    // MARK: - Arrival

    func testAnyChangeBeforeArrivalSettlesRedirectsTheArrival() {
        let old = key(0.4, 0.3, reading: readingA)
        let changes = [
            key(0.4, 0.3, reading: readingB),
            key(0.6, 0.5, reading: readingA),
            key(0.4001, 0.3, reading: readingA),
        ]
        for new in changes {
            XCTAssertEqual(RingMotion.reason(from: old, to: new, hasArrived: false), .arrival)
        }
    }

    // MARK: - Update

    func testANewReadingIsAnUpdate() {
        let old = key(0.4, 0.3, reading: readingA)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.4, 0.35, reading: readingB), hasArrived: true), .update)
    }

    func testReloggingTheSameFigureIsStillAnUpdate() {
        let old = key(0.4, 0.3, reading: readingA)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.4, 0.3, reading: readingB), hasArrived: true), .update)
    }

    func testTheFirstReadingIsAnUpdate() {
        let old = key(0.4, 0, reading: nil)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.4, 0.2, reading: readingA), hasArrived: true), .update)
    }

    func testRemovingTheLatestReadingIsAnUpdate() {
        let old = key(0.4, 0.3, reading: readingB)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.4, 0.2, reading: readingA), hasArrived: true), .update)
    }

    // MARK: - Drift and its minimum delta

    func testATargetMovingWithTheSameReadingDriftsOnlyTheRingThatMoved() {
        let old = key(0.4, 0.3, reading: readingA)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.41, 0.3, reading: readingA), hasArrived: true),
                       .drift(outer: true, inner: false))
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.4, 0.28, reading: readingA), hasArrived: true),
                       .drift(outer: false, inner: true))
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.41, 0.28, reading: readingA), hasArrived: true),
                       .drift(outer: true, inner: true))
    }

    func testAChangeBelowTheMinimumDeltaSettlesWithoutMoving() {
        let old = key(0.4, 0.3, reading: readingA)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.402, 0.2981, reading: readingA), hasArrived: true), .settle)
        XCTAssertEqual(RingMotion.reason(from: old, to: old, hasArrived: true), .settle)
    }

    func testTheMinimumDeltaItselfDrifts() {
        let old = key(0, 0, reading: readingA)
        XCTAssertEqual(RingMotion.reason(from: old, to: key(RingMotion.minimumDriftDelta, 0, reading: readingA), hasArrived: true),
                       .drift(outer: true, inner: false))
        XCTAssertEqual(RingMotion.reason(from: old, to: key(0.0024, 0, reading: readingA), hasArrived: true), .settle)
    }

    /// The gate is measured from what was last drawn, so a slow clock's
    /// sub-threshold ticks add up to a drift rather than never moving.
    func testSubThresholdTicksAccumulateFromTheDrawnKey() {
        let drawn = key(0.4, 0.3, reading: readingA)
        var reasons: [RingMotion] = []
        for tick in 1...3 {
            let now = key(0.4 + Double(tick) * 0.001, 0.3, reading: readingA)
            reasons.append(RingMotion.reason(from: drawn, to: now, hasArrived: true))
        }
        XCTAssertEqual(reasons, [.settle, .settle, .drift(outer: true, inner: false)])
    }

    // MARK: - Spring jitter

    func testJitterStaysWithinTenPercent() {
        let base = RingMotion.driftReturnSpring
        for _ in 0..<200 {
            let spring = base.jittered()
            XCTAssertEqual(spring.response, base.response, accuracy: base.response * 0.1 + 1e-9)
            XCTAssertEqual(spring.dampingRatio, base.dampingRatio, accuracy: base.dampingRatio * 0.1 + 1e-9)
        }
    }
}
