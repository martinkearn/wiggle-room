//
//  WobblyGauge.swift
//  WiggleRoom
//

import SwiftUI

/// A single hand-wobbled progress ring with content in the middle — the
/// Lock Screen / watch-face circular replacement for the system
/// `Gauge(.accessoryCircular)`, whose arc can't be restyled. Uses the same
/// outline as the app icon and `RingsView` so even the smallest surfaces
/// share the drawn-by-hand look. `fraction` is exact (arc-length trim).
struct WobblyGauge<Content: View>: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 5
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = IconRingShape(ring: .outer, fitsRect: true)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        ZStack {
            shape.stroke(color.opacity(0.25), style: style)
            shape.trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: style)
            content()
                .padding(lineWidth * 1.4)
        }
        .padding(lineWidth / 2)
    }
}
