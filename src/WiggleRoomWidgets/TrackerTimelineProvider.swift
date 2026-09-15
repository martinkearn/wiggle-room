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
    /// legible at a glance — refreshing hourly is a reasonable ceiling that
    /// keeps the widget looking live without WidgetKit's shared per-app
    /// refresh budget being burned on a slowly-changing number.
    @MainActor
    func timeline(for configuration: SelectTrackerIntent, in context: Context) async -> Timeline<TrackerTimelineEntry> {
        let now = Date.now
        let entry = TrackerTimelineEntry(date: now, tracker: await resolvedTracker(for: configuration))
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
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
