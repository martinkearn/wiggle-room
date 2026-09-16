//
//  AddTrackerView.swift
//  WiggleRoom
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

    /// When set, the form edits this tracker in place instead of creating a
    /// new one. Its source can't be changed here — only the details,
    /// period, and budget.
    var existingTracker: Tracker?

    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    @State private var name = ""
    @State private var unit = ""
    @State private var direction: TrackerDirection = .decreasing
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    /// Whether the period's start/end carry a specific time of day. Off by
    /// default — most trackers just care about the day — in which case
    /// `startDate`/`endDate` are normalized to midnight.
    @State private var includesTime = false
    @State private var startingValueText = "0"
    @State private var totalAllowanceText = ""

    @State private var sourceSelection: SourceOption?
    @State private var isShowingAddSource = false

    /// §5.5 — a lightweight local-notification reminder to log a new
    /// reading, on a user-set cadence. `nil` means no reminder. Only offered
    /// for a manual-entry tracker (see `isManualEntrySelected`) — a real
    /// provider's readings arrive on their own.
    @State private var reminderCadenceDays: Int?

    @State private var errorMessage: String?

    private enum NumberField {
        case startingValue, totalAllowance
    }
    @FocusState private var focusedNumberField: NumberField?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    unitPicker
                    Picker("Direction", selection: $direction) {
                        Text("Decreasing").tag(TrackerDirection.decreasing)
                        Text("Increasing").tag(TrackerDirection.increasing)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Choose the unit this tracker is measured in.")
                }

                Section {
                    let components: DatePicker.Components = includesTime ? [.date, .hourAndMinute] : [.date]
                    DatePicker("Start", selection: $startDate, displayedComponents: components)
                    DatePicker("End", selection: $endDate, displayedComponents: components)
                    Toggle("Set specific times", isOn: $includesTime)
                        .onChange(of: includesTime) { _, newValue in
                            guard !newValue else { return }
                            let calendar = Calendar.current
                            startDate = calendar.startOfDay(for: startDate)
                            endDate = calendar.startOfDay(for: endDate)
                        }
                } header: {
                    Text("Period")
                } footer: {
                    Text("Off by default — the period runs from midnight to midnight. Turn this on to start or end at a specific time instead.")
                }

                Section {
                    LabeledContent("Starting value") {
                        unitValueField(text: $startingValueText, field: .startingValue)
                    }
                    Text(startingValueHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Total budget") {
                        unitValueField(text: $totalAllowanceText, field: .totalAllowance)
                    }
                    Text(totalBudgetHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let hourlyPaceDescription {
                        Text(hourlyPaceDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let dailyPaceDescription {
                        Text(dailyPaceDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let remainingAtEndDescription {
                        Text(remainingAtEndDescription)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text(budgetFooter)
                }

                if existingTracker == nil {
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
                } else {
                    Section {
                        LabeledContent("Source", value: existingTracker?.connectedSource?.displayName ?? "Manual Entry")
                    } footer: {
                        Text("A tracker's source can't be changed after it's created.")
                    }
                }

                if isManualEntrySelected {
                    Section {
                        Picker("Reminder", selection: $reminderCadenceDays) {
                            Text("None").tag(nil as Int?)
                            Text("Daily").tag(1 as Int?)
                            Text("Weekly").tag(7 as Int?)
                            Text("Every 2 Weeks").tag(14 as Int?)
                            Text("Monthly").tag(30 as Int?)
                        }
                    } header: {
                        Text("Reminder")
                    } footer: {
                        Text("Get a local notification reminding you to log a new reading on this cadence.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingTracker == nil ? "New Tracker" : "Edit Tracker")
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
                if let existingTracker {
                    name = existingTracker.name
                    unit = existingTracker.unit
                    direction = existingTracker.direction
                    startDate = existingTracker.startDate
                    endDate = existingTracker.endDate
                    let calendar = Calendar.current
                    includesTime = !calendar.isDate(startDate, equalTo: calendar.startOfDay(for: startDate), toGranularity: .minute)
                        || !calendar.isDate(endDate, equalTo: calendar.startOfDay(for: endDate), toGranularity: .minute)
                    // No grouping separator here: it round-trips through
                    // `Decimal(string:)` on save, which doesn't understand
                    // "3,000" and would silently truncate it to "3".
                    startingValueText = existingTracker.startingValue.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
                    totalAllowanceText = existingTracker.totalAllowance.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
                    sourceSelection = .source(existingTracker.connectedSource?.id ?? store.manualEntrySource.id)
                    reminderCadenceDays = existingTracker.reminderCadenceDays
                } else if sourceSelection == nil {
                    sourceSelection = .source(store.manualEntrySource.id)
                }
            }
            .navigationDestination(isPresented: $isShowingAddSource) {
                AddSourceView()
            }
        }
    }

    /// The only units a tracker can be created with — picking from a fixed
    /// set (rather than free text) means `Tracker.isCurrencyUnit` and every
    /// piece of currency-aware formatting/wording can rely on an exact
    /// match, with no risk of a typo'd or inconsistent unit string. Just the
    /// three most common currencies, plus a few other everyday
    /// depleting/accumulating allowances beyond money and mileage.
    private static let unitOptions = ["£", "$", "€", "mi", "km", "kg", "L", "hrs"]

    private var unitPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.unitOptions, id: \.self) { symbol in
                    Button {
                        unit = symbol
                    } label: {
                        Text(symbol)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(unit == symbol ? WiggleRoomColors.brand : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(unit == symbol ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    /// A budget number field with the chosen unit shown alongside it —
    /// prefixed with no space for a currency symbol ("£3000"), suffixed
    /// otherwise ("3000 mi"), matching `Tracker.formattedValue`'s styling
    /// elsewhere in the app. The whole row (not just the digits themselves)
    /// is tappable to focus the field — a value like "0" is otherwise a tiny
    /// target sitting flush against the row's trailing edge, with the
    /// `Spacer` next to it absorbing taps that land just to its left.
    private func unitValueField(text: Binding<String>, field: NumberField) -> some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if Tracker.isCurrencyUnit(unit) {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            TextField("0", text: text)
                .decimalKeyboardIfAvailable()
                .multilineTextAlignment(.trailing)
                .fixedSize()
                .focused($focusedNumberField, equals: field)
            if !unit.isEmpty && !Tracker.isCurrencyUnit(unit) {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture { focusedNumberField = field }
    }

    private var selectedSourceId: UUID? {
        guard case .source(let id) = sourceSelection else { return nil }
        return id
    }

    /// Whether the reminder section (§5.5) should be offered — either an
    /// existing manual tracker being edited, or Manual Entry currently
    /// selected while creating a new one.
    private var isManualEntrySelected: Bool {
        if let existingTracker {
            return existingTracker.isManualEntry
        }
        return selectedSourceId == store.manualEntrySource.id
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
        let displayUnit = unit.isEmpty ? "units" : unit
        switch direction {
        case .decreasing:
            if Tracker.isCurrencyUnit(unit) {
                return "Example: for a simple \(unit)3000 budget, set both starting value and total budget to 3000. You'll then log your remaining balance over time (e.g. 3000 → 0), not your bank account's own balance unless this tracker follows that account exactly."
            }
            return "Example: for a simple 3000 \(displayUnit) budget, set both starting value and total budget to 3000. You'll then log your remaining amount over time (e.g. 3000 → 0)."
        case .increasing:
            if Tracker.isCurrencyUnit(unit) {
                return "Example: for a \(unit)3000 allowance, set starting value to what you've already used and total budget to 3000. You'll then log your running total over time as it rises."
            }
            return "Example: for a 3000 \(displayUnit) allowance (e.g. a mileage lease), set starting value to your reading at the start and total budget to 3000. You'll then log your current reading over time as it rises."
        }
    }

    /// Parses a decimal typed or pasted by the user. Plain `Decimal(string:)`
    /// doesn't understand grouping separators ("3,000") and silently
    /// truncates at the comma instead of failing — this tries locale-aware
    /// parsing first (handles "3,000" and "3.000" correctly depending on
    /// locale) before falling back to the plain parse.
    private static func parseDecimal(_ text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let number = formatter.number(from: text) {
            return number.decimalValue
        }
        return Decimal(string: text)
    }

    private var hourlyPaceDescription: String? {
        guard let totalAllowance = Self.parseDecimal(totalAllowanceText), endDate > startDate else { return nil }
        let periodHours = endDate.timeIntervalSince(startDate) / 3600
        guard periodHours > 0 else { return nil }
        let hourlyRate = totalAllowance / Decimal(periodHours)
        let displayUnit = unit.isEmpty ? "units" : unit
        return "≈ \(hourlyRate.formatted(.number.precision(.fractionLength(0...2)))) \(displayUnit) / hour"
    }

    /// Only worth showing alongside the hourly rate once a tracker runs
    /// longer than a day — for anything shorter, "per day" isn't a
    /// meaningful way to think about the pace.
    private var dailyPaceDescription: String? {
        guard let totalAllowance = Self.parseDecimal(totalAllowanceText), endDate > startDate else { return nil }
        let periodHours = endDate.timeIntervalSince(startDate) / 3600
        guard periodHours > 24 else { return nil }
        let dailyRate = totalAllowance / Decimal(periodHours / 24)
        let displayUnit = unit.isEmpty ? "units" : unit
        return "≈ \(dailyRate.formatted(.number.precision(.fractionLength(0...2)))) \(displayUnit) / day"
    }

    /// See `Tracker.projectedRemainder` — how much would be left over at the
    /// end given the current form values, shown only when starting value and
    /// total budget actually differ.
    private var remainingAtEndDescription: String? {
        guard let startingValue = Self.parseDecimal(startingValueText),
              let totalAllowance = Self.parseDecimal(totalAllowanceText),
              let remainder = Tracker.projectedRemainder(direction: direction, startingValue: startingValue, totalAllowance: totalAllowance)
        else { return nil }
        let displayUnit = unit.isEmpty ? "units" : unit
        if remainder > 0 {
            return "\(Tracker.formattedValue(remainder, unit: displayUnit)) will remain at the end of the tracker."
        } else {
            return "This budget exceeds the starting value by \(Tracker.formattedValue(abs(remainder), unit: displayUnit))."
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !unit.trimmingCharacters(in: .whitespaces).isEmpty
            && endDate > startDate
            && Self.parseDecimal(startingValueText) != nil
            && Self.parseDecimal(totalAllowanceText) != nil
            && selectedSourceId != nil
    }

    private func save() {
        guard let startingValue = Self.parseDecimal(startingValueText),
              let totalAllowance = Self.parseDecimal(totalAllowanceText)
        else {
            errorMessage = "Please fill in all fields correctly."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)

        // When no specific time was set, the period should run midnight to
        // midnight — not whatever time the form happened to be created at.
        if !includesTime {
            let calendar = Calendar.current
            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: endDate)
        }

        if let existingTracker {
            existingTracker.name = trimmedName
            existingTracker.unit = trimmedUnit
            existingTracker.direction = direction
            existingTracker.startDate = startDate
            existingTracker.endDate = endDate
            existingTracker.startingValue = startingValue
            existingTracker.totalAllowance = totalAllowance
            existingTracker.reminderCadenceDays = reminderCadenceDays
            store.saveChanges(reminderTracker: existingTracker)
            dismiss()
            return
        }

        guard let selectedSourceId,
              let source = resolveSource(withId: selectedSourceId)
        else {
            errorMessage = "Please fill in all fields correctly."
            return
        }

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
            totalAllowance: totalAllowance,
            reminderCadenceDays: reminderCadenceDays
        )
        store.addTracker(tracker)
        // Seed the reading history with the starting value itself, dated at
        // the tracker's own start — otherwise a brand new tracker shows "No
        // readings logged yet" and a blank ring until the user manually logs
        // one, even though the starting value is already a real data point.
        store.logReading(value: startingValue, date: startDate, for: tracker)
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
