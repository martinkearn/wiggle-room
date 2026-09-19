//
//  WiggleEmptyState.swift
//  WiggleRoom
//

import SwiftUI

/// A shared "nothing here yet" visual for every empty list in the app —
/// the app icon's two rings (`EmptyRingsMark`) standing in for the SF Symbol a plain `ContentUnavailableView`
/// would use, so even a blank screen still reads as Wiggle Room rather than
/// generic system chrome. The symbol sits inside the ring exactly where a
/// tracker's own status color would go, tinted the brand color rather than
/// a status one, since there's no pace to report here.
struct WiggleEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                EmptyRingsMark(size: 120)
                Image(systemName: symbol)
                    .font(.wiggleText(size: 34, weight: .medium))
                    .foregroundStyle(WiggleRoomColors.brand)
            }
            .padding(.bottom, 4)

            VStack(spacing: 8) {
                Text(title)
                    .font(WiggleRoomFont.headline(24))
                Text(message)
                    .font(WiggleRoomFont.aside(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                        .font(.wiggleText(.subheadline, weight: .semibold))
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(WiggleRoomColors.brand)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    WiggleEmptyState(
        symbol: "point.3.filled.connected.trianglepath.dotted",
        title: "No Connected Sources",
        message: "Add a source like Starling or Tesla to fetch readings automatically."
    )
}
