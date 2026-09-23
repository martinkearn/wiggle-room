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
/// **Deliberately just two fields.** This screen previously also showed a
/// Starling badge, a Connected/Not Connected row, the trackers using the
/// source, and the shared daily request counter. It is pushed from
/// `ConnectedSourcesView`, which holds a live `@Query`, and everything in
/// that list put this view's `body` in a SwiftUI update loop that ran until
/// iOS killed the app on the watchdog.
///
/// So this body observes **nothing** from SwiftData: only local `@State`
/// seeded once in `init`. No live query, no relationship traversal, no model
/// property read during `body`. The duplicate-name check that used to need a
/// query now happens in `connect()`, against a one-shot fetch, at the moment
/// of saving.
///
/// See `docs/swiftdata-update-loops.md` before restoring any of the removed
/// detail here — it belongs on a screen that isn't rebuilt by a
/// `@Query`-backed parent. macOS keeps the richer editor (`SourceEditorCard`),
/// which is not reached that way.
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

    /// Captured once, so `body` never has to ask `existingSource` whether
    /// this is an edit or a fresh connection.
    private let isEditing: Bool

    init(existingSource: ConnectedSource? = nil) {
        self.existingSource = existingSource
        self.isEditing = existingSource != nil
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

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(WiggleRoomColors.error)
                }
            }
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
