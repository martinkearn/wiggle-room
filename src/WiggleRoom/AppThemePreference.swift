//
//  AppThemePreference.swift
//  WiggleRoom
//

import SwiftUI

/// Standard `UserDefaults` key for the host app's appearance preference.
/// Widgets and companion extensions keep their own system appearance rather
/// than reading this app-local setting through the App Group.
let appThemePreferenceKey = "appThemePreference"

/// Settings → General appearance choices. `allCases` is the picker order,
/// and `resolved(from:)` deliberately falls back to System so a future raw
/// value or corrupted preference cannot force an invalid colour scheme.
enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolved(from rawValue: String) -> AppThemePreference {
        AppThemePreference(rawValue: rawValue) ?? .system
    }
}
