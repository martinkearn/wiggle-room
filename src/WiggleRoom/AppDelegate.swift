//
//  AppDelegate.swift
//  WiggleRoom
//

#if os(macOS)
import AppKit

/// Keeps the app (and its `MenuBarExtra`, §7.2) running after the main
/// window is closed, rather than quitting the moment it is — the whole
/// point of a menu bar item is that a tracker's ahead/behind figure stays
/// glanceable even with no window open at all. SwiftUI's default macOS
/// behavior otherwise terminates the app once its last window closes, which
/// would take the menu bar item down with it; "Open Wiggle Room" in the
/// dropdown (`MenuBarStatusView`) is how the main window comes back.
///
/// Also registers for CloudKit's silent push so an already-running,
/// foregrounded app picks up another device's changes within seconds
/// instead of waiting for its own next periodic/opportunistic import — see
/// this method's doc comment below for the incident that surfaced the gap.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// SwiftData's `cloudKitDatabase: .automatic` mirroring (§6) manages its
    /// own CloudKit subscription and picks a delivered push up on its own —
    /// this method only needs to exist so the system actually delivers the
    /// push to the process at all. Without `registerForRemoteNotifications()`
    /// above and this delegate method present, a Mac app left open sees
    /// another device's change only on its own next periodic/opportunistic
    /// import, which can take several minutes — reported 2026-09-22 as a
    /// reset performed on iOS not appearing on an already-running Mac app
    /// even minutes later (confirmed via the CloudKit Dashboard that iOS had
    /// already pushed the change; the Mac just hadn't been told to look).
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {}
}
#endif

#if os(iOS)
import UIKit

/// iOS-side counterpart to the macOS `AppDelegate` above — same purpose,
/// same fix: register for CloudKit's silent push so a foregrounded app
/// picks up another device's changes promptly instead of waiting for its
/// own next periodic/opportunistic import.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    /// See the macOS `AppDelegate.application(_:didReceiveRemoteNotification:)`
    /// doc comment — same mechanism, same fix, both platforms.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }
}
#endif
