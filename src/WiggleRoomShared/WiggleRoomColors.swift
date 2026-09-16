//
//  WiggleRoomColors.swift
//  WiggleRoomShared
//

import SwiftUI

/// Shared color language for pace status (§3.2) — calm, not alarming, but
/// unambiguously traffic-light: green/amber/red map to `PaceStatus`. Lives in
/// the shared target so widgets/watch complications use the exact same
/// colors as the main app rather than an approximation.
///
/// Palette direction: everyday finance-app color (flat system green/red,
/// stop-sign urgency) is deliberately avoided per §3.2. These are warmer,
/// slightly desaturated, hand-picked hues — "Meadow" not "systemGreen",
/// "Clay" not "systemRed" — so the app reads as considered rather than
/// templated, while keeping every state instantly distinguishable at a
/// glance and in both appearances.
enum WiggleRoomColors {
    /// Outer ring — a clock, not a status indicator. Warm graphite, not a
    /// cold system gray, so it still feels like part of the same palette.
    static let paceRing = Color.dynamic(
        light: (0.58, 0.57, 0.60), dark: (0.47, 0.46, 0.50)
    )

    /// On track / ahead of pace — "Meadow": a calm, confident green.
    static let good = Color.dynamic(
        light: (0.15, 0.55, 0.42), dark: (0.32, 0.78, 0.60)
    )

    /// Early-warning band, 1–5% behind (§3.2) — "Marmalade": a genuine
    /// amber, distinct from both green and red, corrective rather than
    /// alarming.
    static let warning = Color.dynamic(
        light: (0.82, 0.55, 0.10), dark: (0.95, 0.70, 0.28)
    )

    /// Needs attention, >5% behind — "Clay": amber-leaning red, reserved for
    /// genuine urgency rather than the default "behind" color.
    static let bad = Color.dynamic(
        light: (0.78, 0.32, 0.22), dark: (0.94, 0.48, 0.38)
    )

    /// Stale/error state (§8.4) — "Ash Amber": visibly different from both
    /// `warning` and `bad` (cooler, more muted) so a connectivity problem is
    /// never mistaken for being behind pace.
    static let error = Color.dynamic(
        light: (0.62, 0.48, 0.18), dark: (0.80, 0.66, 0.38)
    )

    /// Neutral/refreshing — cool grey-blue, per §3.2.
    static let refreshing = Color.dynamic(
        light: (0.42, 0.48, 0.58), dark: (0.62, 0.68, 0.78)
    )

    /// The app's brand identity color — deliberately a different hue family
    /// (violet) from every status color above, so chrome (buttons, tint,
    /// the app icon) never gets read as a pace signal. "Ribbon."
    static let brand = Color.dynamic(
        light: (0.35, 0.29, 0.74), dark: (0.62, 0.56, 0.98)
    )

    /// The brand's warm second hue, used only in gradients (icon, hero
    /// moments) — never alone, and never for status. "Sherbet."
    static let brandWarm = Color.dynamic(
        light: (0.92, 0.45, 0.38), dark: (0.97, 0.56, 0.48)
    )

    /// A warm paper-like surface tint for cards, sitting a half-step off the
    /// system grouped background so cards read as considered rather than
    /// the platform default `secondarySystemFill`.
    static let cardSurface = Color.dynamic(
        light: (0.96, 0.95, 0.94), dark: (0.14, 0.14, 0.16)
    )
}

extension Color {
    /// Cross-platform "the system's default window/card background" —
    /// `UIColor.systemBackground` on iOS has no direct macOS equivalent, so
    /// widgets/extensions that need a background reach for this instead.
    static var widgetBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(watchOS)
        Color.black
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// Builds a `Color` that switches between two sRGB values by appearance,
    /// on every platform this app ships on. watchOS has no light appearance
    /// (the system is always dark), so it always resolves to `dark`.
    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(watchOS)
        Color(red: dark.0, green: dark.1, blue: dark.2)
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
}
