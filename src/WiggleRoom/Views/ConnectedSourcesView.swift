//
//  ConnectedSourcesView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Settings → Connected Sources (§5.2): lists real external connections
/// (Starling, Tesla, …) the user has added, independent of the Tracker
/// list, with add/reconnect/remove actions. Manual Entry is deliberately
/// never listed here — it isn't a connection, just the fixed "log it
/// yourself" choice every tracker's Source picker also offers (see
/// `AddTrackerView`).
///
/// Kept behind a secondary entry point rather than surfaced in the main
/// flow, since adding a tracker is the primary action (§7.1) and managing
/// sources is occasional, setup-time work.
struct ConnectedSourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    @State private var sourcePendingRemoval: ConnectedSource?
    @State private var removalBlockedMessage: String?
    #if os(macOS)
    // macOS deliberately doesn't use push/back navigation here (see the
    // #else branch below and the 2026-09-18 progress-notes entry) — Add/
    // Reconnect are presented as sheets instead, the same pattern already
    // used everywhere else in the app on macOS (AddTrackerView,
    // ReadingHistoryView). A NavigationLink push into this Settings
    // window's own NavigationStack rendered as a cramped back-chevron/
    // title bar with a squeezed label column, not a native-looking pane.
    @State private var isPresentingAddSource = false
    @State private var sourceToReconnect: ConnectedSource?
    #endif

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
                        Group {
                            #if os(macOS)
                            Button {
                                sourceToReconnect = source
                            } label: {
                                row(for: source)
                            }
                            .buttonStyle(.plain)
                            #else
                            NavigationLink {
                                AddSourceView(existingSource: source)
                            } label: {
                                row(for: source)
                            }
                            #endif
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                requestRemoval(of: source)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connected Sources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    #if os(macOS)
                    Button {
                        isPresentingAddSource = true
                    } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                    #else
                    NavigationLink {
                        AddSourceView()
                    } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                    #endif
                }
            }
            .confirmationDialog(
                "Remove \u{201C}\(sourcePendingRemoval?.displayName ?? "")\u{201D}?",
                isPresented: Binding(
                    get: { sourcePendingRemoval != nil },
                    set: { if !$0 { sourcePendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Source", role: .destructive) {
                    if let source = sourcePendingRemoval {
                        remove(source)
                    }
                    sourcePendingRemoval = nil
                }
            } message: {
                Text("This removes the connection and its stored token everywhere it's synced. Only allowed while no trackers use it.")
            }
            .alert(
                "Can't Remove Source",
                isPresented: Binding(
                    get: { removalBlockedMessage != nil },
                    set: { if !$0 { removalBlockedMessage = nil } }
                )
            ) {
                Button("OK") { removalBlockedMessage = nil }
            } message: {
                Text(removalBlockedMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        .sheet(isPresented: $isPresentingAddSource) {
            NavigationStack {
                AddSourceView()
            }
            .frame(minWidth: 420, minHeight: 260)
        }
        .sheet(item: $sourceToReconnect) { source in
            NavigationStack {
                AddSourceView(existingSource: source)
            }
            .frame(minWidth: 420, minHeight: 260)
        }
        #endif
    }

    private func row(for source: ConnectedSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.displayName)
                .font(WiggleRoomFont.headline(17, weight: 600))
            Text(source.providerId.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// Removing a source out from under trackers that still point at it
    /// would leave them with a `nil` connection (`ConnectedSource`'s
    /// inverse relationship has no cascade rule) — silently and
    /// permanently broken rather than cleanly deleted, so this is blocked
    /// rather than allowed and explained away after the fact.
    private func requestRemoval(of source: ConnectedSource) {
        guard source.trackers?.isEmpty ?? true else {
            let count = source.trackers?.count ?? 0
            removalBlockedMessage = "\(count) tracker\(count == 1 ? "" : "s") still use\(count == 1 ? "s" : "") \u{201C}\(source.displayName)\u{201D}. Delete or move \(count == 1 ? "it" : "them") first."
            return
        }
        sourcePendingRemoval = source
    }

    private func remove(_ source: ConnectedSource) {
        modelContext.delete(source)
        try? modelContext.save()
    }
}

#Preview {
    ConnectedSourcesView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
