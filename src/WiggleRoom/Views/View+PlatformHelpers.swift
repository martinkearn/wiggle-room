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

    /// macOS sheets indent a `NavigationStack` title (space reserved for
    /// leading toolbar items that sheets don't use). Hides the toolbar title
    /// and draws a left-aligned heading in the content instead, like a native
    /// macOS sheet. Buttons stay in the sheet's bottom bar. No-op on iOS.
    @ViewBuilder
    func leadingSheetTitle(_ title: String) -> some View {
        #if os(macOS)
        self
            .toolbar(removing: .title)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(title)
                    .font(WiggleRoomFont.headline(22, weight: 650))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }
        #else
        self
        #endif
    }
}
