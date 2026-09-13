//
//  AddTrackerView.swift
//  Ringet
//

import SwiftUI
import SwiftData

private enum SourceOption: Hashable {
    case source(UUID)
    case addNew
}

/// Add/Edit tracker screen (§7.1).
///
/// The user picks a **Source** for the tracker: either "Manual Entry" (they
/// log readings themselves), one of the real connections listed in
/// Settings → Connected Sources (§5.2), or "Add New Source…", a shortcut
/// into the same add-a-source flow Settings uses (`AddSourceView`) — handy
/// mid-way through creating a tracker rather than backing out to Settings
/// first. Starling/Tesla aren't implemented yet, so the added-sources list
/// is currently always empty and Manual Entry is the only real option.
///
/// Manual Entry is a fixed, single choice, not something the user can add
/// more of — each tracker that uses it simply gets its own dedicated manual
/// reading log (its `sourceTargetId` is just its own id), created
/// automatically on save. No further picking is needed for it. A real
/// connected source with multiple targets (e.g. several Starling accounts)
/// will need a follow-up "which one" picker once such a provider exists.
struct AddTrackerView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    @State private var name = ""
    @State private var unit = ""
    @State private var direction: TrackerDirection = .decreasing
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var startingValueText = "0"
    @State private var totalAllowanceText = ""

    @State private var sourceSelection: SourceOption?
    @State private var isShowingAddSource = false

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Unit (e.g. £, mi)", text: $unit)
                    Picker("Direction", selection: $direction) {
                        Text("Decreasing").tag(TrackerDirection.decreasing)
                        Text("Increasing").tag(TrackerDirection.increasing)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Period") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                }

                Section {
                    LabeledContent("Starting value") {
                        TextField("0", text: $startingValueText)
                            .decimalKeyboardIfAvailable()
                            .multilineTextAlignment(.trailing)
                    }
                    Text(startingValueHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Total budget") {
                        TextField("0", text: $totalAllowanceText)
                            .decimalKeyboardIfAvailable()
                            .multilineTextAlignment(.trailing)
                    }
                    Text(totalBudgetHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let hourlyPaceDescription {
                        Text(hourlyPaceDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text(budgetFooter)
                }

                Section {
                    Picker("Source", selection: $sourceSelection) {
                        Text("Manual Entry").tag(SourceOption.source(store.manualEntrySource.id) as SourceOption?)
                        ForEach(addedSources) { source in
                            Text(source.displayName).tag(SourceOption.source(source.id) as SourceOption?)
                        }
                        Text("Add New Source…").tag(SourceOption.addNew as SourceOption?)
                    }
                    .onChange(of: sourceSelection) { oldValue, newValue in
                        guard newValue == .addNew else { return }
                        isShowingAddSource = true
                        // "Add New Source…" is a shortcut action, not a real
                        // selection — restore whatever was chosen before.
                        sourceSelection = oldValue
                    }
                } footer: {
                    Text("Manual Entry means you'll log this tracker's readings yourself. Otherwise, pick a source you've added in Settings → Connected Sources.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Tracker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .task {
                if sourceSelection == nil {
                    sourceSelection = .source(store.manualEntrySource.id)
                }
            }
            .navigationDestination(isPresented: $isShowingAddSource) {
                AddSourceView()
            }
        }
    }

    private var selectedSourceId: UUID? {
        guard case .source(let id) = sourceSelection else { return nil }
        return id
    }

    private var startingValueHint: String {
        switch direction {
        case .decreasing:
            return "How much you're starting with, e.g. 3000 for a £3000 budget."
        case .increasing:
            return "Your reading at the start, e.g. 0 miles, or today's odometer reading."
        }
    }

    private var totalBudgetHint: String {
        switch direction {
        case .decreasing:
            return "The total amount allowed for the whole period — usually the same as starting value."
        case .increasing:
            return "How much more you're allowed to add over the whole period."
        }
    }

    private var budgetFooter: String {
        switch direction {
        case .decreasing:
            return "Example: for a simple £3000 budget, set both starting value and total budget to 3000. You'll then log your remaining balance over time (e.g. 3000 → 0), not your bank account's own balance unless this tracker follows that account exactly."
        case .increasing:
            return "Example: for a 3000-mile lease allowance, set starting value to your odometer reading and total budget to 3000. You'll then log your current odometer reading over time as it rises."
        }
    }

    private var hourlyPaceDescription: String? {
        guard let totalAllowance = Decimal(string: totalAllowanceText), endDate > startDate else { return nil }
        let periodHours = endDate.timeIntervalSince(startDate) / 3600
        guard periodHours > 0 else { return nil }
        let hourlyRate = totalAllowance / Decimal(periodHours)
        let displayUnit = unit.isEmpty ? "units" : unit
        return "≈ \(hourlyRate.formatted(.number.precision(.fractionLength(0...2)))) \(displayUnit) / hour"
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !unit.trimmingCharacters(in: .whitespaces).isEmpty
            && endDate > startDate
            && Decimal(string: startingValueText) != nil
            && Decimal(string: totalAllowanceText) != nil
            && selectedSourceId != nil
    }

    private func save() {
        guard let selectedSourceId,
              let source = resolveSource(withId: selectedSourceId),
              let startingValue = Decimal(string: startingValueText),
              let totalAllowance = Decimal(string: totalAllowanceText)
        else {
            errorMessage = "Please fill in all fields correctly."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)

        guard source.providerId == store.manualProvider.providerId else {
            // No auto-fetch providers exist yet (§9); unreachable until
            // Starling/Tesla land, since `addedSources` is always empty.
            errorMessage = "This source isn't supported yet."
            return
        }

        let trackerId = UUID()
        let tracker = Tracker(
            id: trackerId,
            name: trimmedName,
            unit: trimmedUnit,
            direction: direction,
            connectedSource: source,
            sourceTargetId: trackerId.uuidString,
            startDate: startDate,
            endDate: endDate,
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
        store.addTracker(tracker)
        dismiss()
    }

    private func resolveSource(withId id: UUID) -> ConnectedSource? {
        if id == store.manualEntrySource.id { return store.manualEntrySource }
        return addedSources.first { $0.id == id }
    }
}

#Preview {
    AddTrackerView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
