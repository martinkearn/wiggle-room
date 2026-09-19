//
//  EmptyRingsMark.swift
//  WiggleRoom
//

import SwiftUI

/// The "nothing here yet" ring graphic — the app's two-ring motif (§3.4),
/// drawn faint. Shared so the tracker list's empty state and the widgets'
/// "Loading data…" state show the same picture. `size` is the outer
/// diameter; stroke widths and the inner ring scale with it.
struct EmptyRingsMark: View {
    var size: CGFloat = 132

    var body: some View {
        let line = size * 0.075
        ZStack {
            Circle()
                .stroke(WiggleRoomColors.brand.opacity(0.35), lineWidth: line)
                .frame(width: size, height: size)
            Circle()
                .stroke(WiggleRoomColors.brandWarm.opacity(0.5), lineWidth: line)
                .frame(width: size * 0.7, height: size * 0.7)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    EmptyRingsMark()
}
