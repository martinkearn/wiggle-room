//
//  ZoomIndicator.swift
//  WiggleRoom
//

import SwiftUI

/// A small magnifier shown beside a tracker's name on the medium and larger
/// chart widgets, which have no room for the zoom window's date range, so a
/// zoomed chart is never mistaken for a whole-period one. Renders nothing
/// while the chart isn't zoomed or its level doesn't apply.
struct ZoomIndicator: View {
    let tracker: Tracker
    let now: Date
    var size: CGFloat = 11

    var body: some View {
        if let window = tracker.chartZoomWindow(asOf: now) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Zoomed to \(Tracker.zoomRangeText(window))")
        }
    }
}
