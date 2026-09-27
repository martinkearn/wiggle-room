//
//  TrackerHapticsTests.swift
//  WiggleRoomTests
//

import XCTest
import SwiftUI
@testable import WiggleRoom

@MainActor
final class TrackerHapticsTests: XCTestCase {

    private let trackerA = UUID()
    private let trackerB = UUID()
    private let reading1 = UUID()
    private let reading2 = UUID()
    private let reading3 = UUID()

    private func pulse(_ id: UUID, _ reading: UUID?, _ status: PaceStatus?) -> TrackerPulse {
        TrackerPulse(id: id, readingID: reading, status: status)
    }

    func testNothingChangingIsSilent() {
        let pulses = [pulse(trackerA, reading1, .good), pulse(trackerB, nil, nil)]
        XCTAssertNil(TrackerHapticEvent.between(pulses, pulses))
    }

    func testANewReadingLands() {
        XCTAssertEqual(TrackerHapticEvent.between([pulse(trackerA, reading1, .good)],
                                                  [pulse(trackerA, reading2, .good)]),
                       .readingLanded)
    }

    func testTheFirstReadingLandsWithoutCountingAsACrossing() {
        XCTAssertEqual(TrackerHapticEvent.between([pulse(trackerA, nil, nil)],
                                                  [pulse(trackerA, reading1, .bad)]),
                       .readingLanded)
    }

    func testTheClockCrossingThePaceLineIsFeltWithoutANewReading() {
        XCTAssertEqual(TrackerHapticEvent.between([pulse(trackerA, reading1, .warning)],
                                                  [pulse(trackerA, reading1, .good)]),
                       .paceCrossed(into: .good))
    }

    func testACrossingWinsOverTheReadingThatCausedIt() {
        XCTAssertEqual(TrackerHapticEvent.between([pulse(trackerA, reading1, .good)],
                                                  [pulse(trackerA, reading2, .bad)]),
                       .paceCrossed(into: .bad))
    }

    func testSeveralTrackersChangingAtOnceMakeOneEventTheWorstCrossing() {
        let old = [pulse(trackerA, reading1, .good), pulse(trackerB, reading2, .good)]
        let new = [pulse(trackerA, reading3, .warning), pulse(trackerB, reading2, .bad)]
        XCTAssertEqual(TrackerHapticEvent.between(old, new), .paceCrossed(into: .bad))
    }

    func testAReadingOnOneTrackerAndACrossingOnAnotherIsTheCrossing() {
        let old = [pulse(trackerA, reading1, .good), pulse(trackerB, reading2, .bad)]
        let new = [pulse(trackerA, reading3, .good), pulse(trackerB, reading2, .warning)]
        XCTAssertEqual(TrackerHapticEvent.between(old, new), .paceCrossed(into: .warning))
    }

    func testAddingOrRemovingATrackerIsSilent() {
        let one = [pulse(trackerA, reading1, .good)]
        let two = one + [pulse(trackerB, reading2, .bad)]
        XCTAssertNil(TrackerHapticEvent.between(one, two))
        XCTAssertNil(TrackerHapticEvent.between(two, one))
    }

    func testReorderingTrackersIsSilent() {
        let pulses = [pulse(trackerA, reading1, .good), pulse(trackerB, reading2, .bad)]
        XCTAssertNil(TrackerHapticEvent.between(pulses, pulses.reversed()))
    }

    func testFeedbackWeights() {
        XCTAssertEqual(TrackerHapticEvent.readingLanded.feedback, .impact(weight: .light))
        XCTAssertEqual(TrackerHapticEvent.paceCrossed(into: .good).feedback, .success)
        XCTAssertEqual(TrackerHapticEvent.paceCrossed(into: .warning).feedback, .warning)
        XCTAssertEqual(TrackerHapticEvent.paceCrossed(into: .bad).feedback, .error)
    }
}
