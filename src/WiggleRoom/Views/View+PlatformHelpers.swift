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

    /// macOS sheets centre/indent a `NavigationStack` title, which reads as
    /// "tabbed right" against the left-aligned form content beneath it.
    /// Hides the toolbar title and draws a flush-left one instead. No-op on iOS.
    @ViewBuilder
    func leadingSheetTitle(_ title: String) -> some View {
        #if os(macOS)
        self
            .toolbar(removing: .title)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        #else
        self
        #endif
    }
}
