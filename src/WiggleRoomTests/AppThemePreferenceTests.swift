//
//  AppThemePreferenceTests.swift
//  WiggleRoomTests
//

import SwiftUI
import XCTest
@testable import WiggleRoom

final class AppThemePreferenceTests: XCTestCase {
    func testThemeOptionsMatchSettingsOrder() {
        XCTAssertEqual(AppThemePreference.allCases, [.system, .light, .dark])
        XCTAssertEqual(AppThemePreference.allCases.map(\.displayName), ["System", "Light", "Dark"])
    }

    func testThemeOptionsMapToColorSchemes() {
        XCTAssertNil(AppThemePreference.system.colorScheme)
        XCTAssertEqual(AppThemePreference.light.colorScheme, .light)
        XCTAssertEqual(AppThemePreference.dark.colorScheme, .dark)
    }

    func testUnknownStoredThemeFallsBackToSystem() {
        XCTAssertEqual(AppThemePreference.resolved(from: "future-theme"), .system)
    }
}
