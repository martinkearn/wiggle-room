//
//  TrackerPalette.swift
//  WiggleRoomShared
//

import SwiftUI

/// The eight per-tracker identity colours (design direction, 2026-09-19).
/// Deliberately clear of every status hue: no pure green, amber or red, so
/// "which tracker is this" never gets confused with "how is it doing" — the
/// rings' actual arc and the ahead/behind figure always keep the
/// `WiggleRoomColors` traffic-light colours. Each has a light and a dark
/// value so it glows on dark surfaces rather than muddying.
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
        "cart.fill", "drop.fill", "cup.and.saucer.fill", "car.fill",
        "airplane", "bag.fill", "fork.knife", "creditcard.fill",
        "star.fill", "heart.fill", "house.fill", "bolt.fill",
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

    /// The SF Symbol on this tracker's badge.
    var glyphSymbol: String {
        if !glyph.isEmpty { return glyph }
        return isCurrencyUnit ? "creditcard.fill" : "gauge.with.dots.needle.33percent"
    }
}
