//
//  AddSourcePickerView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// First step of adding a connected source: choose the kind of source.
/// Starling leads to token entry (`AddSourceView`); Apple Health leads to an
/// authorisation request (`AddHealthSourceView`) and is offered only on
/// iOS/iPadOS, and only while no Health source exists yet — it is the device
/// owner's own Health store, so a second one would mean nothing. Tesla is
/// listed but only shows a "Coming soon" screen until its OAuth setup (§5.4)
/// exists.
struct AddSourcePickerView: View {
    #if os(iOS)
    @Environment(\.modelContext) private var modelContext
    /// A one-shot read taken as the screen appears, held as a plain `Bool`.
    /// This screen is pushed from `ConnectedSourcesView`'s live `@Query`, so
    /// it must not observe SwiftData from `body` — see
    /// `docs/swiftdata-update-loops.md`.
    @State private var hasHealthSource = false
    #endif

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AddSourceView()
                } label: {
                    SettingsLabel(title: "Starling", symbol: "creditcard.fill", colorIndex: 2)
                }
                #if os(iOS)
                if !hasHealthSource {
                    NavigationLink {
                        AddHealthSourceView()
                    } label: {
                        SettingsLabel(title: "Apple Health", symbol: "heart.fill", colorIndex: 1)
                    }
                }
                #endif
                NavigationLink {
                    TeslaComingSoonView()
                } label: {
                    SettingsLabel(title: "Tesla", symbol: "bolt.car.fill", colorIndex: 5)
                }
            } header: {
                Text("Choose a Source Type")
                    .font(WiggleRoomFont.headline(15, weight: 650))
            } footer: {
                #if os(iOS)
                Text("Apple Health supplies your latest weight to a Weight loss tracker. Starling supplies account balances.")
                #else
                Text("Starling supplies account balances.")
                #endif
            }
        }
        .navigationTitle("Add Source")
        .inlineNavigationBarIfAvailable()
        #if os(iOS)
        .task {
            let descriptor = FetchDescriptor<ConnectedSource>(
                predicate: #Predicate { $0.providerId == "healthkit" }
            )
            hasHealthSource = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
        }
        #endif
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
        .modelContainer(PreviewData.container)
}
