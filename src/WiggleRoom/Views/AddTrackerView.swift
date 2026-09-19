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
/// first. Only Starling is implemented as a real provider so far (§5.3);
/// Tesla (§5.4) isn't built yet.
///
/// Manual Entry is a fixed, single choice, not something the user can add
/// more of — each tracker that uses it simply gets its own dedicated manual
/// reading log (its `sourceTargetId` is just its own id), created
/// automatically on save. No further picking is needed for it. A real
/// connected source with multiple targets (e.g. several Starling accounts)
/// gets a follow-up "which account" picker instead — see
/// `targetPickerSection`.
struct AddTrackerView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, the form edits this tracker in place instead of creating a
    /// new one. Its source can't be changed here — only the details,
    /// period, and budget.
    var existingTracker: Tracker?

    /// Called after the user confirms deleting `existingTracker`, right
    /// before this view dismisses itself — lets a presenting screen (e.g.
    /// `TrackerDetailView`) dismiss itself too, since the tracker it was
    /// showing no longer exists. `nil`/unused when creating a new tracker.
    var onDelete: (() -> Void)?

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
    @State private var startingValueText = ""
    @State private var totalAllowanceText = ""

    @State private var sourceSelection: SourceOption?
    @State private var isShowingAddSource = false

    /// The picked-target step (§5.2) for a real, non-manual source — e.g.
    /// which Starling account this tracker should read from. Manual Entry
    /// needs none of this (each manual tracker gets its own dedicated log,
    /// per the type doc comment above).
    @State private var availableTargets: [SourceTarget] = []
    @State private var selectedTargetId: String?
    @State private var isLoadingTargets = false
    @State private var targetLoadErrorMessage: String?
    @State private var isPrefillingStartingValue = false

    /// The bound account's display name, resolved read-only when editing an
    /// existing tracker on a real (non-manual) source — `Tracker` only
    /// stores `sourceTargetId` (a bare id like a Starling `accountUid`), not
    /// a human-readable label, so this is fetched live the same way the
    /// target picker fetches its list. `nil` while loading or for a manual
    /// tracker (which has nothing to resolve).
    @State private var resolvedAccountName: String?
    @State private var isResolvingAccountName = false

    /// §5.5 — a lightweight local-notification reminder to log a new
    /// reading, on a user-set cadence in minutes. `nil` means no reminder.
    /// Only offered for a manual-entry tracker (see `isManualEntrySelected`)
    /// — a real provider's readings arrive on their own.
    @State private var reminderCadenceMinutes: Int?

    @State private var errorMessage: String?

    /// Guards `save()` against a double-tap/double-click on the Save
    /// button inserting two trackers — `save()` itself has no async gap for
    /// SwiftUI's own touch-debouncing to help with, so without this a fast
    /// second tap before the sheet dismisses could fire `save()` twice.
    @State private var isSaving = false
    @State private var isPresentingDeleteConfirmation = false

    private enum NumberField {
        case startingValue, totalAllowance
    }
    @FocusState private var focusedNumberField: NumberField?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        #if os(macOS)
                        .autocorrectionDisabled()
                        #endif
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
                        .datePickerStyle(.compact)
                    DatePicker("End", selection: $endDate, displayedComponents: components)
                        .datePickerStyle(.compact)
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
                    if isPrefillingStartingValue {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Fetching live balance…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(startingValueHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

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

                    if !isManualEntrySelected {
                        targetPickerSection
                    }
                } else {
                    Section {
                        LabeledContent("Source", value: existingTracker?.connectedSource?.displayName ?? "Manual Entry")
                        if existingTracker?.isManualEntry == false {
                            if isResolvingAccountName {
                                LabeledContent("Account") {
                                    ProgressView()
                                }
                            } else {
                                LabeledContent("Account", value: resolvedAccountName ?? existingTracker?.sourceTargetId ?? "Unknown")
                            }
                        }
                    } footer: {
                        Text("A tracker's source and account can't be changed after it's created.")
                    }
                }

                if isManualEntrySelected {
                    Section {
                        Picker("Reminder", selection: $reminderCadenceMinutes) {
                            Text("None").tag(nil as Int?)
                            Text("Every Minute").tag(1 as Int?)
                            Text("Hourly").tag(60 as Int?)
                            Text("Daily").tag(1440 as Int?)
                            Text("Weekly").tag(10080 as Int?)
                            Text("Every 2 Weeks").tag(20160 as Int?)
                            Text("Monthly").tag(43200 as Int?)
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

                // Deliberately the last thing on the screen, with extra
                // space above it (`.listSectionSpacing`, iOS/iPadOS only —
                // unavailable on macOS) so it reads as its own separate zone
                // rather than sitting shoulder-to-shoulder with an ordinary
                // field — this used to be a "…" menu item right next to Edit
                // Tracker with no gap at all, an easy mis-tap on iOS. See
                // progress-notes.md's 2026-09-18 entry.
                if existingTracker != nil {
                    Section {
                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Tracker")
                                Spacer()
                            }
                        }
                    } footer: {
                        Text("This removes the tracker and all its logged readings. This can't be undone.")
                    }
                    #if os(iOS)
                    .listSectionSpacing(.custom(48))
                    #endif
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingTracker == nil ? "New Tracker" : "Edit Tracker")
            .toolbar {
                ToolbarItem(placement: .sheetCancel) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .sheetConfirm) {
                    Button("Save") { save() }
                        .disabled(!isValid || isSaving)
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
                    reminderCadenceMinutes = existingTracker.reminderCadenceMinutes
                    await resolveAccountNameIfNeeded(for: existingTracker)
                } else if sourceSelection == nil {
                    sourceSelection = .source(store.manualEntrySource.id)
                }
            }
            .navigationDestination(isPresented: $isShowingAddSource) {
                AddSourceView()
            }
            .task(id: selectedSourceId) {
                await loadAvailableTargetsIfNeeded()
            }
            .task(id: selectedTargetId) {
                await prefillStartingValueIfNeeded()
            }
            .confirmationDialog(
                "Delete \u{201C}\(existingTracker?.name ?? "")\u{201D}?",
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Tracker", role: .destructive) {
                    if let existingTracker {
                        store.deleteTracker(existingTracker)
                    }
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("This removes the tracker and all its logged readings. This can't be undone.")
            }
        }
    }

    /// Which account/target within the selected real source this tracker
    /// should read from — e.g. one of the user's Starling accounts. Fetched
    /// live (not cached) whenever the selected source changes, since it's a
    /// real network call.
    private var targetPickerSection: some View {
        Section {
            if isLoadingTargets {
                HStack {
                    ProgressView()
                    Text("Loading accounts…")
                        .foregroundStyle(.secondary)
                }
            } else if let targetLoadErrorMessage {
                Text(targetLoadErrorMessage)
                    .foregroundStyle(WiggleRoomColors.error)
            } else if availableTargets.isEmpty {
                Text("No accounts found for this source.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Account", selection: $selectedTargetId) {
                    Text("Choose one").tag(nil as String?)
                    ForEach(availableTargets) { target in
                        Text(target.displayName).tag(target.id as String?)
                    }
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Which account within this source this tracker reads its balance from.")
        }
    }

    private func loadAvailableTargetsIfNeeded() async {
        selectedTargetId = nil
        availableTargets = []
        targetLoadErrorMessage = nil
        // Editing an existing tracker never shows `targetPickerSection` (its
        // source can't change) — skip the network call entirely rather than
        // spending a Starling request on nothing.
        guard existingTracker == nil, !isManualEntrySelected,
              let selectedSourceId, let source = resolveSource(withId: selectedSourceId)
        else {
            return
        }
        isLoadingTargets = true
        defer { isLoadingTargets = false }
        do {
            availableTargets = try await store.listAvailableTargets(for: source)
        } catch {
            targetLoadErrorMessage = "Couldn't load accounts for this source — try again."
        }
    }

    /// Read-only resolution of a bound account's display name when editing
    /// an existing tracker on a real (non-manual) source — `Tracker` only
    /// stores `sourceTargetId` (a bare id like a Starling `accountUid`), not
    /// a human-readable label, so this fetches the source's current
    /// account list (same call the target picker makes for a new tracker)
    /// and finds the matching one. Never lets the user change anything —
    /// this only fills in the "Account" row for display. Falls back to the
    /// raw id if the fetch fails or the account is no longer listed (e.g.
    /// renamed/closed at Starling) rather than leaving the row blank.
    private func resolveAccountNameIfNeeded(for tracker: Tracker) async {
        guard !tracker.isManualEntry,
              let source = tracker.connectedSource,
              let targetId = tracker.sourceTargetId
        else { return }
        isResolvingAccountName = true
        defer { isResolvingAccountName = false }
        guard let targets = try? await store.listAvailableTargets(for: source) else { return }
        resolvedAccountName = targets.first(where: { $0.id == targetId })?.displayName
    }

    /// Prefills "Starting value" with the picked account's live balance
    /// rather than leaving the user to guess/type today's real number —
    /// only for a fresh tracker on a real (non-manual) source; skipped
    /// entirely for manual entry (nothing to fetch) and when editing an
    /// existing tracker (its source/target can't change). **Never
    /// overwrites a value the user has already typed** — e.g. backdating a
    /// tracker's start time to reflect a balance from earlier rather than
    /// right now is a real, intentional use case, and silently replacing
    /// that with "whatever the balance is at this exact second" would be
    /// actively wrong, not just unhelpful. Silent on failure — the user can
    /// still type a starting value by hand if the fetch fails.
    private func prefillStartingValueIfNeeded() async {
        guard existingTracker == nil, !isManualEntrySelected,
              let selectedTargetId,
              let selectedSourceId, let source = resolveSource(withId: selectedSourceId),
              let target = availableTargets.first(where: { $0.id == selectedTargetId }),
              startingValueText.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        isPrefillingStartingValue = true
        defer { isPrefillingStartingValue = false }
        guard let value = try? await store.fetchCurrentValue(for: target, from: source) else { return }
        // The user may have typed their own starting value (e.g. backdating
        // the tracker's start to reflect a balance from earlier, not right
        // now) while this fetch was in flight — never stomp on that.
        guard startingValueText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        startingValueText = value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
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
            // Manual placeholder, not `TextField`'s own — same fix as
            // `LogReadingView.valueInput` (2026-09-18): `.fixedSize()`
            // sizes to the bound string, not the placeholder, and on
            // macOS a real `TextField` placeholder has also been seen
            // rendering alongside genuinely-typed content at once. A
            // `Text("0")` shown only while `text` is empty sidesteps both.
            ZStack(alignment: .trailing) {
                if text.wrappedValue.isEmpty {
                    Text("0")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: text)
                    .decimalKeyboardIfAvailable()
                    .multilineTextAlignment(.trailing)
                    .focused($focusedNumberField, equals: field)
            }
            .frame(minWidth: 60, maxWidth: 120)
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
            return "\(Tracker.formattedValue(remainder, unit: displayUnit)) should remain at the end of the tracker."
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
            // `selectedTargetId` is only ever populated by
            // `loadAvailableTargetsIfNeeded()`, which deliberately does
            // nothing when editing (`existingTracker != nil`) — the
            // target picker is replaced by a read-only row there, since a
            // tracker's source/account can't be changed after creation.
            // Requiring it unconditionally left Save permanently disabled
            // for every existing non-manual tracker.
            && (existingTracker != nil || isManualEntrySelected || selectedTargetId != nil)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true

        guard let startingValue = Self.parseDecimal(startingValueText),
              let totalAllowance = Self.parseDecimal(totalAllowanceText)
        else {
            errorMessage = "Please fill in all fields correctly."
            isSaving = false
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
            existingTracker.reminderCadenceMinutes = reminderCadenceMinutes
            store.saveChanges(reminderTracker: existingTracker)
            dismiss()
            return
        }

        guard let selectedSourceId,
              let source = resolveSource(withId: selectedSourceId)
        else {
            errorMessage = "Please fill in all fields correctly."
            isSaving = false
            return
        }

        // A manual tracker owns its own dedicated log (its id doubles as its
        // `sourceTargetId`); a real source's tracker points at whichever
        // account the user picked in `targetPickerSection`.
        let trackerId = UUID()
        let resolvedTargetId: String
        if source.providerId == store.manualProvider.providerId {
            resolvedTargetId = trackerId.uuidString
        } else {
            guard let selectedTargetId else {
                errorMessage = "Please choose an account for this source."
                isSaving = false
                return
            }
            resolvedTargetId = selectedTargetId
        }

        let tracker = Tracker(
            id: trackerId,
            name: trimmedName,
            unit: trimmedUnit,
            direction: direction,
            connectedSource: source,
            sourceTargetId: resolvedTargetId,
            startDate: startDate,
            endDate: endDate,
            startingValue: startingValue,
            totalAllowance: totalAllowance,
            reminderCadenceMinutes: reminderCadenceMinutes
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
