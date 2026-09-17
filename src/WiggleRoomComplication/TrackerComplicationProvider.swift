//
//  TrackerComplicationProvider.swift
//  WiggleRoomComplication
//

import WidgetKit

struct TrackerComplicationEntry: TimelineEntry {
    let date: Date
    let tracker: Tracker?
}

struct TrackerComplicationProvider: AppIntentTimelineProvider {
    @MainActor
    func placeholder(in context: Context) -> TrackerComplicationEntry {
        TrackerComplicationEntry(date: .now, tracker: try? WidgetDataStore.fetchAllTrackersImmediately().first)
    }

    @MainActor
    func snapshot(for configuration: SelectTrackerIntent, in context: Context) async -> TrackerComplicationEntry {
        TrackerComplicationEntry(date: .now, tracker: await resolvedTracker(for: configuration))
    }

    /// Same end-aligned reload policy as the phone/Mac widgets (§8.1) — a
    /// complication only needs to look live at a glance, not tick in real
    /// time, and `CloudSyncWidgetRefresher`/`TrackerStore.reloadWidgets()`
    /// already force an earlier reload on any real data change.
    @MainActor
    func timeline(for configuration: SelectTrackerIntent, in context: Context) async -> Timeline<TrackerComplicationEntry> {
        let now = Date.now
        let tracker = await resolvedTracker(for: configuration)
        let entry = TrackerComplicationEntry(date: now, tracker: tracker)
        let nextUpdate = tracker.map {
            TrackerUpdateScheduling.nextWidgetReloadDate(after: now, until: $0.endDate)
        } ?? now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    @MainActor
    private func resolvedTracker(for configuration: SelectTrackerIntent) async -> Tracker? {
        guard let id = configuration.tracker?.id else {
            return try? await WidgetDataStore.fetchAllTrackers().first
        }
        return try? await WidgetDataStore.fetchTracker(id: id)
    }

    /// No canned per-tracker suggestions to offer up front — the "choose a
    /// tracker" picker (`SelectTrackerIntent`) already covers configuration.
    /// Unlike the iOS/macOS widget's `AppIntentTimelineProvider` conformance,
    /// this watchOS SDK's protocol has no default implementation for this
    /// requirement, so it needs stating explicitly here.
    func recommendations() -> [AppIntentRecommendation<SelectTrackerIntent>] {
        []
    }
}
