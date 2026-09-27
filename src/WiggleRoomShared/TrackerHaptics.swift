//
//  TrackerHaptics.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// The two things about a tracker that earn a haptic: its latest reading
/// and which side of the pace line it is on. `status` is `nil` until the
/// tracker has a reading, since there is no pace to cross before then.
struct TrackerPulse: Equatable {
    var id: UUID
    var readingID: UUID?
    var status: PaceStatus?
}

extension TrackerPulse {
    init(tracker: Tracker, now: Date) {
        let reading = tracker.latestReading
        self.init(id: tracker.id,
                  readingID: reading?.id,
                  status: reading.map { tracker.pace(actualValue: $0.value, asOf: now).status })
    }
}

/// A moment worth feeling in the hand as well as seeing (§6, Haptics).
enum TrackerHapticEvent: Equatable {
    /// A tracker's latest reading changed — the same change that plays the
    /// rings' update animation, whether logged or fetched.
    case readingLanded
    /// A tracker's pace status changed — the same change that cross-fades
    /// its status colour.
    case paceCrossed(into: PaceStatus)

    /// The one event between two snapshots of every tracker, or `nil`.
    /// Several trackers changing at once, such as a background refresh,
    /// still make a single event: a crossing wins over a reading, and the
    /// worst crossing wins over the others. Trackers added or removed in
    /// between are ignored — neither is a reading landing.
    static func between(_ old: [TrackerPulse], _ new: [TrackerPulse]) -> TrackerHapticEvent? {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var crossings: [PaceStatus] = []
        var readingLanded = false
        for pulse in new {
            guard let previous = before[pulse.id] else { continue }
            if let was = previous.status, let now = pulse.status, was != now {
                crossings.append(now)
            }
            if previous.readingID != pulse.readingID {
                readingLanded = true
            }
        }
        if let worst = crossings.max(by: { severity($0) < severity($1) }) {
            return .paceCrossed(into: worst)
        }
        return readingLanded ? .readingLanded : nil
    }

    private static func severity(_ status: PaceStatus) -> Int {
        switch status {
        case .good: 0
        case .warning: 1
        case .bad: 2
        }
    }

    /// A light tap for a reading. A crossing is weighted by where it
    /// landed: warning into amber, error into red, success back to green.
    var feedback: SensoryFeedback {
        switch self {
        case .readingLanded: .impact(weight: .light)
        case .paceCrossed(into: .good): .success
        case .paceCrossed(into: .warning): .warning
        case .paceCrossed(into: .bad): .error
        }
    }
}

extension View {
    /// Plays `TrackerHapticEvent`s for `trackers`. Apply once per device, at
    /// a view that stays alive while any tracker is on screen — never inside
    /// a row or `RingsView`, which would fire once per visible surface for
    /// the same event. `now` should be the clock the list itself shows, so
    /// a crossing is felt when it is seen. A no-op where the platform has no
    /// haptics, and deliberately not gated on Reduce Motion: it keeps these
    /// moments marked for someone who has turned the ring animation off.
    func trackerHaptics(for trackers: [Tracker], now: Date) -> some View {
        background {
            TrackerHaptics(trackers: trackers, now: now)
        }
    }
}

/// A separate view so the SwiftData reads that feed the haptics invalidate
/// only this empty view, not whichever screen it is attached to.
private struct TrackerHaptics: View {
    let trackers: [Tracker]
    let now: Date

    /// Skips trackers mid-deletion: reading any property on one is a hard
    /// SwiftData crash (see `RingsView`'s own guard).
    private var pulses: [TrackerPulse] {
        trackers
            .filter { $0.modelContext != nil }
            .map { TrackerPulse(tracker: $0, now: now) }
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .sensoryFeedback(trigger: pulses) { old, new in
                TrackerHapticEvent.between(old, new)?.feedback
            }
    }
}
