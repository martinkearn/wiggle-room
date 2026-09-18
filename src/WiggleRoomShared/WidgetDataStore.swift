//
//  WidgetDataStore.swift
//  WiggleRoomShared
//

import CoreData
import Foundation
import SwiftData
import os

/// A glanceable extension's own read access to the same CloudKit-synced,
/// App Group-shared SwiftData store the main app uses (§6 of the build
/// spec). Shared by every WidgetKit-based extension in this app — the
/// iOS/macOS Home/Lock Screen widgets (`WiggleRoomWidgets`) and the watchOS
/// complication (`WiggleRoomComplication`, §7.3) — since each runs in its
/// own process and needs the identical CloudKit cold-start/import-wait
/// handling below; living here instead of duplicated per-extension means a
/// fix to that handling (like the CloudKit-import-notification wait) only
/// has to happen once. Each process opens its own `ModelContainer`, but all
/// of them point at the same on-disk file — the shared App Group container
/// (`AppGroup.identifier`), not each target's own private sandbox — so a
/// same-device change (the phone app writing, this extension reading) is
/// visible instantly, with no CloudKit round-trip needed for that. CloudKit
/// sync is still what keeps *different devices* (the phone and the Mac, or
/// the phone and the Watch) consistent with each other — the cold-start/
/// import-wait handling below exists for that cross-device case, and for
/// this extension's own very first launch before it's ever shared the App
/// Group container with a process that already warmed it.
enum WidgetDataStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "martinkearn.WiggleRoom",
        category: "WidgetDataStore"
    )

    /// Created once and reused for the lifetime of the extension process —
    /// standing up a CloudKit-backed `ModelContainer` from scratch isn't
    /// free, and App Intents entity queries (the "choose a tracker" widget
    /// configuration UI in particular) have a short time budget before the
    /// picker just gives up and shows nothing, with no visible error.
    @MainActor
    private static var cachedContainer: ModelContainer?

    /// Once at least one tracker has appeared, two no-growth import polls is
    /// "settled enough": one could be a quiet import notification, while two
    /// avoids spending the full picker deadline on an already-warm App Group
    /// store. This is intentionally count-based: this longer wait is for the
    /// interactive configuration picker discovering rows, while timeline
    /// freshness for value changes is handled by `fetchAllTrackers()`'s shorter
    /// update wait and explicit widget reload triggers.
    private static let stablePollsBeforeSettled = 2

    @MainActor
    static func makeContainer() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        // Must stay identical to every other process's schema for this same
        // store (`WiggleRoomApp`, `IntentDataStore`, `WiggleRoomWatchApp`) —
        // a mismatched schema between processes sharing one on-disk/CloudKit
        // store is a real corruption risk, not just a compile-time detail.
        let schema = Schema([Tracker.self, ConnectedSource.self, ValueSnapshot.self, StarlingRequestLogEntry.self])
        // Shared App Group container (see `AppGroup`) — the same on-disk
        // store the host app (WiggleRoom/WiggleRoomWatch) opens, so this
        // extension sees a same-device change the instant it's asked for,
        // with no CloudKit round-trip needed for same-device freshness.
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .automatic
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            cachedContainer = container
            return container
        } catch {
            logger.error("Failed to create CloudKit ModelContainer: \(error, privacy: .public)")
            throw error
        }
    }

    /// A plain, immediate fetch with no retry — for `placeholder(in:)`,
    /// which WidgetKit expects to return instantly and doesn't award any
    /// extra time budget to. Fine for it to come back empty on a cold
    /// extension process; the placeholder is a generic skeleton, not the
    /// figure a user is actually trying to read.
    @MainActor
    static func fetchAllTrackersImmediately() throws -> [Tracker] {
        let container = try makeContainer()
        let descriptor = FetchDescriptor<Tracker>(sortBy: [SortDescriptor(\.name)])
        return try container.mainContext.fetch(descriptor)
    }

    /// The very first time this extension's sandboxed container talks to
    /// CloudKit (a fresh install, a fresh Simulator container), SwiftData's
    /// initial history import runs asynchronously in the background — the
    /// `ModelContainer` can finish initializing and a fetch can legitimately
    /// see zero rows before that import lands, even though the real data
    /// already exists in iCloud. Reported as the widget's "choose a
    /// tracker" picker flashing "Loading" and coming back empty. Polling
    /// briefly here (instead of accepting the first empty result) is a
    /// one-time cold-start cost per extension process — once
    /// `cachedContainer` above is warm, later calls return immediately.
    ///
    /// When trackers *are* already present, this still gives CloudKit one
    /// short, bounded chance to deliver a fresher import before returning.
    /// `TrackerStore` calls `WidgetCenter.reloadAllTimelines()` the instant
    /// a reading is logged in the main app, which makes WidgetKit re-invoke
    /// this immediately — almost always well before that change has
    /// actually round-tripped through CloudKit into this extension's own
    /// separate local store. Without this, a value *update* to a tracker
    /// the widget already knows about was invisible until the store's own
    /// periodic refresh or the next unrelated reload, since only the
    /// true-empty case above ever waited at all.
    ///
    /// **Deliberately a single ~2s wait, not several** — a real regression
    /// was found in practice from widening this to three (~6s total): the
    /// system only gives a widget's live render a few seconds (~3, per
    /// device logs) to actually produce content before it gives up and
    /// leaves the widget on its last/placeholder state. A widget with no
    /// prior cached render for its exact configuration (e.g. right after
    /// picking a tracker for the first time) hit that slow path on every
    /// single attempt and never finished in time — a persistently blank
    /// widget, not just occasional staleness. This is much shorter than
    /// `fetchAllTrackersForConfiguration()`'s wait for exactly that reason —
    /// this runs inside WidgetKit's own timeline-generation budget, not
    /// behind an interactive "Loading" sheet, so it can't afford to be
    /// generous at all.
    @MainActor
    static func fetchAllTrackers() async throws -> [Tracker] {
        do {
            var trackers = try fetchAllTrackersImmediately()
            if trackers.isEmpty {
                for attempt in 1...8 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    // A transient fetch error on any one poll used to throw
                    // out of this whole function (discarding the wait already
                    // done and reporting no trackers at all), rather than just
                    // trying again on the next iteration. Log and continue so
                    // persistent failures are still visible.
                    do {
                        let latest = try fetchAllTrackersImmediately()
                        trackers = latest
                    } catch {
                        logger.error("Failed to refetch trackers while waiting for CloudKit import: \(error, privacy: .public)")
                    }
                    if !trackers.isEmpty {
                        logger.notice("Trackers appeared after waiting for initial CloudKit import (attempt \(attempt)).")
                        break
                    }
                }
            } else {
                await waitForNextCloudKitImport(timeout: 2)
                // A transient error here must fall back to the already-known-
                // good `trackers` rather than throwing, but still gets logged.
                do {
                    let latest = try fetchAllTrackersImmediately()
                    trackers = latest
                } catch {
                    logger.error("Failed to refetch trackers after CloudKit import wait: \(error, privacy: .public)")
                }
            }
            return trackers
        } catch {
            logger.error("Failed to fetch trackers: \(error, privacy: .public)")
            throw error
        }
    }

    @MainActor
    static func fetchTracker(id: UUID) async throws -> Tracker? {
        try await fetchAllTrackers().first { $0.id == id }
    }

    /// Used only by the interactive "choose a tracker" widget configuration
    /// picker (`TrackerEntityQuery.suggestedEntities()`), which already
    /// shows its own "Loading" state, so a longer wait here is expected
    /// rather than surprising. Unlike `fetchAllTrackers()` above, this keeps
    /// re-fetching even when the *first* result already has trackers in it —
    /// a tracker created moments ago in the main app still has to make a
    /// round trip through CloudKit and back down into this extension's own
    /// separate local store, which doesn't finish just because this
    /// container already had other trackers cached from before.
    ///
    /// A short fixed poll (originally ~3-6s) turned out to be nowhere near
    /// enough: a brand new tracker's very first CloudKit sync — especially
    /// right after this app switched CloudKit containers — can legitimately
    /// take considerably longer than that, and the picker was timing out
    /// and showing "no tracker" well before the sync had actually finished
    /// (confirmed by it succeeding on retry once enough wall-clock time had
    /// passed, with no code change). Rather than guess a longer fixed delay,
    /// this waits on CloudKit's own "import finished" signal
    /// (`NSPersistentCloudKitContainer.eventChangedNotification`, which
    /// SwiftData's CloudKit-backed store posts under the hood) so it moves
    /// on the moment a sync actually completes, re-fetching after each one —
    /// with a generous overall deadline as a backstop in case that
    /// notification never arrives (e.g. no network). Returns whichever
    /// fetch found the most trackers, on the assumption the local store
    /// only gains rows during this window, never loses ones it already had.
    @MainActor
    static func fetchAllTrackersForConfiguration() async throws -> [Tracker] {
        do {
            var best = try fetchAllTrackersImmediately()
            // Previously a shorter 10s window once *any* tracker was already
            // visible, on the assumption a newly-added one only needs a
            // brief grace period to catch up. In practice a brand new
            // tracker's very first CloudKit sync (a genuinely new record,
            // not an update to one already replicated here) can take just
            // as long as the cold-start case below — reported as a
            // just-created tracker simply never appearing in the widget's
            // "choose a tracker" picker. Both cases now get the same
            // generous window; a picker that occasionally waits a few
            // seconds longer when there's nothing new to find is a much
            // smaller cost than a tracker that can't be picked at all.
            // Stops as soon as results look settled, rather than always
            // burning the full 25s deadline regardless of how quickly data
            // actually showed up — with the shared App Group container
            // (see `AppGroup`), a same-device fetch is now usually
            // instant, and this loop used to have no early-exit at all,
            // so the picker waited the full 25 seconds on essentially
            // every open even when nothing was ever going to change.
            // Two consecutive no-growth polls (each up to 3s) once `best`
            // is non-empty is judged "settled enough" — still leaves the
            // full deadline available for the genuine cold-start case
            // where nothing has appeared yet at all.
            let deadline = Date().addingTimeInterval(25)
            var consecutiveStablePolls = 0
            while Date() < deadline {
                let timeRemaining = deadline.timeIntervalSinceNow
                guard timeRemaining > 0 else { break }
                await waitForNextCloudKitImport(timeout: min(timeRemaining, 3))
                // A `try?` here rather than letting a mid-poll fetch error
                // propagate — a single transient failure partway through
                // this window used to abort the whole call and throw away
                // whatever `best` already held (even the exact tracker the
                // picker needed), surfacing as the picker giving up and
                // reverting to no selection despite CloudKit having already
                // delivered the data moments before. Only the very first
                // fetch above still throws — a container that can't be
                // opened at all is worth surfacing; one bad poll in the
                // middle of an otherwise-working wait isn't.
                guard let latest = try? fetchAllTrackersImmediately() else { continue }
                if latest.count > best.count {
                    best = latest
                    consecutiveStablePolls = 0
                } else if latest.count == best.count, !best.isEmpty {
                    consecutiveStablePolls += 1
                    if consecutiveStablePolls >= stablePollsBeforeSettled { break }
                } else {
                    // Fewer rows than `best` is treated as a transient/
                    // regressing fetch, not evidence that the store settled.
                    consecutiveStablePolls = 0
                }
            }
            return best
        } catch {
            logger.error("Failed to fetch trackers for configuration: \(error, privacy: .public)")
            throw error
        }
    }

    /// Suspends until CloudKit reports an import has finished (successful or
    /// not — either way it's a good moment to re-check the local store), or
    /// `timeout` elapses, whichever comes first. Never throws; a missed or
    /// absent notification just falls through to the caller's next poll.
    private static func waitForNextCloudKitImport(timeout: TimeInterval) async {
        let importFinished = NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await note in importFinished {
                    guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                        event.type == .import, event.endDate != nil else { continue }
                    return
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
    }
}
