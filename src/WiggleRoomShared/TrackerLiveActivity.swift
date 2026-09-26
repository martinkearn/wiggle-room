//
//  TrackerLiveActivity.swift
//  WiggleRoomShared
//

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// A Live Activity that only exists for a tracker's **final stretch** — the
/// last 10% of its period (`TrackerLiveActivity.finalStretchFraction`) —
/// rather than its whole life. Live Activities are built for short, bounded
/// events (§9), which a tracker running for weeks or months isn't; the last
/// tenth of one is.
///
/// `nonisolated` because the target defaults to main-actor isolation, and
/// ActivityKit reads these values from concurrent contexts of its own — an
/// isolated conformance to `ActivityAttributes` is an error under the Swift 6
/// language mode.
nonisolated struct TrackerActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var statusLine: String
        var difference: String
        var isOnPace: Bool
    }

    var trackerId: UUID
    var name: String
    var endDate: Date
    /// The tracker's palette index and badge glyph. Optional so an activity
    /// started by an older build (without them) still decodes.
    var colorIndex: Int?
    var glyph: String?
}

enum TrackerLiveActivity {
    /// The share of a tracker's period, counted from the end, during which
    /// its Live Activity is shown.
    static let finalStretchFraction = 0.1

    static func isInFinalStretch(_ tracker: Tracker, asOf now: Date = .now) -> Bool {
        let period = tracker.endDate.timeIntervalSince(tracker.startDate)
        guard period > 0, now < tracker.endDate else { return false }
        return now >= tracker.startDate.addingTimeInterval(period * (1 - finalStretchFraction))
    }

    static func state(for tracker: Tracker, asOf now: Date = .now) -> TrackerActivityAttributes.ContentState {
        let pace = tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
        return .init(
            statusLine: pace.statusLine(for: tracker),
            difference: pace.displayDifference(for: tracker),
            isOnPace: pace.status == .good
        )
    }

    /// Starts, updates or ends this tracker's activity to match whether it is
    /// currently in its final stretch. Starting one needs the app in the
    /// foreground (ActivityKit's rule), so a tracker that *enters* its final
    /// stretch while the app is closed gets its activity the next time the
    /// app is opened; updates and ends work from anywhere.
    static func sync(_ tracker: Tracker, asOf now: Date = .now) {
        let existing = Activity<TrackerActivityAttributes>.activities.first { $0.attributes.trackerId == tracker.id }
        guard isInFinalStretch(tracker, asOf: now) else {
            if let existing { Task { await existing.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let content = ActivityContent(state: state(for: tracker, asOf: now), staleDate: tracker.endDate)
        if let existing {
            Task { await existing.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = TrackerActivityAttributes(
                trackerId: tracker.id, name: tracker.name, endDate: tracker.endDate,
                colorIndex: tracker.resolvedColorIndex, glyph: tracker.glyphSymbol
            )
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }

    static func syncAll(_ trackers: [Tracker], asOf now: Date = .now) {
        for tracker in trackers { sync(tracker, asOf: now) }
    }
}
#endif
