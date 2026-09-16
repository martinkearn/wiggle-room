//
//  ConnectedSourcesView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

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
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    var body: some View {
        NavigationStack {
            Group {
                if addedSources.isEmpty {
                    WiggleEmptyState(
                        symbol: "point.3.filled.connected.trianglepath.dotted",
                        title: "No Connected Sources",
                        message: "Add a source like Starling or Tesla to fetch readings automatically."
                    )
                } else {
                    List(addedSources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.displayName)
                                .font(WiggleRoomFont.headline(17, weight: 600))
                            Text(source.providerId.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
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
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
