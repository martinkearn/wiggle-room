//
//  AddHealthSourceView.swift
//  WiggleRoom
//

#if os(iOS)
import SwiftUI
import SwiftData

/// Add Source → Apple Health, and the editor for one that already exists.
/// iOS/iPadOS only: HealthKit doesn't exist on macOS, and authorisation only
/// exists on the device that grants it, so a Mac can't create this source at
/// all (see `AddSourcePickerView`).
///
/// There is no credential to type. Connecting is an authorisation request,
/// and the screen is careful about what it claims afterwards: HealthKit
/// deliberately never reports read permission back to an app, so a refusal
/// looks exactly like an empty Health store. Nothing here says "Connected"
/// on the strength of the prompt having been answered — it says the source
/// is set up, reports whether a weight could actually be read just now, and
/// points at Health's own permission screen when one couldn't.
///
/// **Observes nothing from SwiftData in `body`.** It's pushed from
/// `ConnectedSourcesView`, which holds a live `@Query`, and reading the store
/// from this screen's `body` — a query, a relationship traversal, or a model
/// property — puts the two views in an update loop that runs until iOS kills
/// the app on the watchdog. Name is seeded in `init`, tracker names are read
/// once in `.task`, and the duplicate-name check is a one-shot fetch at save
/// time. See `docs/swiftdata-update-loops.md` and `AddSourceView`, which
/// carries the same constraint for the same reason.
struct AddHealthSourceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, this view renames an existing Health source in place
    /// instead of creating one. Read in `init` and in `save()`, never in
    /// `body`.
    var existingSource: ConnectedSource?

    @State private var displayName: String
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var accessMessage: String?
    /// Names of the trackers pointed at this source, captured once in
    /// `.task` — a plain `[String]`, so this screen holds no `Tracker`
    /// references and never faults the relationship from `body`.
    @State private var trackerNames: [String] = []

    private let isEditing: Bool
    /// Captured in `init`: whether this device has a Health store at all.
    /// Can't change while the screen is open.
    private let isHealthDataAvailable: Bool

    init(existingSource: ConnectedSource? = nil) {
        self.existingSource = existingSource
        self.isEditing = existingSource != nil
        self.isHealthDataAvailable = HealthKitProvider().isAvailableOnThisDevice
        _displayName = State(initialValue: existingSource?.displayName ?? "Apple Health")
    }

    var body: some View {
        Group {
            if isHealthDataAvailable {
                form
            } else {
                WiggleEmptyState(
                    symbol: "heart.slash",
                    title: "Health Isn't Available",
                    message: "This device has no Health data, so Apple Health can't be used as a source here."
                )
            }
        }
        .navigationTitle(isEditing ? "Apple Health" : "Add Apple Health")
        .inlineNavigationBarIfAvailable()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(isEditing ? "Save" : "Connect")
                    }
                }
                .disabled(isWorking || !isHealthDataAvailable)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
            } header: {
                Text("Details")
                    .font(WiggleRoomFont.headline(15, weight: 650))
            } footer: {
                Text("Wiggle Room reads the latest weight recorded in Health, and nothing else. It never writes to Health, and a weight you add by hand here stays in Wiggle Room.")
            }

            if isEditing {
                Section {
                    Button {
                        Task { await checkAccess() }
                    } label: {
                        Label("Check Health Access", systemImage: "arrow.clockwise.heart")
                    }
                    .disabled(isWorking)
                } footer: {
                    Text(accessMessage ?? "Access is managed in Health \u{2192} your profile \u{2192} Apps and Services \u{2192} Wiggle Room. Health never tells an app whether access was granted, so checking is the only way to see whether a weight can be read.")
                }
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
        }
        .formStyle(.grouped)
        .task {
            trackerNames = namesOfTrackersUsingThisSource()
        }
    }

    /// The trackers pointed at this source, captured as plain names when the
    /// screen appears — traversing the relationship from `body` would fault
    /// it in on the main context, which is structurally the same act as a
    /// live `@Query`. Sorted for a stable order; the relationship's own order
    /// is arbitrary.
    private func namesOfTrackersUsingThisSource() -> [String] {
        (existingSource?.trackers ?? [])
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Asks Health for access and saves the source. Saving does **not**
    /// depend on the answer, because there is no answer to depend on: the
    /// prompt returning without throwing means Health has taken the
    /// decision, not that it went one way. A source with no readable weight
    /// behind it is harmless — its trackers simply stay on whatever readings
    /// they already have.
    private func save() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Apple Health" : trimmedName

        guard !nameIsTaken(resolvedName) else {
            errorMessage = "A source named \u{201C}\(resolvedName)\u{201D} already exists."
            return
        }

        if let existingSource {
            existingSource.displayName = resolvedName
            try? modelContext.save()
            dismiss()
            return
        }

        // A second Health source would mean nothing — it is the same Health
        // store either way. Re-checked here as well as in the picker, since
        // one could have arrived by CloudKit sync while this screen was open.
        guard !healthSourceExists() else {
            errorMessage = "Apple Health is already connected."
            return
        }

        let provider = HealthKitProvider()
        do {
            try await provider.requestAuthorization()
        } catch {
            errorMessage = "Couldn't ask Health for access. Check Health is set up on this device and try again."
            return
        }

        // No credential: `credentialToken` stays nil for a Health source and
        // is never read. Authorisation lives in the system's own Health
        // permissions, per device, and isn't the app's to store or sync.
        modelContext.insert(ConnectedSource(providerId: "healthkit", displayName: resolvedName))
        try? modelContext.save()
        dismiss()
    }

    /// Reads the latest weight and reports whether one came back. The honest
    /// version of a connection test: "no weight" covers both an empty Health
    /// store and refused access, and says so rather than guessing.
    private func checkAccess() async {
        accessMessage = nil
        isWorking = true
        defer { isWorking = false }

        let provider = HealthKitProvider()
        do {
            _ = try await provider.fetchCurrentReading(target: HealthKitProvider.weightTarget)
            accessMessage = "Health returned a weight reading."
        } catch HealthKitProviderError.noReadings {
            accessMessage = "No weight came back. Either Health holds no weight yet, or Wiggle Room hasn't been allowed to read it \u{2014} check Health \u{2192} your profile \u{2192} Apps and Services \u{2192} Wiggle Room."
        } catch {
            accessMessage = "Couldn't read from Health on this device."
        }
    }

    /// Whether another connected source already uses `name`, ignoring case
    /// and excluding this screen's own source. A one-shot fetch at save time
    /// rather than a live `@Query` — see the type note above.
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

    private func healthSourceExists() -> Bool {
        let descriptor = FetchDescriptor<ConnectedSource>(
            predicate: #Predicate { $0.providerId == "healthkit" }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }
}

#Preview {
    NavigationStack {
        AddHealthSourceView()
    }
    .modelContainer(PreviewData.container)
}
#endif
