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
    /// `false` (the icon-faithful mapping) places both rings in the same
    /// 26–172 design box, so the inner ring sits inside the outer as it does
    /// in the icon. `true` stretches this ring's own outline to fill `rect`
    /// exactly, the way a `Circle` would — for the live rings, where the
    /// caller insets the inner ring itself.
    var fitsRect = false
    /// A more exaggerated wobble, for small, faint uses (the empty and
    /// loading marks) where the icon's own subtle outline reads as plain
    /// circles at ~50pt.
    var pronounced = false

    func path(in rect: CGRect) -> Path {
        let s: [CGFloat]
        switch (ring, pronounced) {
        case (.outer, false): s = [100, 32, 144, 26, 172, 60, 168, 102, 166, 148, 130, 176, 96, 170, 54, 168, 26, 138, 32, 96, 34, 56, 60, 30, 100, 32]
        case (.inner, false): s = [100, 56, 128, 52, 148, 76, 144, 102, 142, 130, 120, 150, 96, 146, 70, 144, 54, 126, 56, 98, 58, 72, 76, 54, 100, 56]
        case (.outer, true): s = [100, 30, 150, 20, 176, 58, 170, 104, 168, 154, 128, 182, 92, 172, 46, 170, 22, 140, 30, 92, 34, 48, 58, 34, 100, 30]
        case (.inner, true): s = [100, 54, 132, 46, 152, 74, 146, 104, 144, 134, 118, 154, 92, 148, 64, 146, 50, 126, 54, 94, 58, 66, 74, 56, 100, 54]
        }
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
        p.closeSubpath()
        guard fitsRect else { return p }
        let b = p.boundingRect
        return p.applying(
            CGAffineTransform(translationX: -b.minX, y: -b.minY)
                .concatenating(CGAffineTransform(scaleX: rect.width / b.width, y: rect.height / b.height))
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        )
    }
}

/// The "nothing here yet" ring graphic — the app icon's two wobbly,
/// partly closed rings (outer pace ring ~75%, inner actual ring ~68%),
/// drawn faint and with a deliberately stronger wobble than the icon's. Shared so the tracker list's empty state, the other empty
/// states and the widgets' "Loading data…" state all show the same picture
/// as the icon. `size` is the outer diameter; stroke widths scale with it.
struct EmptyRingsMark: View {
    var size: CGFloat = 132

    var body: some View {
        let line = size * 0.09
        let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        ZStack {
            IconRingShape(ring: .outer, fitsRect: true, pronounced: true)
                .trim(from: 0, to: 0.75)
                .stroke(WiggleRoomColors.brand.opacity(0.5), style: style)
            IconRingShape(ring: .inner, fitsRect: true, pronounced: true)
                .trim(from: 0, to: 0.68)
                .stroke(WiggleRoomColors.good.opacity(0.7), style: style)
                .padding(size * 0.17)
        }
        .padding(line / 2)
        .frame(width: size, height: size)
    }
}

#Preview {
    EmptyRingsMark()
}
