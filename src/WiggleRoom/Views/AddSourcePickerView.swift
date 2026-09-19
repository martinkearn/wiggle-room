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
            Section("Choose a Source Type") {
                NavigationLink {
                    AddSourceView()
                } label: {
                    Label("Starling", systemImage: "creditcard")
                }
                NavigationLink {
                    TeslaComingSoonView()
                } label: {
                    Label("Tesla", systemImage: "bolt.car")
                }
            }
        }
        .navigationTitle("Add Source")
        .inlineNavigationBarIfAvailable()
    }
}

struct TeslaComingSoonView: View {
    var body: some View {
        ContentUnavailableView(
            "Tesla — Coming Soon",
            systemImage: "bolt.car",
            description: Text("Tesla support isn't available yet.")
        )
        .navigationTitle("Tesla")
        .inlineNavigationBarIfAvailable()
    }
}

#Preview {
    NavigationStack { AddSourcePickerView() }
}
