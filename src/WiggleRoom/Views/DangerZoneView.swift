//
//  DangerZoneView.swift
//  WiggleRoom
//

import SwiftUI
import SwiftData

/// Settings → Danger Zone: destructive, whole-account operations, kept in
/// their own top-level menu (last in the list, red glyph) rather than tucked
/// under General/the settings root — so a routine settings visit never sits
/// next to a "reset everything" button, and finding it takes a deliberate
/// step. Previously lived inline on General (macOS) and the Settings root
/// (iOS); split out into its own page 2026-09-22 so both platforms share one
/// structure, matching how Connected Sources already gets its own menu
/// rather than living inline on another page.
///
/// A deliberate, explicit escape hatch — see `TrackerStore.resetAllData()`'s
/// own doc comment for why this exists at all (a real data-corruption
/// incident, 2026-09-18) rather than being a routine feature.
struct DangerZoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TrackerStore.self) private var store
    @State private var isPresentingResetConfirmation = false

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
            Text("Danger Zone")
                .font(WiggleRoomFont.headline(22, weight: 650))
                .foregroundStyle(WiggleRoomColors.bad)

            VStack(alignment: .leading, spacing: 6) {
                Button("Reset App Data…", role: .destructive) {
                    isPresentingResetConfirmation = true
                }
                Text("Clears every tracker, reading and source on all your devices. This can't be undone.")
                    .font(.wiggleText(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .confirmationDialog(
            "Reset All App Data?",
            isPresented: $isPresentingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                Task { await store.resetAllData() }
            }
        } message: {
            Text("Clears everything on every device signed in to this iCloud account. This can't be undone.")
        }
        .alert("Reset Failed", isPresented: resetErrorBinding) {
            Button("OK") { store.clearResetError() }
        } message: {
            Text(store.resetErrorDescription ?? "The app data could not be reset.")
        }
    }
    #else
    /// No `NavigationStack` of its own — pushed as a destination from
    /// `SettingsView`'s own stack, same as every other Settings sub-page.
    private var iosBody: some View {
        List {
            Section {
                Button("Reset App Data…", role: .destructive) {
                    isPresentingResetConfirmation = true
                }
            } footer: {
                Text("Clears every tracker, reading and source on all your devices. This can't be undone.")
            }
        }
        .navigationTitle("Danger Zone")
        .inlineNavigationBarIfAvailable()
        .confirmationDialog(
            "Reset All App Data?",
            isPresented: $isPresentingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Everything", role: .destructive) {
                Task {
                    if await store.resetAllData() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Clears everything on every device signed in to this iCloud account. This can't be undone.")
        }
        .alert("Reset Failed", isPresented: resetErrorBinding) {
            Button("OK") { store.clearResetError() }
        } message: {
            Text(store.resetErrorDescription ?? "The app data could not be reset.")
        }
    }
    #endif

    private var resetErrorBinding: Binding<Bool> {
        Binding(
            get: { store.resetErrorDescription != nil },
            set: { if !$0 { store.clearResetError() } }
        )
    }
}

#Preview {
    #if os(macOS)
    DangerZoneView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
        .frame(width: 640, height: 440)
    #else
    NavigationStack {
        DangerZoneView()
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
    #endif
}
