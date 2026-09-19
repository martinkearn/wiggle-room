//
//  View+PlatformHelpers.swift
//  WiggleRoom
//

import SwiftUI

extension View {
    /// `.keyboardType` is UIKit-only; this is a no-op on macOS.
    @ViewBuilder
    func decimalKeyboardIfAvailable() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// `.navigationBarTitleDisplayMode` is UIKit-only; this is a no-op on macOS.
    @ViewBuilder
    func inlineNavigationBarIfAvailable() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// macOS sheets put `.cancellationAction`/`.confirmationAction` buttons in
    /// a bottom bar; these place them in the top toolbar instead (Cancel
    /// leading, Save trailing, title in between). Unchanged on iOS.
    static var sheetCancel: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .cancellationAction
        #endif
    }

    static var sheetConfirm: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .confirmationAction
        #endif
    }
}
