//
//  WidgetFamily+LockScreen.swift
//  WiggleRoomWidgets
//

import WidgetKit

extension WidgetFamily {
    /// Lock Screen (accessory) families — too small for a caption under the
    /// loading rings mark, so loading states there show the mark alone.
    var isLockScreen: Bool {
        #if os(macOS)
        false
        #else
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
        #endif
    }
}
