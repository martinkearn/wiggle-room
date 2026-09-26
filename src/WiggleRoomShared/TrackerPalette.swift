//
//  TrackerPalette.swift
//  WiggleRoomShared
//

import SwiftUI

/// The twelve per-tracker identity colours (design direction, 2026-09-19;
/// Forest, Slate, Sunshine and Cherry added 2026-09-20). The first eight
/// deliberately avoid every status hue; the last four are user-requested
/// green/grey/yellow/red choices, kept deeper or softer than the
/// `WiggleRoomColors` traffic-light colours the rings' arc and ahead/behind
/// figure use. Append only — `Tracker.colorIndex` indexes this array. Each
/// has a light and a dark value so it glows on dark surfaces.
///
/// **Reference colours.** Being merely "deeper or softer" than a status
/// colour turned out not to be enough. A few surfaces draw a tracker's own
/// colour immediately against a traffic-light one — the chart's pace line
/// beside the green/red actual line, the rings' unfilled track beneath the
/// green/amber/red arc, the pace figure card beside the status figure card —
/// and on those a green tracker's pace line is indistinguishable from "ahead
/// of pace" and a red one's from "behind". Those surfaces therefore use
/// `reference` rather than `color`: the identity colour itself wherever it is
/// already clear of the status hues, and a deliberate stand-in where it is
/// not. See `Tracker.referenceColor` for the list of surfaces.
///
/// The five stand-ins below were chosen by measuring every palette entry's
/// hue against `WiggleRoomColors.good`, `.warning` and `.bad` in both
/// appearances (the only three that can be drawn on a ring or a chart —
/// `.error` is text-only). Each stand-in keeps its identity colour's
/// lightness and weight so the tracker still reads as itself, and clears
/// every status hue by at least 42° in both appearances:
///
/// | Identity | Hue | Reference | Why |
/// |---|---|---|---|
/// | Peach | orange-red, 5° from red | Rose | pink, away from red |
/// | Toffee | brown, 10° from amber | Taupe | mauve-grey, desaturated |
/// | Forest | green, 13° from green | Petrol | deep teal-blue |
/// | Sunshine | gold, 9° from amber | Citron | yellow-green |
/// | Cherry | red, 8° from red | Raspberry | magenta |
///
/// The other seven are left as they are. Bubblegum (38° from red) and Lagoon
/// (26° from green) are the closest of them, and both were judged clear
/// enough by eye: pink against red and cyan against emerald are easy to tell
/// apart, unlike the five above, which differ from a status colour only in
/// shade. Slate is near-neutral and has no meaningful hue to clash.
enum TrackerPalette {
    struct Entry: Identifiable {
        let id: Int
        let name: String
        let color: Color
        /// The colour to use where this entry would otherwise sit directly
        /// against a status colour — the identity colour itself unless it
        /// needs a stand-in.
        let reference: Color
    }

    static let all: [Entry] = [
        entry(0, "Blueberry", light: 0x5B57D6, dark: 0x8B88F5),
        entry(1, "Bubblegum", light: 0xD9508F, dark: 0xF27DB2),
        entry(2, "Sky", light: 0x2F8FD6, dark: 0x5FB4F2),
        entry(3, "Lagoon", light: 0x1F9AA8, dark: 0x4FC3D0),
        entry(4, "Lilac", light: 0x9B6BD3, dark: 0xBC93EE),
        // Peach → Rose
        entry(5, "Peach", light: 0xE9805A, dark: 0xF5A283, referenceLight: 0xD45E9D, referenceDark: 0xEC8DC0),
        entry(6, "Plum", light: 0x86407E, dark: 0xB96FB0),
        // Toffee → Taupe
        entry(7, "Toffee", light: 0xA9754A, dark: 0xD19F72, referenceLight: 0x845C83, referenceDark: 0xB78FB6),
        // Forest → Petrol
        entry(8, "Forest", light: 0x2F6B45, dark: 0x5FA57A, referenceLight: 0x2A5E7E, referenceDark: 0x5C9BC1),
        entry(9, "Slate", light: 0x6B7280, dark: 0x9CA3AF),
        // Sunshine → Citron
        entry(10, "Sunshine", light: 0xE0B000, dark: 0xF5CD3D, referenceLight: 0x6E9C11, referenceDark: 0xAFDC56),
        // Cherry → Raspberry
        entry(11, "Cherry", light: 0xC4302B, dark: 0xF06A63, referenceLight: 0xB93191, referenceDark: 0xE76AC1),
    ]

