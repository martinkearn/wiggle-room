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
///
/// **Deliberately minimal.** This screen once showed a Starling badge, a
/// Connected/Not Connected row, and the trackers using the source as well.
/// It is pushed from `ConnectedSourcesView`, which holds a live `@Query`, and
/// every one of those put this view's `body` in a SwiftUI update loop that
/// ran until iOS killed the app on the watchdog.
///
/// So this body observes **nothing** from SwiftData: no live query, no
/// relationship traversal, no model property read during `body` — only local
/// `@State`, seeded in `init` or once in `.task`. Everything that needs the
/// store reads it outside `body`: the request count in `.task`, the
/// duplicate-name check in `connect()`.
///
/// See `docs/swiftdata-update-loops.md` before adding anything back here.
/// Anything genuinely needing a *live* view of the store belongs on a screen
/// that isn't rebuilt by a `@Query`-backed parent; macOS keeps the richer
/// editor (`SourceEditorCard`), which is not reached that way.
struct AddSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, this view reconnects an existing source in place (new
    /// token, same `ConnectedSource` record) instead of creating a new one.
    ///
    /// Read in `init` and in `connect()`, never in `body` — see the type
    /// note above.
    var existingSource: ConnectedSource?

    @State private var displayName: String
    @State private var token: String
    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// The shared Starling request budget, read once in `.task`. Snapshots,
    /// deliberately — a live `@Query` here is what got the app killed; see
    /// the type note above.
    @State private var starlingRequestsToday = 0
    @State private var starlingCooldownUntil: Date?

    /// Names of the trackers pointed at this source, also captured once in
    /// `.task`. See `namesOfTrackersUsingThisSource()`.
    @State private var trackerNames: [String] = []

    /// Captured once, so `body` never has to ask `existingSource` whether
    /// this is an edit or a fresh connection.
    private let isEditing: Bool

    /// Whether the source already has a token stored, captured in `init`.
    ///
    /// Deliberately reflects what is actually **stored**, not whether the
    /// token field currently has text in it — that only shows what is about
    /// to be saved, possibly still unedited, possibly cleared.
    ///
    /// A snapshot rather than a model read in `body`, for the reason in the
    /// type note. Nothing can change it while this screen is open except
    /// `connect()`, which dismisses on success, so the captured value stays
    /// accurate for the screen's lifetime.
    private let isConnected: Bool

    init(existingSource: ConnectedSource? = nil) {
        self.existingSource = existingSource
        self.isEditing = existingSource != nil
        self.isConnected = !(existingSource?.credentialToken ?? "").isEmpty
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
                TextField("Name", text: $displayName)
                if isEditing {
                    connectionStatusRow
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

            if !trackerNames.isEmpty {
                Section {
                    // Indexed rather than identified by name: these are
                    // display strings, and two trackers could in principle
                    // share one, which would collide as a ForEach id.
                    ForEach(Array(trackerNames.enumerated()), id: \.offset) { _, name in
                        Text(name)
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

            // Only for an existing source — a brand new one has no usage to
            // report, and this is the only place an iOS user can see the
            // figure at all, since iOS has no Settings scene (§7.2).
            if isEditing {
                starlingRateLimitSection
            }
        }
        .task {
            trackerNames = namesOfTrackersUsingThisSource()
            await refreshStarlingStatus()
        }
        .formStyle(.grouped)
        .navigationTitle(isEditing ? "Edit Source" : "Add Source")
        .inlineNavigationBarIfAvailable()
        .toolbar {
            // Only on macOS, where this view is always presented as a
            // sheet with no other way to dismiss it — Esc aside. iOS keeps
            // the push, which already has a free back button, so an
            // explicit Cancel here would just be redundant with it.
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
                        Text(isEditing ? "Save" : "Connect")
                    }
                }
                .disabled(trimmedToken.isEmpty || isConnecting)
            }
        }
    }

    /// "Connected"/"Not Connected" — the same wording, symbols and colours as
    /// the macOS editor's `connectionStatusBadge`, at the text size this
    /// screen's own form rows use rather than the compact card size that card
    /// is tuned for.
    private var connectionStatusRow: some View {
        Label(
            isConnected ? "Connected" : "Not Connected",
            systemImage: isConnected ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .font(.wiggleText(.subheadline, weight: .medium))
        .foregroundStyle(isConnected ? WiggleRoomColors.good : WiggleRoomColors.warning)
    }

    /// The shared daily request budget for this token, worded exactly as the
    /// macOS editor words it (`SourceEditorCard.starlingRateLimitSection`) so
    /// the same figure reads the same on both platforms. The caption sits in
    /// the section footer rather than inline, which is where a Form puts
    /// explanatory text on iOS.
    ///
    /// The count is per *token*, not per source or per device — see
    /// `StarlingRequestLogEntry` for why it is a synced set of records rather
    /// than a counter, and `StarlingRequestBudget` for why the number shown
    /// can't come from this process's own budget actor.
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

    private static let timeFormatter: Date.FormatStyle = .init().hour().minute()

    /// Reads the request count and any active cool-down **once**, when the
    /// screen appears. `.task` is keyed to view identity, so a rebuild of
    /// this view's value doesn't re-run it — which is exactly what keeps this
    /// off the update treadmill described in the type note.
    ///
    /// The figure therefore doesn't tick upward while the screen sits open.
    /// That's the deliberate trade: this is a diagnostic number on a screen
    /// the user opens, reads, and leaves, and a live count is what made the
    /// screen unusable. macOS, which isn't reached through a `@Query`-backed
    /// parent, still shows it live.
    private func refreshStarlingStatus() async {
        starlingRequestsToday = requestCountToday()
        starlingCooldownUntil = await StarlingProvider.sharedBudget.status.cooldownUntil
    }

    /// The trackers pointed at this source, captured as plain names when the
    /// screen appears.
    ///
    /// Reading `existingSource.trackers` from `body` was the worst of the
    /// things this screen used to do: traversing a to-many relationship
    /// faults it in, which is a fetch on the main context — structurally the
    /// same act as a live `@Query`. Read once here instead.
    ///
    /// Kept as `String`s so this view holds no `Tracker` references at all,
    /// which additionally rules out rendering a model whose backing data has
    /// since been deleted or merged away — the separate hard crash
    /// `RingsView` and `TrackerRow` carry their own guards for.
    ///
    /// Sorted for a stable order; the relationship's own order is arbitrary.
    private func namesOfTrackersUsingThisSource() -> [String] {
        (existingSource?.trackers ?? [])
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Counted in the store rather than by fetching and filtering every
    /// entry — the log holds up to three days of records and only today's
    /// are wanted.
    private func requestCountToday() -> Int {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<StarlingRequestLogEntry>(
            predicate: #Predicate { $0.date >= startOfToday }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private var tokenFieldFooter: String {
        "Create a free personal access token at developer.starlingbank.com with account:read and balance:read."
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether another connected source already uses `name`, ignoring case
    /// and excluding `existingSource` itself so renaming a source without
    /// changing its name doesn't flag against itself. A one-shot fetch made
    /// at save time rather than a live `@Query` — the inline
    /// "already exists" warning this used to drive is gone, because keeping
    /// it meant observing SwiftData from `body`; see the type note above.
    private func nameIsTaken(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let descriptor = FetchDescriptor<ConnectedSource>(
            predicate: #Predicate { $0.providerId != "manual" }
        )
        let sources = (try? modelContext.fetch(descriptor)) ?? []
        let ownID = existingSource?.id
        return sources.contains {
            $0.id != ownID && $0.displayName.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Starling" : trimmedName

        // Checked before the network call so a name collision doesn't spend
        // a Starling request only to be rejected anyway.
        guard !nameIsTaken(resolvedName) else {
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
