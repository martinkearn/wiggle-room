//
//  AddTrackerView.swift
//  Ringet
//

import SwiftUI

/// Add/Edit tracker screen (§7.1).
///
/// The user picks a **Source** for the tracker: either "Manual Entry" (they
/// log readings themselves) or one of the real connections listed in
/// Settings → Connected Sources (§5.2) — Starling/Tesla aren't implemented
/// yet, so that list is currently always empty and Manual Entry is the only
/// option. Manual Entry is a fixed, single choice, not something the user
/// can add more of — each tracker that uses it simply gets its own
/// dedicated manual reading log behind the scenes (named after the tracker
/// itself), created automatically on save. No further picking is needed for
/// it. A real connected source with multiple targets (e.g. several Starling
/// accounts) will need a follow-up "which one" picker once such a provider
/// exists — out of scope while `addedSources` is always empty.
struct AddTrackerView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = ""
    @State private var direction: TrackerDirection = .decreasing
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var startingValueText = "0"
    @State private var totalAllowanceText = ""

    @State private var selectedSourceId: UUID?

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

                Section("Allowance") {
                    LabeledContent("Starting value") {
                        TextField("0", text: $startingValueText)
                            .decimalKeyboardIfAvailable()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Total allowance") {
                        TextField("0", text: $totalAllowanceText)
                            .decimalKeyboardIfAvailable()
                            .multilineTextAlignment(.trailing)
                    }
                    if let hourlyPaceDescription {
                        Text(hourlyPaceDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Source", selection: $selectedSourceId) {
                        Text("Manual Entry").tag(store.manualEntrySource.id as UUID?)
                        ForEach(store.addedSources) { source in
                            Text(source.displayName).tag(source.id as UUID?)
                        }
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
                if selectedSourceId == nil {
                    selectedSourceId = store.manualEntrySource.id
                }
            }
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
              let source = store.source(withId: selectedSourceId),
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

        Task {
            let target = await store.manualProvider.addTarget(displayName: trimmedName, to: source)

            let tracker = Tracker(
                name: trimmedName,
                unit: trimmedUnit,
                direction: direction,
                connectedSourceId: source.id,
                sourceTargetId: target.id,
                startDate: startDate,
                endDate: endDate,
                startingValue: startingValue,
                totalAllowance: totalAllowance
            )
            store.addTracker(tracker)
            dismiss()
        }
    }
}

#Preview {
    AddTrackerView()
        .environment(TrackerStore())
}

private extension View {
    /// `.keyboardType` is UIKit-only; this is a no-op on macOS.
    @ViewBuilder
    func decimalKeyboardIfAvailable() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
