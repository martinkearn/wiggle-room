//
//  ZoomIndicator.swift
//  WiggleRoom
//

import SwiftUI

/// A small magnifier shown beside a tracker's name on surfaces too small for
/// the zoom window's date range (list rows, the menu bar, medium and larger
/// widgets), so a zoomed ring is never mistaken for a whole-period one.
/// Renders nothing while the tracker isn't zoomed or isn't eligible.
struct ZoomIndicator: View {
    let tracker: Tracker
    let now: Date
    var size: CGFloat = 11

    var body: some View {
        if let window = tracker.zoomWindow(asOf: now) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Zoomed to \(Tracker.zoomRangeText(window))")
        }
    }
}
