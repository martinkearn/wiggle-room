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
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
#endif
