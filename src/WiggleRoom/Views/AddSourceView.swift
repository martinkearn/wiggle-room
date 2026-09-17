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
struct AddSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = "My Starling Account"
    @State private var token = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private let tokenStore: SecureTokenStore = KeychainTokenStore()

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
                Text("Generate a personal access token at developer.starlingbank.com with account:read and balance:read scopes, then paste it here. It's stored in the Keychain, never sent anywhere but Starling itself.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(WiggleRoomColors.error)
                }
            }
        }
        .navigationTitle("Add Source")
        .inlineNavigationBarIfAvailable()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .disabled(trimmedToken.isEmpty || isConnecting)
            }
        }
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        let keychainKey = "starling.\(UUID().uuidString)"
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = ConnectedSource(
            providerId: "starling",
            displayName: trimmedName.isEmpty ? "Starling" : trimmedName,
            credentialKeychainKey: keychainKey
        )

        do {
            try tokenStore.save(token: trimmedToken, for: keychainKey)
        } catch {
            errorMessage = "Couldn't save the token securely — try again."
            return
        }

        let provider = StarlingProvider(connection: source, tokenStore: tokenStore)
        do {
            // Validates the token actually works before persisting anything
            // to SwiftData — an empty account list is still a valid token
            // (an edge-case Starling login with no accounts), so only a
            // thrown error counts as a failed connection.
            _ = try await provider.listAvailableTargets(for: source)
        } catch {
            try? tokenStore.deleteToken(for: keychainKey)
            errorMessage = Self.errorMessage(for: error)
            return
        }

        modelContext.insert(source)
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
