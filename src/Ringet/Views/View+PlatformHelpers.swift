//
//  View+PlatformHelpers.swift
//  Ringet
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
