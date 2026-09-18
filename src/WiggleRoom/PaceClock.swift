//
//  PaceClock.swift
//  WiggleRoom
//

import Foundation
import Observation
import WidgetKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The app-wide "now" that every pace figure is computed against. "Target
/// Right Now" moves every minute regardless of whether a balance changed, so
/// under/over-budget figures drift with time alone — this ticks that forward
/// **without ever touching a connected source** (no Starling request, unlike
/// `BackgroundRefreshScheduler`/pull-to-refresh, which are the only things
/// that fetch balances).
///
/// Every 30s while the app is active, every 5 minutes otherwise (only
/// meaningful on macOS, where the menu bar item keeps running with no
/// window; iOS suspends the process, and widgets/complications rely on their
/// own 5-minute timeline reload instead). Each tick also reloads widget
/// timelines so they show the same figures as the app.
@MainActor
@Observable
final class PaceClock {
    static let shared = PaceClock()

    static let foregroundInterval: TimeInterval = 30
    static let backgroundInterval: TimeInterval = 5 * 60

    private(set) var now = Date.now
    /// Increments on every tick — lets a view key an animation off "the
    /// clock advanced" without comparing dates.
    private(set) var tickCount = 0

    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var timer: Timer?

    private init() {
        #if os(iOS)
        observe(UIApplication.didBecomeActiveNotification, active: true)
        observe(UIApplication.didEnterBackgroundNotification, active: false)
        #elseif os(macOS)
        observe(NSApplication.didBecomeActiveNotification, active: true)
        observe(NSApplication.didResignActiveNotification, active: false)
        #endif
        schedule()
    }

    private func observe(_ name: Notification.Name, active: Bool) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isActive = active
                // Catch up immediately on returning to the foreground
                // rather than waiting out up to 30s of stale figures.
                if active { self.tick() }
                self.schedule()
            }
        }
    }

    private func schedule() {
        timer?.invalidate()
        let interval = isActive ? Self.foregroundInterval : Self.backgroundInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        now = .now
        tickCount += 1
        WidgetCenter.shared.reloadAllTimelines()
    }
}
