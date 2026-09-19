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
    let colorIndex: Int
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            WobblyBadge(
                color: TrackerPalette.color(at: colorIndex),
                symbol: symbol,
                seed: Double(colorIndex) * 1.3,
                size: size
            )
            Text(title)
        }
    }
}

/// The badge for a connected source's provider (Starling → Sky, Tesla →
/// Peach, Manual → Toffee), so a source reads as its provider at a glance.
struct ProviderBadge: View {
    let providerId: String
    var size: CGFloat = 36

    private var style: (symbol: String, color: Int) {
        switch providerId {
        case "starling": ("creditcard.fill", 2)
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
