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

    init(existingSource: ConnectedSource? = nil) {
        self.existingSource = existingSource
        _displayName = State(initialValue: existingSource?.displayName ?? "My Starling Account")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
                SecureField("Personal Access Token", text: $token)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Starling")
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
        .navigationTitle(existingSource == nil ? "Add Source" : "Reconnect")
        .inlineNavigationBarIfAvailable()
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
                        Text(existingSource == nil ? "Connect" : "Reconnect")
                    }
                }
                .disabled(trimmedToken.isEmpty || isConnecting)
            }
        }
    }

    private var tokenFieldFooter: String {
        "Generate a personal access token at developer.starlingbank.com with account:read and balance:read scopes."
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Starling" : trimmedName

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
            return "That token was rejected — check it's current and has account:read/balance:read scopes."
        case StarlingAPIError.rateLimited, StarlingAPIError.budgetExceeded:
            return "Starling is rate-limiting requests right now — try again shortly."
        case StarlingAPIError.network:
            return "Couldn't reach Starling — check your connection and try again."
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
