//
//  TrackerTimelineProvider.swift
//  WiggleRoomWidgets
//

import WidgetKit

struct TrackerTimelineEntry: TimelineEntry {
    let date: Date
    let tracker: Tracker?
}

struct TrackerTimelineProvider: AppIntentTimelineProvider {
    @MainActor
    func placeholder(in context: Context) -> TrackerTimelineEntry {
        TrackerTimelineEntry(date: .now, tracker: try? WidgetDataStore.fetchAllTrackersImmediately().first)
    }

    @MainActor
    func snapshot(for configuration: SelectTrackerIntent, in context: Context) async -> TrackerTimelineEntry {
        TrackerTimelineEntry(date: .now, tracker: await resolvedTracker(for: configuration))
    }

    /// A tracker's pace figures drift continuously, but they only need to be
    /// legible at a glance — `TrackerUpdateScheduling.nextWidgetReloadDate`
    /// keeps a budget-friendly ~15 minute cadence for most of a tracker's
    /// life, tightening to every minute in the final hour so the widget's
    /// last reload lines up with the tracker's own end instead of a flat
    /// "always an hour away" ceiling.
    @MainActor
    func timeline(for configuration: SelectTrackerIntent, in context: Context) async -> Timeline<TrackerTimelineEntry> {
        let now = Date.now
        let tracker = await resolvedTracker(for: configuration)
        let entry = TrackerTimelineEntry(date: now, tracker: tracker)
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
}
