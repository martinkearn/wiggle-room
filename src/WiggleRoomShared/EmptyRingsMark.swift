//
//  EmptyRingsMark.swift
//  WiggleRoom
//

import SwiftUI

/// One of the app icon's two hand-wobbled rings, as a shape. The outline is
/// the icon's own geometry (drawn in a 200-unit design space, ring bounds
/// roughly 26–172), rescaled to fill `rect`, and starts at the top running
/// clockwise so `trim(from:to:)` closes it like a progress ring.
struct IconRingShape: Shape {
    enum Ring { case outer, inner }
    var ring: Ring

    func path(in rect: CGRect) -> Path {
        let s: [CGFloat] = ring == .outer
            ? [100, 32, 144, 26, 172, 60, 168, 102, 166, 148, 130, 176, 96, 170, 54, 168, 26, 138, 32, 96, 34, 56, 60, 30, 100, 32]
            : [100, 56, 128, 52, 148, 76, 144, 102, 142, 130, 120, 150, 96, 146, 70, 144, 54, 126, 56, 98, 58, 72, 76, 54, 100, 56]
        // Both rings share the outer ring's bounds so the pair stays in
        // the same relationship as in the icon.
        let (minX, minY, span): (CGFloat, CGFloat, CGFloat) = (26, 26, 146)
        func pt(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + (s[i] - minX) / span * rect.width,
                    y: rect.minY + (s[i + 1] - minY) / span * rect.height)
        }
        var p = Path()
        p.move(to: pt(0))
        for i in stride(from: 2, to: s.count, by: 6) {
            p.addCurve(to: pt(i + 4), control1: pt(i), control2: pt(i + 2))
        }
        return p
    }
}

/// The "nothing here yet" ring graphic — the app icon's two wobbly,
/// partly closed rings (outer pace ring ~75%, inner actual ring ~68%),
/// drawn faint. Shared so the tracker list's empty state, the other empty
/// states and the widgets' "Loading data…" state all show the same picture
/// as the icon. `size` is the outer diameter; stroke widths scale with it.
struct EmptyRingsMark: View {
    var size: CGFloat = 132

    var body: some View {
        let line = size * 0.09
        ZStack {
            IconRingShape(ring: .outer)
                .trim(from: 0, to: 0.75)
                .stroke(WiggleRoomColors.brand.opacity(0.35), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
            IconRingShape(ring: .inner)
                .trim(from: 0, to: 0.68)
                .stroke(WiggleRoomColors.good.opacity(0.55), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
        .padding(line / 2)
        .frame(width: size, height: size)
    }
}

#Preview {
    EmptyRingsMark()
}
