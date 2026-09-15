//
//  ContentView.swift
//  WiggleRoom
//
//  Created by Martin Kearn on 13/09/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
        #else
        TrackerListView()
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
