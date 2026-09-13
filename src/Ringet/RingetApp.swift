//
//  RingetApp.swift
//  Ringet
//
//  Created by Martin Kearn on 13/09/2026.
//

import SwiftUI

@main
struct RingetApp: App {
    @State private var store = TrackerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
