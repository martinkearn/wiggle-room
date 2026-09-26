//
//  SettingsLabel.swift
//  WiggleRoom
//

import SwiftUI

/// A settings row/sidebar label: a small wobbly colour badge with the
/// symbol in white, beside the title. Each settings area has its own
/// palette colour so the list isn't a column of identical grey icons.
struct SettingsLabel: View {
    let title: String
    let symbol: String
    var colorIndex: Int = 0
    /// Overrides the palette lookup entirely — used for menus (like Danger
    /// Zone) whose glyph colour is a fixed semantic colour rather than one
    /// of the per-tracker identity colours `colorIndex` picks from.
    var color: Color? = nil
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            WobblyBadge(
                color: color ?? TrackerPalette.color(at: colorIndex),
                symbol: symbol,
                seed: Double(colorIndex) * 1.3,
                size: size
            )
            Text(title)
        }
    }
}

/// The badge for a connected source's provider (Starling → Sky, Apple Health
/// → Bubblegum, Tesla → Peach, Manual → Toffee), so a source reads as its
/// provider at a glance.
struct ProviderBadge: View {
    let providerId: String
    var size: CGFloat = 36

    /// The provider's own name, for the places that show it as text beside
    /// the badge. A raw `providerId` capitalized reads as "Healthkit", which
    /// is neither the framework's name nor the app's.
    static func displayName(for providerId: String) -> String {
        switch providerId {
        case "starling": "Starling"
        case "healthkit": "Apple Health"
        case "tesla": "Tesla"
        case "manual": "Manual Entry"
        default: providerId.capitalized
        }
    }

    private var style: (symbol: String, color: Int) {
        switch providerId {
        case "starling": ("creditcard.fill", 2)
        case "healthkit": ("heart.fill", 1)
        case "tesla": ("bolt.car.fill", 5)
        default: ("square.and.pencil", 7)
        }
    }

    var body: some View {
        WobblyBadge(
            color: TrackerPalette.color(at: style.color),
            symbol: style.symbol,
            seed: Double(style.color) * 1.3,
            size: size
        )
    }
}
