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
/// **Platforms diverge in presentation, but share the same structure**
/// (2026-09-18, restructured 2026-09-22): both start on a list of connected
/// sources and push into a detail view for one specific source — iOS via a
/// normal `NavigationLink` push to a full-screen `AddSourceView`; macOS via
/// an in-pane list-to-detail swap (no `NavigationStack` runs through
/// `SettingsRootView`'s fixed sidebar, so this pane manages its own
/// selection state instead), editing the selected source **inline** with no
/// pop-up sheet/dialog, per explicit design direction to match modern macOS
/// conventions (System Settings' own sidebar-plus-inline-content style,
/// also used by Claude's own desktop app). Previously macOS skipped the
/// list step and edited every source inline at once; with more than one
/// source that read as dropping straight into a single source's details
/// rather than a menu of sources, so it now lists first like iOS does.
struct ConnectedSourcesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    @State private var sourcePendingRemoval: ConnectedSource?
    @State private var removalBlockedMessage: String?
    #if os(macOS)
    @State private var isAddingSource = false
    @State private var selectedSourceID: PersistentIdentifier?
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
        Group {
            if let selectedSourceID, let selectedSource = addedSources.first(where: { $0.persistentModelID == selectedSourceID }) {
                macDetail(for: selectedSource)
            } else {
                macList
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
            Text("Removes this connection and its token from all your devices. Only possible while no trackers use it.")
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

    /// The intermediate menu — lists every connected source, same as the
    /// iOS `List` below, so both platforms present "which source?" before
    /// "here are its details" rather than macOS jumping straight to one.
    private var macList: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connected Sources")
                .font(WiggleRoomFont.headline(22, weight: 650))

            if addedSources.isEmpty && !isAddingSource {
                WiggleEmptyState(
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    title: "No Connected Sources",
                    message: "Add a source like Starling to fetch readings for you.",
                    actionTitle: "Add Source",
                    action: { isAddingSource = true }
                )
                .frame(minHeight: 260)
            } else {
                VStack(spacing: 4) {
                    ForEach(addedSources) { source in
                        Button {
                            selectedSourceID = source.persistentModelID
                        } label: {
                            HStack {
                                row(for: source)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
    }

    /// One source's details, edited in place — pushed to by `macList`,
    /// popped back to it by the back button rather than a `NavigationStack`
    /// (this pane manages its own selection since `SettingsRootView`'s
    /// sidebar doesn't run one).
    private func macDetail(for source: ConnectedSource) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                selectedSourceID = nil
            } label: {
                Label("Connected Sources", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            SourceEditorCard(source: source) {
                requestRemoval(of: source)
            }

            Spacer()
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
                    message: "Add a source like Starling to fetch readings for you."
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
                    AddSourcePickerView()
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
            Text("Removes this connection and its token from all your devices. Only possible while no trackers use it.")
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
    #endif

    private func row(for source: ConnectedSource) -> some View {
        HStack(spacing: 12) {
            ProviderBadge(providerId: source.providerId, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(WiggleRoomFont.headline(17, weight: 600))
                Text(source.providerId.capitalized)
                    .font(.wiggleText(.subheadline))
                    .foregroundStyle(.secondary)
            }
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
        #if os(macOS)
        if selectedSourceID == source.persistentModelID {
            selectedSourceID = nil
        }
        #endif
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
        return "Starling didn't accept that token. Check it's current and includes account:read and balance:read."
    case StarlingAPIError.rateLimited, StarlingAPIError.budgetExceeded:
        return "Starling is busy right now — try again in a moment."
    case StarlingAPIError.network:
        return "Can't reach Starling. Check your connection and try again."
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
    @State private var duplicateNameMessage: String?
    @Query(sort: \StarlingRequestLogEntry.date, order: .reverse) private var starlingRequestLog: [StarlingRequestLogEntry]
    @State private var starlingCooldownUntil: Date?
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

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
            HStack(alignment: .center, spacing: 10) {
                ProviderBadge(providerId: source.providerId, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: $source.displayName)
                        .textFieldStyle(.plain)
                        .font(WiggleRoomFont.headline(17, weight: 650))
                        // Reverts the edit rather than saving it when it
                        // collides with another source's name — this field
                        // otherwise saves on every keystroke with no
                        // separate confirm step, so a duplicate has to be
                        // caught here, before it ever reaches the model.
                        .onChange(of: source.displayName) { oldValue, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            guard trimmed.isEmpty || !addedSources.contains(where: {
                                $0.id != source.id && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
                            }) else {
                                duplicateNameMessage = "A source named \u{201C}\(trimmed)\u{201D} already exists."
                                source.displayName = oldValue
                                return
                            }
                            duplicateNameMessage = nil
                            try? modelContext.save()
                        }
                    Text(source.providerId.capitalized)
                        .font(.wiggleText(.caption))
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

            if let duplicateNameMessage {
                Text(duplicateNameMessage)
                    .font(.wiggleText(.caption))
                    .foregroundStyle(WiggleRoomColors.error)
            }

            if let trackers = source.trackers, !trackers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trackers Using This Source")
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                    ForEach(trackers) { tracker in
                        Text(tracker.name)
                            .font(.wiggleText(.subheadline))
                    }
                }
            }

            Text("Personal Access Token")
                .font(.wiggleText(.caption))
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
                        .font(.wiggleText(.caption))
                        .foregroundStyle(WiggleRoomColors.error)
                } else if didUpdate {
                    Text("Token updated.")
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Create a token at developer.starlingbank.com with account:read and balance:read.")
                        .font(.wiggleText(.caption2))
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
        .background(.quinary, in: WobblyCard.shape(0, scale: 0.7))
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
                    .font(WiggleRoomFont.cardLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(starlingRequestsToday) / \(StarlingRequestBudget.dailyLimit)")
                    .font(.wiggleText(.caption, weight: .medium))
            }
            if let starlingCooldownUntil {
                Text("Taking a breather until \(starlingCooldownUntil.formatted(Self.timeFormatter)) — Starling's rate limit was hit.")
                    .font(.wiggleText(.caption2))
                    .foregroundStyle(WiggleRoomColors.warning)
            } else {
                Text(StarlingRequestBudget.requestCaption)
                    .font(.wiggleText(.caption2))
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
            .font(.wiggleText(.caption, weight: .medium))
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

    private enum Kind: String, CaseIterable { case starling = "Starling", tesla = "Tesla" }
    @State private var kind = Kind.starling
    @State private var displayName = "My Starling Account"
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return addedSources.contains { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Source")
                .font(WiggleRoomFont.headline(17, weight: 650))

            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if kind == .tesla {
                Text("Tesla — Coming soon")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { onCancel() }
                }
            } else {
            TextField("Name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            if isDuplicateName {
                Text("A source named \u{201C}\(displayName.trimmingCharacters(in: .whitespaces))\u{201D} already exists.")
                    .font(.wiggleText(.caption))
                    .foregroundStyle(WiggleRoomColors.error)
            }

            Text("Personal Access Token")
                .font(.wiggleText(.caption))
                .foregroundStyle(.secondary)
            TextField("Paste a Personal Access Token", text: $token, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...6)
                .autocorrectionDisabled()

            if let errorMessage {
                Text(errorMessage)
                    .font(.wiggleText(.caption))
                    .foregroundStyle(WiggleRoomColors.error)
            }

            Text("Create a personal access token at developer.starlingbank.com with account:read and balance:read.")
                .font(.wiggleText(.caption2))
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
                .disabled(trimmedToken.isEmpty || isConnecting || isDuplicateName)
            }
            }
        }
        .padding(14)
        .background(.quinary, in: WobblyCard.shape(0, scale: 0.7))
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
