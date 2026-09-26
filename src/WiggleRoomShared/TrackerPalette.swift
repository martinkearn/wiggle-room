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
enum TrackerPalette {
    struct Entry: Identifiable {
        let id: Int
        let name: String
        let color: Color
    }

    static let all: [Entry] = [
        entry(0, "Blueberry", light: 0x5B57D6, dark: 0x8B88F5),
        entry(1, "Bubblegum", light: 0xD9508F, dark: 0xF27DB2),
        entry(2, "Sky", light: 0x2F8FD6, dark: 0x5FB4F2),
        entry(3, "Lagoon", light: 0x1F9AA8, dark: 0x4FC3D0),
        entry(4, "Lilac", light: 0x9B6BD3, dark: 0xBC93EE),
        entry(5, "Peach", light: 0xE9805A, dark: 0xF5A283),
        entry(6, "Plum", light: 0x86407E, dark: 0xB96FB0),
        entry(7, "Toffee", light: 0xA9754A, dark: 0xD19F72),
        entry(8, "Forest", light: 0x2F6B45, dark: 0x5FA57A),
        entry(9, "Slate", light: 0x6B7280, dark: 0x9CA3AF),
        entry(10, "Sunshine", light: 0xE0B000, dark: 0xF5CD3D),
        entry(11, "Cherry", light: 0xC4302B, dark: 0xF06A63),
    ]

    private static func entry(_ id: Int, _ name: String, light: UInt32, dark: UInt32) -> Entry {
        Entry(id: id, name: name, color: Color.dynamic(light: rgb(light), dark: rgb(dark)))
    }

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func color(at index: Int) -> Color {
        all[((index % all.count) + all.count) % all.count].color
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

    /// This tracker's identity colour (badge, row wash, header glow, budget
    /// card, chart Budget line, ring track, widget background).
    var accentColor: Color { TrackerPalette.color(at: resolvedColorIndex) }

    var accentName: String { TrackerPalette.name(at: resolvedColorIndex) }

    /// The SF Symbol on this tracker's badge — the chosen one, or the
    /// default for this tracker's type.
    var glyphSymbol: String {
        if !glyph.isEmpty { return glyph }
        return trackerType.defaultGlyph
    }
}
