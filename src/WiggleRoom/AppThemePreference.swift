//
//  AppThemePreference.swift
//  WiggleRoom
//

import SwiftUI

let appThemePreferenceKey = "appThemePreference"

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
