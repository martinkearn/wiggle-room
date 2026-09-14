//
//  RingetColors.swift
//  RingetShared
//

import SwiftUI

/// Shared color language for pace status (§3.2) — calm, not alarming, but
/// unambiguously traffic-light: green/amber/red map to `PaceStatus`. Lives in
/// the shared target so widgets/watch complications use the exact same
/// colors as the main app rather than an approximation.
enum RingetColors {
    /// Outer ring — a clock, not a status indicator.
    static let paceRing = Color.gray
    /// On track.
    static let good = Color(red: 0.20, green: 0.60, blue: 0.40)
    /// Near target — a small tolerance band, not yet a problem.
    static let warning = Color(red: 0.85, green: 0.60, blue: 0.10)
    /// Needs attention.
    static let bad = Color(red: 0.80, green: 0.25, blue: 0.20)
}
