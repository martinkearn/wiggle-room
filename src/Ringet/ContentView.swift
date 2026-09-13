//
//  ContentView.swift
//  Ringet
//
//  Created by Martin Kearn on 13/09/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TrackerListView()
    }
}

#Preview {
    ContentView()
        .environment(TrackerStore())
}
