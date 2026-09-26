//
//  TrackerTimelineProvider.swift
//  WiggleRoomWidgets
//

import WidgetKit

struct TrackerTimelineEntry: TimelineEntry {
    let date: Date
    let tracker: Tracker?
    /// True while there's no data to show *yet* (placeholder / first fetch
    /// after a resize), as opposed to genuinely having no tracker.
    var isLoading = false
}

struct TrackerTimelineProvider: AppIntentTimelineProvider {
    @MainActor
    func placeholder(in context: Context) -> TrackerTimelineEntry {
        TrackerTimelineEntry(date: .now, tracker: nil, isLoading: true)
    }

    /// `snapshot` is what WidgetKit shows immediately while the user is
    /// actively resizing/reconfiguring a widget (family change, or picking
    /// a different tracker) — Apple's own guidance is that it should return
    /// essentially instantly, unlike `timeline` below. It deliberately does
    /// **not** go through `resolvedTracker(for:)`/`WidgetDataStore
    /// .fetchAllTrackers()`, which bakes in an unconditional ~2s CloudKit-
    /// import wait meant for periodic background reloads catching a fresh
    /// value — appropriate for `timeline`, but exactly the kind of avoidable
    /// delay that made reconfiguring visibly blank for longer than it
    /// needed to. A plain immediate local fetch here is a real, local
    /// SwiftData read (already synced data on disk), not a network call, so
    /// it's fast regardless.
    @MainActor
    func snapshot(for configuration: SelectTrackerIntent, in context: Context) async -> TrackerTimelineEntry {
        let trackers = (try? WidgetDataStore.fetchAllTrackersImmediately()) ?? []
        let tracker = TrackerEntity.selectedId(configuration.tracker).flatMap { id in trackers.first { $0.id == id } } ?? trackers.first
        return TrackerTimelineEntry(date: .now, tracker: tracker, isLoading: tracker == nil)
    }

    /// A tracker's pace figures drift continuously, but they only need to be
    /// legible at a glance — `TrackerUpdateScheduling.nextWidgetReloadDate`
    /// keeps a budget-friendly ~5 minute cadence for most of a tracker's
    /// life, tightening to every minute in the final hour so the widget's
    /// last reload lines up with the tracker's own end instead of a flat
    /// "always an hour away" ceiling. This is the periodic backstop for
    /// drift from time passing alone; `WidgetCenter.reloadAllTimelines()`
    /// (triggered on every actual data change — see `TrackerStore` and
    /// `CloudSyncWidgetRefresher`) is what makes a *new* reading show up
    /// promptly rather than waiting out this interval.
    @MainActor
    func timeline(for configuration: SelectTrackerIntent, in context: Context) async -> Timeline<TrackerTimelineEntry> {
        let now = Date.now
        let tracker = await resolvedTracker(for: configuration)
        let entry = TrackerTimelineEntry(date: now, tracker: tracker)
        // A zoomed tracker's window moves at local midnight, so reload then
        // at the latest rather than showing yesterday's window any longer.
        let nextUpdate = tracker.map {
            let next = TrackerUpdateScheduling.nextWidgetReloadDate(after: now, until: $0.endDate)
            return min(next, $0.nextZoomWindowChange(after: now) ?? next)
        } ?? now.addingTimeInterval(TrackerUpdateScheduling.defaultWidgetFarInterval)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    @MainActor
    private func resolvedTracker(for configuration: SelectTrackerIntent) async -> Tracker? {
        guard let id = TrackerEntity.selectedId(configuration.tracker) else {
            return try? await WidgetDataStore.fetchAllTrackers().first
        }
        return try? await WidgetDataStore.fetchTracker(id: id)
    }
}
