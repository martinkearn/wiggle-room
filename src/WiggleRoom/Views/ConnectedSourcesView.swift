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
///
/// **Platforms diverge substantially here, deliberately** (2026-09-18):
/// iOS keeps a `List` of rows pushing to a full-screen `AddSourceView` via
/// `NavigationLink` — normal, idiomatic iOS Settings-style navigation.
/// macOS instead edits each source **inline**, directly in this pane, with
/// no pop-up sheet/dialog at all, and its own "Add Source" affordance
/// lives inside the pane's content rather than a shared window toolbar —
/// per explicit design direction to match modern macOS conventions
/// (System Settings' own sidebar-plus-inline-content style, also used by
/// Claude's own desktop app) rather than the sheet-based flow tried first.
struct ConnectedSourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    @State private var sourcePendingRemoval: ConnectedSource?
    @State private var removalBlockedMessage: String?
    #if os(macOS)
    @State private var isAddingSource = false
    #endif

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connected Sources")
                .font(.title2.weight(.semibold))

            if addedSources.isEmpty && !isAddingSource {
                WiggleEmptyState(
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    title: "No Connected Sources",
                    message: "Add a source like Starling or Tesla to fetch readings automatically.",
                    actionTitle: "Add Source",
                    action: { isAddingSource = true }
                )
                .frame(minHeight: 260)
            } else {
                VStack(spacing: 12) {
                    ForEach(addedSources) { source in
                        SourceEditorCard(source: source) {
                            requestRemoval(of: source)
                        }
                    }
                    if isAddingSource {
                        NewSourceCard(
                            onCancel: { isAddingSource = false },
                            onAdd: { newSource in
                                modelContext.insert(newSource)
                                try? modelContext.save()
                                isAddingSource = false
                            }
                        )
                    }
                }

                // Lives inside this pane's own content, not the window's
                // shared toolbar — "Add Source" is a Connected Sources
                // action, not app-wide chrome.
                if !isAddingSource {
                    Button {
                        isAddingSource = true
                    } label: {
                        Label("Add Source", systemImage: "plus")
                    }
                }
            }

            Spacer()
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
    #else
    /// No `NavigationStack` of its own — pushed as a destination from
    /// `SettingsView`'s own stack (§7.1/§7.2's iOS Settings screen), not
    /// presented standalone. Nesting a second `NavigationStack` inside
    /// another breaks back-button/toolbar behavior, so this relies entirely
    /// on whatever stack is hosting it.
    private var iosBody: some View {
        Group {
            if addedSources.isEmpty {
                WiggleEmptyState(
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    title: "No Connected Sources",
                    message: "Add a source like Starling or Tesla to fetch readings automatically."
                )
            } else {
                List(addedSources) { source in
                    NavigationLink {
                        AddSourceView(existingSource: source)
                    } label: {
                        row(for: source)
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
        .inlineNavigationBarIfAvailable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    AddSourceView()
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
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
    #endif

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

#if os(macOS)
/// Shared by `SourceEditorCard` and `NewSourceCard` — both validate a
/// Starling token the same way and need to explain the same failures.
private func starlingConnectErrorMessage(for error: Error) -> String {
    switch error {
    case StarlingAPIError.invalidToken:
        return "That token was rejected — check it's current and has account:read/balance:read scopes."
    case StarlingAPIError.rateLimited, StarlingAPIError.budgetExceeded:
        return "Starling is rate-limiting requests right now — try again shortly."
    case StarlingAPIError.network:
        return "Couldn't reach Starling — check your connection and try again."
    default:
        return "Couldn't connect — try again."
    }
}

/// One existing source, edited **in place** — no pop-up. Renaming is a
/// live, always-saved binding straight to the model (trivial, no
/// validation needed); the Personal Access Token is a separate local draft
/// with its own explicit "Update" action, since a token genuinely does
/// need validating against Starling before it's trusted (§5.3) — unlike
/// the name, silently saving a bad token as you type would be a real bug,
/// not a convenience.
private struct SourceEditorCard: View {
    @Bindable var source: ConnectedSource
    let onRemove: () -> Void

    @Environment(\.modelContext) private var modelContext
    /// Pre-filled from `source.credentialToken` (not left blank) — a
    /// Starling personal access token is user-entered, not a system
    /// secret, so there's no reason to hide it (unlike, say, an OS
    /// keychain-managed password): showing what's actually stored is what
    /// makes it obvious at a glance whether this source is genuinely
    /// connected, and lets it be reviewed/copied like any other field.
    @State private var token: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didUpdate = false
    @Query(sort: \StarlingRequestLogEntry.date, order: .reverse) private var starlingRequestLog: [StarlingRequestLogEntry]
    @State private var starlingCooldownUntil: Date?

    init(source: ConnectedSource, onRemove: @escaping () -> Void) {
        self.source = source
        self.onRemove = onRemove
        _token = State(initialValue: source.credentialToken ?? "")
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isConnected: Bool {
        !(source.credentialToken ?? "").isEmpty
    }

    private var hasUnsavedChanges: Bool {
        trimmedToken != (source.credentialToken ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: $source.displayName)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .onChange(of: source.displayName) {
                            try? modelContext.save()
                        }
                    Text(source.providerId.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionStatusBadge
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Text("Personal Access Token")
                .font(.caption)
                .foregroundStyle(.secondary)
            // axis: .vertical grows the field to fit a token's real
            // length (Starling's are long strings) rather than scrolling
            // it sideways inside a single-line box.
            TextField("Paste a Personal Access Token", text: $token, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...6)
                .autocorrectionDisabled()
                .onChange(of: token) { didUpdate = false }

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(WiggleRoomColors.error)
                } else if didUpdate {
                    Text("Token updated.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Generate a token at developer.starlingbank.com with account:read and balance:read scopes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await updateToken() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Update")
                    }
                }
                .disabled(trimmedToken.isEmpty || !hasUnsavedChanges || isSaving)
            }

            if source.providerId == "starling" {
                Divider()
                starlingRateLimitSection
            }
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .task { await refreshStarlingCooldown() }
    }

    /// Admin/diagnostic info about this connection's shared Starling
    /// request budget — deliberately lives here (per-source), not on any
    /// individual tracker: the figure is the same regardless of which
    /// tracker asked, since Starling's limit applies per personal access
    /// token, not per tracker (§4.4), so showing it per-tracker would just
    /// repeat the same number in several places. Live, CloudKit-synced —
    /// see `StarlingRequestLogEntry`'s own doc comment for why it reflects
    /// every device sharing this token, not just this one.
    private var starlingRateLimitSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Starling Requests Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(starlingRequestsToday) / \(StarlingRequestBudget.dailyLimit)")
                    .font(.caption.weight(.medium))
            }
            if let starlingCooldownUntil {
                Text("Paused until \(starlingCooldownUntil.formatted(Self.timeFormatter)) after hitting Starling's rate limit.")
                    .font(.caption2)
                    .foregroundStyle(WiggleRoomColors.warning)
            } else {
                Text(StarlingRequestBudget.requestCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var starlingRequestsToday: Int {
        starlingRequestLog.count { Calendar.current.isDateInToday($0.date) }
    }

    private static let timeFormatter: Date.FormatStyle = .init().hour().minute()

    private func refreshStarlingCooldown() async {
        guard source.providerId == "starling" else { return }
        starlingCooldownUntil = await StarlingProvider.sharedBudget.status.cooldownUntil
    }

    private var connectionStatusBadge: some View {
        Label(isConnected ? "Connected" : "Not Connected", systemImage: isConnected ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(isConnected ? WiggleRoomColors.good : WiggleRoomColors.warning)
    }

    private func updateToken() async {
        errorMessage = nil
        didUpdate = false
        isSaving = true
        defer { isSaving = false }

        // Validated against a draft, not the persisted `source` — nothing
        // about the real record changes until the token actually works.
        let draft = ConnectedSource(providerId: source.providerId, displayName: source.displayName, credentialToken: trimmedToken)
        do {
            _ = try await StarlingProvider(connection: draft).listAvailableTargets(for: draft)
        } catch {
            errorMessage = starlingConnectErrorMessage(for: error)
            return
        }

        source.credentialToken = trimmedToken
        try? modelContext.save()
        didUpdate = true
    }
}

/// An inline "add a new source" card, shown at the end of the list only
/// while adding — replaces the sheet-based `AddSourceView` flow on macOS.
/// Same token-validate-before-save behavior as `SourceEditorCard`'s update
/// path.
private struct NewSourceCard: View {
    let onCancel: () -> Void
    let onAdd: (ConnectedSource) -> Void

    @State private var displayName = "My Starling Account"
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Source")
                .font(.headline)

            TextField("Name", text: $displayName)
                .textFieldStyle(.roundedBorder)

            Text("Personal Access Token")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Paste a Personal Access Token", text: $token, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...6)
                .autocorrectionDisabled()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WiggleRoomColors.error)
            }

            Text("Generate a personal access token at developer.starlingbank.com with account:read and balance:read scopes.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedToken.isEmpty || isConnecting)
            }
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Starling" : trimmedName
        let draft = ConnectedSource(providerId: "starling", displayName: resolvedName, credentialToken: trimmedToken)

        do {
            // An empty account list is still a valid token (an edge-case
            // Starling login with no accounts) — only a thrown error
            // counts as a failed connection.
            _ = try await StarlingProvider(connection: draft).listAvailableTargets(for: draft)
        } catch {
            errorMessage = starlingConnectErrorMessage(for: error)
            return
        }

        onAdd(draft)
    }
}
#endif

#Preview {
    #if os(macOS)
    ConnectedSourcesView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .frame(width: 640, height: 440)
    #else
    NavigationStack {
        ConnectedSourcesView()
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    #endif
}
