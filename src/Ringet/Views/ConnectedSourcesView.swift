//
//  ConnectedSourcesView.swift
//  Ringet
//

import SwiftUI

/// Settings → Connected Sources (§5.2): lists all configured sources,
/// independent of the Tracker list, with an add action. Kept behind a
/// secondary entry point rather than surfaced in the main flow, since
/// adding a tracker is the primary action (§7.1) and managing sources is
/// occasional, setup-time work.
struct ConnectedSourcesView: View {
    @Environment(TrackerStore.self) private var store

    var body: some View {
        NavigationStack {
            List(store.connectedSources) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.displayName)
                        .font(.headline)
                    Text(source.providerId.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
