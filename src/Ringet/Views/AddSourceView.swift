//
//  AddSourceView.swift
//  Ringet
//

import SwiftUI

/// Placeholder for adding a new connected source (§5.2). Provider setup
/// (Starling's personal access token entry, Tesla's OAuth flow, §5.3/§5.4)
/// isn't built yet — this is intentionally a stub so the "Add Source" entry
/// point exists ahead of that work, rather than something to flesh out now.
struct AddSourceView: View {
    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "point.3.filled.connected.trianglepath.dotted",
            description: Text("Adding Starling, Tesla, or another manual source isn't available yet.")
        )
        .navigationTitle("Add Source")
        .inlineNavigationBarIfAvailable()
    }
}

private extension View {
    /// `.navigationBarTitleDisplayMode` is UIKit-only; this is a no-op on macOS.
    @ViewBuilder
    func inlineNavigationBarIfAvailable() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#Preview {
    NavigationStack {
        AddSourceView()
    }
}
