//
//  ConnectedSourcesView.swift
//  Ringet
//

import SwiftUI

/// Settings → Connected Sources (§5.2): lists real external connections
/// (Starling, Tesla, …) the user has added, independent of the Tracker
/// list, with an add action. Manual Entry is deliberately never listed
/// here — it isn't a connection, just the fixed "log it yourself" choice
/// every tracker's Source picker also offers (see `AddTrackerView`).
///
/// Kept behind a secondary entry point rather than surfaced in the main
/// flow, since adding a tracker is the primary action (§7.1) and managing
/// sources is occasional, setup-time work.
struct ConnectedSourcesView: View {
    @Environment(TrackerStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.addedSources.isEmpty {
                    ContentUnavailableView(
                        "No Connected Sources",
                        systemImage: "point.3.filled.connected.trianglepath.dotted",
                        description: Text("Add a source like Starling or Tesla to fetch readings automatically.")
                    )
                } else {
                    List(store.addedSources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.displayName)
                                .font(.headline)
                            Text(source.providerId.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Connected Sources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        AddSourceView()
                    } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                }
            }
        }
    }
}

#Preview {
    ConnectedSourcesView()
        .environment(TrackerStore())
}
