//
//  AddSourceView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Add Source (§5.2/§5.3): Starling personal-access-token entry. Validates
/// the token by actually listing accounts before saving anything — a bad or
/// expired token is never silently stored as though it were a working
/// connection. Tesla's OAuth-based setup (§5.4) isn't built yet, so Starling
/// is the only option offered here for now.
///
/// Doubles as the **reconnect** flow when given `existingSource`: re-enters
/// a token for an existing `ConnectedSource` in place, rather than
/// requiring the source (and every tracker using it) to be deleted and
/// recreated. The token itself lives directly on `ConnectedSource
/// .credentialToken` (§6/§11) — synced via CloudKit exactly like the rest
/// of the app's data, so reconnecting is normally only needed after
/// actually revoking/rotating the token at Starling, not because of a
/// cross-device sync gap.
struct AddSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, this view reconnects an existing source in place (new
    /// token, same `ConnectedSource` record) instead of creating a new one.
    var existingSource: ConnectedSource?

    @State private var displayName: String
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @Query(sort: \StarlingRequestLogEntry.date, order: .reverse) private var starlingRequestLog: [StarlingRequestLogEntry]
    @State private var starlingCooldownUntil: Date?

    /// The *other* connected sources' names, used only by `isDuplicateName`
    /// — a one-shot snapshot taken when this screen appears, deliberately
    /// **not** a live `@Query`.
    ///
    /// A second live `@Query` over an entity the presenting view already
    /// queries is an infinite SwiftUI update loop, not merely redundant.
    /// `ConnectedSourcesView` queries `ConnectedSource`, and
    /// `NavigationLink`'s destination is built *inside* that parent's body,
    /// so this view — and its query — is reconstructed on every parent
    /// pass. This query's own fetch then notifies SwiftData's change
    /// observers, which invalidates the parent's query on the same entity,
    /// which rebuilds this view again, forever. Reproduced on iOS at ~750
    /// body evaluations per second with memory climbing ~4 MB/s until the
    /// scene-update watchdog killed the app (0x8BADF00D); a live `@Query`
    /// here was the cause. `AddTrackerView`'s own source picker reaches
    /// this screen the same way, so this is not specific to one entry
    /// point. A snapshot is sufficient regardless: this is a transient
    /// editor, and `connect()` re-checks against a fresh fetch before it
    /// actually saves anything.
    @State private var otherSourceNames: [String] = []

    init(existingSource: ConnectedSource? = nil) {
        self.existingSource = existingSource
        _displayName = State(initialValue: existingSource?.displayName ?? "My Starling Account")
        // Pre-filled from the stored token (not left blank) — a Starling
        // personal access token is user-entered, not a system secret, so
        // there's no reason to hide it, and showing what's actually
        // stored is what makes it obvious at a glance whether this source
        // is genuinely connected rather than looking connected with
        // nothing behind it.
        _token = State(initialValue: existingSource?.credentialToken ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ProviderBadge(providerId: existingSource?.providerId ?? "starling", size: 46)
                    Text("Starling")
                        .font(WiggleRoomFont.headline(22, weight: 650))
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Name", text: $displayName)
                if isDuplicateName {
                    Text("A source named \u{201C}\(trimmedDisplayName)\u{201D} already exists.")
                        .font(.wiggleText(.caption))
                        .foregroundStyle(WiggleRoomColors.error)
                }
                if let existingSource {
                    connectionStatusRow(for: existingSource)
                }
                // axis: .vertical grows the field to fit a token's real
                // length (Starling's are long strings) rather than
                // scrolling it sideways in a single-line box.
                TextField("Paste a Personal Access Token", text: $token, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...6)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Details")
                    .font(WiggleRoomFont.headline(15, weight: 650))
            } footer: {
                Text(tokenFieldFooter)
            }

            // Only for an existing source — a brand new one has no trackers
            // yet, so this section would always be empty.
            if let existingSource, let trackers = existingSource.trackers, !trackers.isEmpty {
                Section {
                    ForEach(trackers) { tracker in
                        Text(tracker.name)
                    }
                } header: {
                    Text("Trackers Using This Source")
                        .font(WiggleRoomFont.headline(15, weight: 650))
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(WiggleRoomColors.error)
                }
            }

            // Admin/diagnostic info, not part of setting up the connection
            // itself — kept in its own section at the bottom, and only for
            // an existing (already-connected) source, since there's nothing
            // meaningful to show before a token has ever been used.
            if existingSource != nil {
                starlingRateLimitSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(existingSource == nil ? "Add Source" : "Edit Source")
        .inlineNavigationBarIfAvailable()
        .task {
            loadOtherSourceNames()
            await refreshStarlingCooldown()
        }
        .toolbar {
            // Only on macOS, where this view is always presented as a
            // sheet (`ConnectedSourcesView`'s `.sheet`) with no other way
            // to dismiss it — Esc aside — now that it's no longer a pushed
            // NavigationLink destination there. iOS keeps the push, which
            // already has a free back button, so an explicit Cancel here
            // would just be redundant with it.
            #if os(macOS)
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            #endif
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        // "Save", not "Reconnect" — this same button also
                        // covers a plain rename with no token change at
                        // all, where "Reconnect" read oddly (nothing was
                        // actually disconnected). Saving still validates
                        // the token against Starling either way (§5.3) and
                        // reports a failure inline if it's no longer valid.
                        Text(existingSource == nil ? "Connect" : "Save")
                    }
                }
                .disabled(trimmedToken.isEmpty || isConnecting || isDuplicateName)
            }
        }
    }

    private var tokenFieldFooter: String {
        "Create a free personal access token at developer.starlingbank.com with account:read and balance:read."
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespaces)
    }

    /// Whether `displayName` (trimmed, case-insensitive) matches another
    /// connected source already in the list — excluding `existingSource`
    /// itself, so reconnecting/renaming a source without changing its name
    /// doesn't flag against itself.
    private var isDuplicateName: Bool {
        nameCollides(with: trimmedDisplayName)
    }

    private func nameCollides(with name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return otherSourceNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Refreshes `otherSourceNames`. Excludes `existingSource` itself, so
    /// reconnecting/renaming a source without changing its name doesn't
    /// flag against itself, and excludes Manual Entry, which isn't a
    /// connected source and can't collide with one.
    private func loadOtherSourceNames() {
        let descriptor = FetchDescriptor<ConnectedSource>(
            predicate: #Predicate { $0.providerId != "manual" }
        )
        let sources = (try? modelContext.fetch(descriptor)) ?? []
        let ownID = existingSource?.id
        otherSourceNames = sources.filter { $0.id != ownID }.map(\.displayName)
    }

    /// "Connected"/"Not Connected", based on whether `source` actually has
    /// a stored token right now — not whether this screen's own `token`
    /// field currently has text in it, which just reflects what's about to
    /// be saved (possibly still unedited, possibly cleared).
    private func connectionStatusRow(for source: ConnectedSource) -> some View {
        let isConnected = !(source.credentialToken ?? "").isEmpty
        return Label(isConnected ? "Connected" : "Not Connected", systemImage: isConnected ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.wiggleText(.subheadline, weight: .medium))
            .foregroundStyle(isConnected ? WiggleRoomColors.good : WiggleRoomColors.warning)
    }

    /// Admin/diagnostic info about this specific Starling connection's
    /// shared request budget — this screen is the only place an iOS user
    /// can see it at all, since iOS has no dedicated Settings scene (§7.2).
    /// Deliberately lives here (Connected Sources → this source), not on
    /// any individual tracker — the figure is the same regardless of which
    /// tracker asked, since Starling's limit applies per personal access
    /// token, not per tracker (§4.4), so showing it per-tracker would just
    /// repeat the same number in several places. The request count is a
    /// live, CloudKit-synced `StarlingRequestLogEntry` query — see that
    /// model's own doc comment for why it reflects every device sharing
    /// this token, not just this one.
    private var starlingRateLimitSection: some View {
        Section {
            HStack {
                Text("Starling Requests Today")
                    .font(WiggleRoomFont.cardLabel)
                Spacer()
                Text("\(starlingRequestsToday) / \(StarlingRequestBudget.dailyLimit)")
                    .foregroundStyle(.secondary)
            }
            if let starlingCooldownUntil {
                Text("Taking a breather until \(starlingCooldownUntil.formatted(Self.timeFormatter)) — Starling's rate limit was hit.")
                    .font(.wiggleText(.caption))
                    .foregroundStyle(WiggleRoomColors.warning)
            }
        } footer: {
            Text(StarlingRequestBudget.requestCaption)
        }
    }

    /// Counts against one precomputed start-of-day rather than calling
    /// `Calendar.isDateInToday` per entry — this runs on every body pass
    /// over the whole (up to three days of) request log, so the per-element
    /// calendar work is the expensive part, not the comparison.
    private var starlingRequestsToday: Int {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return starlingRequestLog.count { $0.date >= startOfToday }
    }

    private static let timeFormatter: Date.FormatStyle = .init().hour().minute()

    private func refreshStarlingCooldown() async {
        starlingCooldownUntil = await StarlingProvider.sharedBudget.status.cooldownUntil
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Starling" : trimmedName

        // Re-checked against a fresh fetch rather than trusting the
        // snapshot behind the inline warning — that snapshot is taken on
        // appear, so another device's source (or one added through the
        // nested Add Source flow) could have arrived since. Checked before
        // the network call so a name collision doesn't spend a Starling
        // request to then be rejected anyway.
        loadOtherSourceNames()
        guard !nameCollides(with: resolvedName) else {
            errorMessage = "A source named \u{201C}\(resolvedName)\u{201D} already exists."
            return
        }

        // Validated against a draft, not the persisted `existingSource` —
        // nothing about the real record changes until the token actually
        // works.
        let draftSource = ConnectedSource(
            providerId: "starling",
            displayName: resolvedName,
            credentialToken: trimmedToken
        )

        let provider = StarlingProvider(connection: draftSource)
        do {
            // Validates the token actually works before persisting anything
            // to SwiftData — an empty account list is still a valid token
            // (an edge-case Starling login with no accounts), so only a
            // thrown error counts as a failed connection.
            _ = try await provider.listAvailableTargets(for: draftSource)
        } catch {
            errorMessage = Self.errorMessage(for: error)
            return
        }

        if let existingSource {
            existingSource.displayName = resolvedName
            existingSource.credentialToken = trimmedToken
        } else {
            modelContext.insert(draftSource)
        }
        try? modelContext.save()
        dismiss()
    }

    private static func errorMessage(for error: Error) -> String {
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
}

#Preview {
    NavigationStack {
        AddSourceView()
    }
    .modelContainer(PreviewData.container)
}
