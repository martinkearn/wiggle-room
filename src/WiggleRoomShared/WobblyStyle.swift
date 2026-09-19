//
//  WobblyStyle.swift
//  WiggleRoomShared
//

import SwiftUI

/// A slightly irregular circle — the tracker badge's shape. A radial
/// function with two low-frequency wobbles, so it reads as hand-cut rather
/// than perfectly round. `seed` gives each tracker its own gentle variation.
struct BlobShape: Shape {
    var seed: Double = 0

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        let steps = 72
        var path = Path()
        for i in 0..<steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let k = 1 + 0.045 * sin(2 * a + seed) + 0.03 * sin(3 * a + seed * 2.1)
            let p = CGPoint(x: cx + CGFloat(cos(a) * k) * r * 0.97, y: cy + CGFloat(sin(a) * k) * r * 0.97)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Cards with slightly uneven corners — friendlier than a perfect rounded
/// rectangle, still quiet enough to sit behind numbers. Two variants so
/// neighbouring cards don't mirror each other exactly.
enum WobblyCard {
    static func shape(_ variant: Int = 0, scale: CGFloat = 1) -> UnevenRoundedRectangle {
        let radii: RectangleCornerRadii = variant % 2 == 0
            ? RectangleCornerRadii(topLeading: 22 * scale, bottomLeading: 26 * scale, bottomTrailing: 20 * scale, topTrailing: 28 * scale)
            : RectangleCornerRadii(topLeading: 26 * scale, bottomLeading: 20 * scale, bottomTrailing: 26 * scale, topTrailing: 22 * scale)
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
    }
}

/// A wobbly colour blob carrying an SF Symbol, with a soft offset shadow
/// shape beneath — the shared drawing behind `TrackerBadge` and the
/// colour/glyph picker's live preview.
struct WobblyBadge: View {
    let color: Color
    let symbol: String
    var seed: Double = 0
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            BlobShape(seed: seed)
                .fill(color.opacity(0.35))
                .offset(y: size * 0.07)
            BlobShape(seed: seed)
                .fill(color)
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The tracker's identity badge, used everywhere a tracker appears — list
/// rows, detail, widgets, watch, Mac sidebar.
struct TrackerBadge: View {
    let tracker: Tracker
    var size: CGFloat = 40

    var body: some View {
        WobblyBadge(
            color: tracker.accentColor,
            symbol: tracker.glyphSymbol,
            seed: Double(tracker.resolvedColorIndex) * 1.3,
            size: size
        )
    }
}

extension View {
    /// The soft wash a tracker's own colour gives a card or row — about a
    /// tenth of its accent over whatever surface is beneath, in a wobbly
    /// card outline.
    func trackerCard(_ tracker: Tracker, variant: Int = 0, strength: Double = 0.11) -> some View {
        background(tracker.accentColor.opacity(strength), in: WobblyCard.shape(variant))
    }
}

/// A widget's container background: the normal widget ground with a wash of
/// the tracker's own colour over it.
struct TrackerWidgetBackground: View {
    let tracker: Tracker

    var body: some View {
        ZStack {
            Color.widgetBackground
            tracker.accentColor.opacity(0.14)
        }
    }
}
