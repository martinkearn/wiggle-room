//
//  AddSourcePickerView.swift
//  WiggleRoom
//

import SwiftUI

/// First step of adding a connected source: choose the kind of source.
/// Starling leads to token entry (`AddSourceView`); Tesla is listed but
/// only shows a "Coming soon" screen until its OAuth setup (§5.4) exists.
struct AddSourcePickerView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    AddSourceView()
                } label: {
                    SettingsLabel(title: "Starling", symbol: "creditcard.fill", colorIndex: 2)
                }
                NavigationLink {
                    TeslaComingSoonView()
                } label: {
                    SettingsLabel(title: "Tesla", symbol: "bolt.car.fill", colorIndex: 5)
                }
            } header: {
                Text("Choose a Source Type")
                    .font(WiggleRoomFont.headline(15, weight: 650))
            }
        }
        .navigationTitle("Add Source")
        .inlineNavigationBarIfAvailable()
    }
}

struct TeslaComingSoonView: View {
    var body: some View {
        WiggleEmptyState(
            symbol: "bolt.car.fill",
            title: "Tesla — Coming Soon",
            message: "Tesla support isn't available yet."
        )
        .navigationTitle("Tesla")
        .inlineNavigationBarIfAvailable()
    }
}

#Preview {
    NavigationStack { AddSourcePickerView() }
}
