//
//  ContentView.swift
//  WiggleRoom
//
//  Created by Martin Kearn on 13/09/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TrackerStore.self) private var store

    var body: some View {
        Group {
            if store.isResettingData {
                ProgressView("Resetting app data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(macOS)
                MacRootView()
                #else
                TrackerListView()
                #endif
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
