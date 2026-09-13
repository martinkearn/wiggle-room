//
//  AddTrackerView.swift
//  Ringet
//

import SwiftUI

/// Add/Edit tracker screen (§7.1), scoped for now to manual-entry sources —
/// Starling and Tesla providers aren't implemented yet.
///
/// Manual entry needs no auth/setup step (`requiresConnection == false`,
/// §5.1), so there's no *connection*-picking step here — the tracker is
/// created against `TrackerStore.defaultManualSource` automatically. What
/// the user does pick is the specific data source (a `SourceTarget`) within
/// it, since that's what actually varies (e.g. "Car A mileage" vs. "Car B
/// mileage" reported by the same manual connection). Creating a new one is
/// a secondary action (a "+" that presents an alert, the same pattern as
/// "New Folder" elsewhere in iOS) rather than a picker entry, so the
/// primary flow — adding a tracker — stays uncluttered. A step for picking
/// between multiple *connections* returns once Starling/Tesla exist, since
/// those require an actual account connection a user might have more than
/// one of; that too belongs behind a secondary "manage sources" entry point
/// (§5.2's Settings → Connected Sources), not inline here.
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

    @State private var availableTargets: [SourceTarget] = []
    @State private var targetId: String?

    @State private var isPresentingNewSourceAlert = false
    @State private var newSourceName = ""

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
                    if availableTargets.isEmpty {
                        ProgressView()
                    } else {
                        Picker("Source", selection: $targetId) {
                            ForEach(availableTargets) { target in
                                Text(target.displayName).tag(target.id as String?)
                            }
                        }
                    }
                    Button {
                        newSourceName = ""
                        isPresentingNewSourceAlert = true
                    } label: {
                        Label("New Source…", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Data Source")
                } footer: {
                    Text("Trackers pointed at the same source share its readings, so add a new source to track something separately, like a second car's mileage.")
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
                loadTargets()
            }
            .alert("New Source", isPresented: $isPresentingNewSourceAlert) {
                TextField("Source name", text: $newSourceName)
                Button("Cancel", role: .cancel) {}
                Button("Add") { createTarget() }
                    .disabled(newSourceName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Give this source a name, e.g. \"Car A mileage\".")
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
            && targetId != nil
    }

    private func loadTargets() {
        Task {
            let source = store.defaultManualSource
            let targets = (try? await store.manualProvider.listAvailableTargets(for: source)) ?? []
            availableTargets = targets
            targetId = targets.first?.id
        }
    }

    private func createTarget() {
        let trimmed = newSourceName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            let target = await store.manualProvider.addTarget(displayName: trimmed, to: store.defaultManualSource)
            availableTargets.append(target)
            targetId = target.id
        }
    }

    private func save() {
        guard let targetId,
              let startingValue = Decimal(string: startingValueText),
              let totalAllowance = Decimal(string: totalAllowanceText)
        else {
            errorMessage = "Please fill in all fields correctly."
            return
        }

        let tracker = Tracker(
            name: name.trimmingCharacters(in: .whitespaces),
            unit: unit.trimmingCharacters(in: .whitespaces),
            direction: direction,
            connectedSourceId: store.defaultManualSource.id,
            sourceTargetId: targetId,
            startDate: startDate,
            endDate: endDate,
            startingValue: startingValue,
            totalAllowance: totalAllowance
        )
        store.addTracker(tracker)
        dismiss()
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
