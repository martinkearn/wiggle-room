//
//  ChartZoomControls.swift
//  WiggleRoom
//

import SwiftUI

/// The trend chart's zoom caption and its − and + buttons, drawn directly
/// above the chart they zoom. The buttons step through the levels that
/// currently apply (`availableChartZooms`) — whole period, then month, then
/// week — and the choice is saved on the tracker with `save`, so it syncs
/// to every device and reaches the chart widget. Renders nothing when the
/// chart can't zoom at all.
struct ChartZoomControls: View {
    let tracker: Tracker
    let now: Date
    let save: () -> Void

    var body: some View {
        let levels = tracker.availableChartZooms(asOf: now)
        if levels.count > 1 {
            let current = tracker.effectiveChartZoom(asOf: now)
            let index = levels.firstIndex(of: current) ?? 0
            HStack(spacing: 12) {
                Text(caption(for: current))
                    .font(.wiggleText(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button {
                    zoom(to: levels[index - 1])
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(index == 0)
                Button {
                    zoom(to: levels[index + 1])
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(index == levels.count - 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    /// "Whole period", or the days a zoomed chart covers.
    private func caption(for zoom: ChartZoom) -> String {
        guard let window = ChartZoom.window(for: zoom, around: now) else { return zoom.title }
        return Tracker.zoomRangeText(window)
    }

    private func zoom(to level: ChartZoom) {
        tracker.chartZoom = level
        save()
    }
}