    /// `referenceLight`/`referenceDark` default to the identity colour, so an
    /// entry only names them if it needs a stand-in.
    private static func entry(
        _ id: Int,
        _ name: String,
        light: UInt32,
        dark: UInt32,
        referenceLight: UInt32? = nil,
        referenceDark: UInt32? = nil
    ) -> Entry {
        Entry(
            id: id,
            name: name,
            color: Color.dynamic(light: rgb(light), dark: rgb(dark)),
            reference: Color.dynamic(
                light: rgb(referenceLight ?? light),
                dark: rgb(referenceDark ?? dark)
            )
        )
    }

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func color(at index: Int) -> Color {
        all[((index % all.count) + all.count) % all.count].color
    }

    static func referenceColor(at index: Int) -> Color {
        all[((index % all.count) + all.count) % all.count].reference
    }

    static func name(at index: Int) -> String {
        all[((index % all.count) + all.count) % all.count].name
    }

    /// Glyphs a tracker can wear on its badge (SF Symbols).
    static let glyphs: [String] = [
        // Money
        "sterlingsign.circle.fill", "dollarsign.circle.fill", "eurosign.circle.fill", "banknote.fill", "creditcard.fill",
        // Getting around
        "car.fill", "bicycle", "bus.fill", "fuelpump.fill", "airplane",
        // Health
        "scalemass.fill", "figure.walk",
        // Leisure
        "figure.run", "dumbbell.fill", "gamecontroller.fill", "popcorn.fill", "beach.umbrella.fill", "cup.and.saucer.fill", "fork.knife",
        // Everyday
        "cart.fill", "drop.fill", "bag.fill", "house.fill", "star.fill", "heart.fill", "bolt.fill",
        // Plain numbers — the defaults for the two unitless types, so a
        // tracker's own default is always somewhere in this grid.
        "chart.line.uptrend.xyaxis", "chart.line.downtrend.xyaxis", "number.circle.fill",
    ]
}

extension Tracker {
    /// The palette index actually in use: the chosen one, or — for a
    /// tracker created before colours existed — a stable one derived from
    /// its id, so it keeps the same colour on every device.
    var resolvedColorIndex: Int {
        if colorIndex >= 0 { return colorIndex % TrackerPalette.all.count }
        var hash = 5381
        for byte in id.uuidString.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return abs(hash) % TrackerPalette.all.count
    }

    /// This tracker's identity colour (badge, row wash, header glow, card
    /// washes, widget background).
    var accentColor: Color { TrackerPalette.color(at: resolvedColorIndex) }

    /// The tracker's colour as drawn where a status colour is immediately
    /// beside it — the chart's pace line and its legend swatch, the rings'
    /// unfilled track, and the pace figure card that sits next to the
    /// status-tinted current figure card. Usually the identity colour; a
    /// status-safe stand-in for the five entries whose own hue is a status
    /// hue (see `TrackerPalette`). Everywhere else keeps `accentColor`, so a
    /// tracker still looks like its chosen colour.
    var referenceColor: Color { TrackerPalette.referenceColor(at: resolvedColorIndex) }

    var accentName: String { TrackerPalette.name(at: resolvedColorIndex) }

    /// The SF Symbol on this tracker's badge — the chosen one, or the
    /// default for this tracker's type.
    var glyphSymbol: String {
        if !glyph.isEmpty { return glyph }
        return trackerType.defaultGlyph
    }
}
