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

/// One other tracker's name and colour, as captured by
/// `AddTrackerView.loadOtherTrackers()` — a plain value, not a `Tracker`
/// reference, so the form never holds live SwiftData objects it doesn't
/// own and can't be invalidated by their changes mid-edit.
private struct TrackerSummary {
    let name: String
    let colorIndex: Int
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
    /// new one. Existing connections are fixed, while a read-only imported
    /// tracker with no source can be connected here.
    var existingTracker: Tracker?

    /// Called after the user confirms deleting `existingTracker`, right
    /// before this view dismisses itself — lets a presenting screen (e.g.
    /// `TrackerDetailView`) dismiss itself too, since the tracker it was
    /// showing no longer exists. `nil`/unused when creating a new tracker.
    var onDelete: (() -> Void)?

    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var addedSources: [ConnectedSource]

    @State private var name = ""
    /// What the tracker tracks. Chosen first, required, and locked once the
    /// tracker exists — it sets the units, the direction, which side of the
    /// pace line is good, all the wording, and which sources can back it.
    @State private var trackerType: TrackerType = .spendingMoney
    @State private var unit: TrackerUnit = TrackerType.spendingMoney.defaultUnit
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    /// Whether the period's start/end carry a specific time of day. Off by
    /// default — most trackers just care about the day — in which case
    /// `startDate`/`endDate` are normalized to midnight.
    @State private var includesTime = false
    @State private var startingValueText = ""
    /// The type's second figure as the user enters it — a movement for an
    /// allowance type ("a £500 budget"), an end value for a goal type
    /// ("£5,000", "85 kg"). `Tracker.totalAllowance` is derived from it on
    /// save; see `TrackerType.totalAllowance(startingValue:targetValue:)`.
    @State private var targetValueText = ""
    @State private var colorIndex = 0
    @State private var glyph = ""
    /// The other trackers' names and colours — a one-shot snapshot taken
    /// when this screen appears, deliberately **not** a live `@Query`.
    ///
    /// Both screens that present this one (`TrackerListView` on iOS,
    /// `MacRootView` on macOS) already query `Tracker`, and a presented
    /// view's content is rebuilt inside its presenter's body. A second
    /// live `@Query` over that same entity therefore loops: this query's
    /// fetch notifies SwiftData's change observers, invalidating the
    /// presenter's query, which rebuilds this view, which fetches again.
    /// See `AddSourceView.otherSourceNames` for the same defect confirmed
    /// as a watchdog kill on iOS. Both uses here — seeding an unused
    /// colour, and the duplicate-name warning — only need a snapshot;
    /// `save()` re-checks against a fresh fetch.
    @State private var otherTrackers: [TrackerSummary] = []

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
        case startingValue, targetValue
    }
    @FocusState private var focusedNumberField: NumberField?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if isDuplicateName {
                        Text("A tracker named \u{201C}\(name.trimmingCharacters(in: .whitespaces))\u{201D} already exists.")
                            .font(.wiggleText(.caption))
                            .foregroundStyle(WiggleRoomColors.error)
                    }
                    if existingTracker == nil {
                        Picker("Type", selection: $trackerType) {
                            ForEach(TrackerType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .onChange(of: trackerType) { _, newValue in
                            applyTypeDefaults(newValue)
                        }
                    } else {
                        LabeledContent("Type", value: trackerType.displayName)
                    }
                    unitPicker
                } header: {
                    Text("Details")
                        .font(WiggleRoomFont.headline(15, weight: 650))
                } footer: {
                    // Without an explicit full-width frame the stack takes its
                    // children's ideal width, which wraps the type summary
                    // halfway across the screen instead of at the margin.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trackerType.summary)
                        if let formFooter = trackerType.formFooter {
                            Text(formFooter)
                        }
                        if existingTracker != nil {
                            Text("A tracker's type is fixed once it's created.")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                TrackerAppearancePicker(
                    colorIndex: $colorIndex,
                    glyph: $glyph,
                    defaultGlyph: trackerType.defaultGlyph
                )

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
                        .font(WiggleRoomFont.headline(15, weight: 650))
                } footer: {
                    Text("Off by default, so the period runs midnight to midnight. Turn on to pick exact start and end times.")
                }

                Section {
                    LabeledContent(trackerType.startingValueLabel) {
                        unitValueField(text: $startingValueText, field: .startingValue)
                    }
                    if isPrefillingStartingValue {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("Fetching live balance…")
                        }
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(trackerType.startingValueHint)
                            .font(.wiggleText(.caption))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent(trackerType.targetValueLabel) {
                        unitValueField(text: $targetValueText, field: .targetValue)
                    }
                    Text(trackerType.targetValueHint)
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                    if let roundingHint = unit.roundingHint {
                        Text(roundingHint)
                            .font(.wiggleText(.caption))
                            .foregroundStyle(.secondary)
                    }
                    if hasBothValues && !isValuePairValid {
                        Text(trackerType.validationMessage)
                            .font(.wiggleText(.caption))
                            .foregroundStyle(WiggleRoomColors.error)
                    }

                    if let hourlyPaceDescription {
                        Text(hourlyPaceDescription)
                            .font(.wiggleText(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    if let dailyPaceDescription {
                        Text(dailyPaceDescription)
                            .font(.wiggleText(.footnote))
                            .foregroundStyle(.secondary)
                    }
                    if let remainingAtEndDescription {
                        Text(remainingAtEndDescription)
                            .font(.wiggleText(.footnote, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(trackerType.targetValueLabel)
                        .font(WiggleRoomFont.headline(15, weight: 650))
                }

                if existingTracker == nil || existingTracker?.connectedSource == nil {
                    Section {
                        Picker("Source", selection: $sourceSelection) {
                            Text("Manual Entry").tag(SourceOption.source(store.manualEntrySource.id) as SourceOption?)
                            ForEach(compatibleSources) { source in
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
                        Text("Only sources that can supply a \(trackerType.displayName.lowercased()) reading are listed. Manual Entry suits every type.")
                    }

                    if showsTargetPicker {
                        targetPickerSection
                    }
                } else {
                    Section {
                        LabeledContent("Source", value: existingTracker?.connectedSource?.displayName ?? "Not Connected")
                        if existingTracker?.isManualEntry == false {
                            if isResolvingAccountName {
                                LabeledContent(boundTargetLabel) {
                                    ProgressView()
                                }
                            } else {
                                LabeledContent(boundTargetLabel, value: resolvedAccountName ?? existingTracker?.sourceTargetId ?? "Unknown")
                            }
                        }
                    } footer: {
                        Text("A connected source and \(boundTargetLabel.lowercased()) are fixed once selected.")
                    }
                }

                if isManualEntrySelected {
                    Section {
                        Picker("Reminder", selection: $reminderCadenceMinutes) {
                            Text("None").tag(nil as Int?)
                            ForEach(trackerType.reminderPresets, id: \.minutes) { preset in
                                Text(preset.label).tag(preset.minutes as Int?)
                            }
                        }
                    } header: {
                        Text("Reminder")
                            .font(WiggleRoomFont.headline(15, weight: 650))
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
                // field — keeping this destructive action visually separate
                // reduces the risk of an accidental tap on iOS.
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
                        Text("Removes this tracker and its data.")
                    }
                    #if os(iOS)
                    .listSectionSpacing(.custom(48))
                    #endif
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingTracker == nil ? "New Tracker" : "Edit Tracker")
            .leadingSheetTitle(existingTracker == nil ? "New Tracker" : "Edit Tracker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid || isSaving)
                }
            }
            .task {
                loadOtherTrackers()
                if let existingTracker {
                    name = existingTracker.name
                    trackerType = existingTracker.trackerType
                    unit = existingTracker.trackerUnit
                    startDate = existingTracker.startDate
                    endDate = existingTracker.endDate
                    let calendar = Calendar.current
                    includesTime = !calendar.isDate(startDate, equalTo: calendar.startOfDay(for: startDate), toGranularity: .minute)
                        || !calendar.isDate(endDate, equalTo: calendar.startOfDay(for: endDate), toGranularity: .minute)
                    // No grouping separator here: it round-trips through
                    // `Decimal(string:)` on save, which doesn't understand
                    // "3,000" and would silently truncate it to "3".
                    startingValueText = Self.editableText(existingTracker.startingValue, unit: existingTracker.trackerUnit)
                    // The *stated* figure, not the stored one: a goal type is
                    // entered as an end value, so the form has to hand back
                    // the goal the user typed rather than the distance to it.
                    targetValueText = Self.editableText(existingTracker.wholePeriodValue, unit: existingTracker.trackerUnit)
                    sourceSelection = existingTracker.connectedSource.map { .source($0.id) }
                    reminderCadenceMinutes = existingTracker.reminderCadenceMinutes
                    colorIndex = existingTracker.resolvedColorIndex
                    glyph = existingTracker.glyph
                    await resolveAccountNameIfNeeded(for: existingTracker)
                } else if sourceSelection == nil {
                    // New trackers start on the first colour no other tracker
                    // is using, so a list fills with distinct colours.
                    let used = Set(otherTrackers.map(\.colorIndex))
                    colorIndex = TrackerPalette.all.indices.first { !used.contains($0) } ?? (otherTrackers.count % TrackerPalette.all.count)
                    sourceSelection = .source(store.manualEntrySource.id)
                    applyTypeDefaults(trackerType)
                }
            }
            .navigationDestination(isPresented: $isShowingAddSource) {
                AddSourcePickerView()
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
                Text("Removes this tracker and its data.")
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
                    Text("Loading \(selectedTargetLabel.lowercased())s…")
                        .foregroundStyle(.secondary)
                }
            } else if let targetLoadErrorMessage {
                Text(targetLoadErrorMessage)
                    .foregroundStyle(WiggleRoomColors.error)
            } else if availableTargets.isEmpty {
                Text("No \(selectedTargetLabel.lowercased())s found for this source.")
                    .foregroundStyle(.secondary)
            } else {
                Picker(selectedTargetLabel, selection: $selectedTargetId) {
                    Text("Choose one").tag(nil as String?)
                    ForEach(availableTargets) { target in
                        Text(target.displayName).tag(target.id as String?)
                    }
                }
            }
        } header: {
            Text(selectedTargetLabel)
                .font(WiggleRoomFont.headline(15, weight: 650))
        } footer: {
            Text("The \(selectedTargetLabel.lowercased()) this tracker reads from.")
        }
    }

    /// Whether there's a choice worth showing. A source offering exactly one
    /// target — Apple Health, whose only measurement is weight — has it
    /// selected automatically in `loadAvailableTargetsIfNeeded`, so a picker
    /// with a single row would be asking a question with one answer. The
    /// loading and failure states still show, since those say something.
    private var showsTargetPicker: Bool {
        guard selectedSourceId != nil, !isManualEntrySelected else { return false }
        if isLoadingTargets || targetLoadErrorMessage != nil { return true }
        return availableTargets.count != 1
    }

    /// The word this source's provider uses for one of its targets —
    /// "Account" for a bank, "Measurement" for Apple Health. Kept with the
    /// provider (`SourceProvider.targetLabel`) rather than hard-coded here,
    /// so a weight tracker never reports its "Account" as "Weight".
    private var selectedTargetLabel: String {
        guard let selectedSourceId, let source = resolveSource(withId: selectedSourceId) else { return "Account" }
        return store.provider(for: source)?.targetLabel ?? "Account"
    }

    /// The same word for a tracker that's already connected, where the
    /// source is fixed and read from the tracker itself.
    private var boundTargetLabel: String {
        guard let existingTracker, let source = existingTracker.connectedSource else { return "Account" }
        return store.provider(for: source)?.targetLabel ?? "Account"
    }

    private func loadAvailableTargetsIfNeeded() async {
        selectedTargetId = nil
        availableTargets = []
        targetLoadErrorMessage = nil
        // A connected existing tracker's source can't change. A read-only
        // imported tracker has no source and deliberately uses this same
        // picker to become connected.
        guard existingTracker?.connectedSource == nil, !isManualEntrySelected,
              let selectedSourceId, let source = resolveSource(withId: selectedSourceId)
        else {
            return
        }
        isLoadingTargets = true
        defer { isLoadingTargets = false }
        do {
            availableTargets = try await store.listAvailableTargets(for: source)
            // One target is no choice at all — pick it, so the section can
            // stay off screen entirely (see `showsTargetPicker`).
            if availableTargets.count == 1 {
                selectedTargetId = availableTargets.first?.id
            }
        } catch {
            targetLoadErrorMessage = "Couldn't load \(selectedTargetLabel.lowercased())s — try again."
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
        // `unit` matters for a provider whose value can be read in more than
        // one unit — Apple Health's body mass, in kilograms or pounds. See
        // `SourceTarget.unit`.
        let unitAwareTarget = SourceTarget(id: target.id, displayName: target.displayName, unit: unit.rawValue)
        guard let value = try? await store.fetchCurrentValue(for: unitAwareTarget, from: source) else { return }
        // The user may have typed their own starting value (e.g. backdating
        // the tracker's start to reflect a balance from earlier, not right
        // now) while this fetch was in flight — never stomp on that.
        guard startingValueText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        startingValueText = value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    /// The units the chosen type permits — never free text, so
    /// `Tracker.trackerUnit` and every piece of unit-aware
    /// formatting/precision can rely on an exact match. A single permitted
    /// unit needs no picker at all.
    @ViewBuilder
    private var unitPicker: some View {
        if trackerType.permittedUnits.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trackerType.permittedUnits) { option in
                        Button {
                            unit = option
                        } label: {
                            Text(option.symbol)
                                .font(.wiggleText(.subheadline, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(unit == option ? WiggleRoomColors.brand : Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(unit == option ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }

    /// Resets everything the type owns. Called when the type picker changes
    /// and once for a brand new tracker, so the unit, the badge glyph and
    /// the reminder always match the type rather than trailing the previous
    /// selection. A source that can't back the new type falls back to Manual
    /// Entry, which backs them all.
    private func applyTypeDefaults(_ type: TrackerType) {
        unit = type.defaultUnit
        reminderCadenceMinutes = type.defaultReminderCadenceMinutes
        if let selectedSourceId,
           selectedSourceId != store.manualEntrySource.id,
           !compatibleSources.contains(where: { $0.id == selectedSourceId }) {
            sourceSelection = .source(store.manualEntrySource.id)
        }
    }

    /// The added sources whose provider can actually supply a reading for
    /// the chosen type (§8) — declared by the provider, not hard-coded per
    /// type. Manual Entry is listed separately and always applies.
    private var compatibleSources: [ConnectedSource] {
        addedSources.filter { store.provider(for: $0)?.supportedTrackerTypes.contains(trackerType) ?? false }
    }

    /// A stored figure rendered back into the form's text field. No grouping
    /// separator: it round-trips through `parseDecimal` on save, and a
    /// locale that groups with "." would otherwise mangle it.
    private static func editableText(_ value: Decimal, unit: TrackerUnit) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...unit.precision)))
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
            if unit.placement == .prefix {
                Text(unit.symbol)
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
            if unit.placement == .suffix {
                Text(unit.symbol)
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
        if let existingTracker, existingTracker.connectedSource != nil {
            return existingTracker.isManualEntry
        }
        return selectedSourceId == store.manualEntrySource.id
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

    /// The two figures the form collects, parsed and rounded to what the
    /// unit can actually hold.
    private var parsedStartingValue: Decimal? {
        Self.parseDecimal(startingValueText).map { unit.rounded($0) }
    }

    private var parsedTargetValue: Decimal? {
        Self.parseDecimal(targetValueText).map { unit.rounded($0) }
    }

    private var hasBothValues: Bool {
        parsedStartingValue != nil && parsedTargetValue != nil
    }

    private var isValuePairValid: Bool {
        guard let startingValue = parsedStartingValue, let targetValue = parsedTargetValue else { return false }
        return trackerType.isValidPair(startingValue: startingValue, targetValue: targetValue)
    }

    /// The canonical figure that actually gets stored — see
    /// `TrackerType.totalAllowance(startingValue:targetValue:)`. For a goal
    /// type this is recomputed from whatever the starting value currently
    /// is, so editing the starting value later keeps the user's stated goal
    /// fixed rather than letting it drift (§6).
    private var derivedTotalAllowance: Decimal? {
        guard let startingValue = parsedStartingValue, let targetValue = parsedTargetValue else { return nil }
        return trackerType.totalAllowance(startingValue: startingValue, targetValue: targetValue)
    }

    private var hourlyPaceDescription: String? {
        guard let totalAllowance = derivedTotalAllowance, endDate > startDate else { return nil }
        let periodHours = endDate.timeIntervalSince(startDate) / 3600
        guard periodHours > 0 else { return nil }
        let hourlyRate = totalAllowance / Decimal(periodHours)
        return "≈ \(Self.paceRate(hourlyRate, unit: unit)) / hour"
    }

    /// Only worth showing alongside the hourly rate once a tracker runs
    /// longer than a day — for anything shorter, "per day" isn't a
    /// meaningful way to think about the pace.
    private var dailyPaceDescription: String? {
        guard let totalAllowance = derivedTotalAllowance, endDate > startDate else { return nil }
        let periodHours = endDate.timeIntervalSince(startDate) / 3600
        guard periodHours > 24 else { return nil }
        let dailyRate = totalAllowance / Decimal(periodHours / 24)
        return "≈ \(Self.paceRate(dailyRate, unit: unit)) / day"
    }

    /// A pace rate for the two "per hour"/"per day" lines. Always shows up to
    /// two decimal places whatever the unit's own precision — a rate of a
    /// third of a mile a day is worth seeing even though a reading isn't —
    /// and omits the unit entirely when it has no symbol, so a plain-number
    /// tracker reads "≈ 12 / day" rather than carrying a stray space.
    private static func paceRate(_ rate: Decimal, unit: TrackerUnit) -> String {
        let magnitude = rate.formatted(.number.precision(.fractionLength(0...2)))
        return unit.symbol.isEmpty ? magnitude : "\(magnitude) \(unit.symbol)"
    }

    /// See `Tracker.projectedRemainder` — how much would be left over at the
    /// end given the current form values, shown only when starting value and
    /// total budget actually differ.
    private var remainingAtEndDescription: String? {
        guard let startingValue = parsedStartingValue,
              let totalAllowance = derivedTotalAllowance,
              let remainder = Tracker.projectedRemainder(type: trackerType, startingValue: startingValue, totalAllowance: totalAllowance)
        else { return nil }
        if remainder > 0 {
            return "\(Tracker.formattedValue(remainder, unit: unit)) left at the end."
        } else {
            return "This \(trackerType.targetValueLabel.lowercased()) is \(Tracker.formattedValue(abs(remainder), unit: unit)) more than the starting value."
        }
    }

    /// Whether `name` (trimmed, case-insensitive) matches another tracker
    /// already in the list — excluding `existingTracker` itself, so editing
    /// a tracker without changing its name doesn't flag against itself.
    private var isDuplicateName: Bool {
        nameCollides(with: name.trimmingCharacters(in: .whitespaces))
    }

    private func nameCollides(with candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        return otherTrackers.contains { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }
    }

    /// Refreshes `otherTrackers`, excluding `existingTracker` itself so
    /// editing a tracker without renaming it doesn't flag against itself.
    private func loadOtherTrackers() {
        let trackers = (try? modelContext.fetch(FetchDescriptor<Tracker>())) ?? []
        let ownID = existingTracker?.id
        otherTrackers = trackers
            .filter { $0.id != ownID }
            .map { TrackerSummary(name: $0.name, colorIndex: $0.resolvedColorIndex) }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !isDuplicateName
            && endDate > startDate
            && isValuePairValid
            && selectedSourceId != nil
            // `selectedTargetId` is only ever populated by
            // `loadAvailableTargetsIfNeeded()`, which deliberately does
            // nothing when editing (`existingTracker != nil`) — the
            // target picker is replaced by a read-only row there, since a
            // tracker's source/account can't be changed after creation.
            // Requiring it unconditionally left Save permanently disabled
            // for every existing non-manual tracker.
            && (existingTracker?.connectedSource != nil || isManualEntrySelected || selectedTargetId != nil)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true

        // Re-checked against a fresh fetch rather than trusting the
        // snapshot behind the inline warning, which was taken on appear and
        // can't see a tracker added since (on this device or another).
        loadOtherTrackers()
        guard !isDuplicateName else {
            errorMessage = "A tracker with this name already exists."
            isSaving = false
            return
        }

        guard let startingValue = parsedStartingValue,
              let totalAllowance = derivedTotalAllowance,
              isValuePairValid
        else {
            errorMessage = trackerType.validationMessage
            isSaving = false
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // When no specific time was set, the period should run midnight to
        // midnight — not whatever time the form happened to be created at.
        if !includesTime {
            let calendar = Calendar.current
            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: endDate)
        }

        if let existingTracker {
            existingTracker.name = trimmedName
            existingTracker.trackerUnit = unit
            existingTracker.colorIndex = colorIndex
            existingTracker.glyph = glyph
            // `trackerType` is deliberately not written back: the type is
            // locked once a tracker exists, since changing it would
            // reinterpret every reading already logged.
            existingTracker.startDate = startDate
            existingTracker.endDate = endDate
            existingTracker.startingValue = startingValue
            existingTracker.totalAllowance = totalAllowance
            existingTracker.reminderCadenceMinutes = reminderCadenceMinutes
            var newlyConnectedToExternalSource = false
            if existingTracker.connectedSource == nil,
               let selectedSourceId,
               let source = resolveSource(withId: selectedSourceId) {
                existingTracker.connectedSource = source
                existingTracker.sourceTargetId = source.providerId == store.manualProvider.providerId
                    ? existingTracker.id.uuidString
                    : selectedTargetId
                newlyConnectedToExternalSource = source.providerId != store.manualProvider.providerId
            }
            store.saveChanges(reminderTracker: existingTracker)
            if newlyConnectedToExternalSource {
                let store = store
                Task { _ = try? await store.refreshFromSource(existingTracker, force: true) }
            }
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
                errorMessage = "Pick an account for this source."
                isSaving = false
                return
            }
            resolvedTargetId = selectedTargetId
        }

        let tracker = Tracker(
            id: trackerId,
            name: trimmedName,
            type: trackerType,
            unit: unit,
            connectedSource: source,
            sourceTargetId: resolvedTargetId,
            startDate: startDate,
            endDate: endDate,
            startingValue: startingValue,
            totalAllowance: totalAllowance,
            reminderCadenceMinutes: reminderCadenceMinutes
        )
        tracker.colorIndex = colorIndex
        tracker.glyph = glyph
        store.addTracker(tracker)
        // Seed the reading history with the starting value itself, dated at
        // the tracker's own start — otherwise a brand new tracker shows "No
        // readings logged yet" and a blank ring until the user manually logs
        // one, even though the starting value is already a real data point.
        store.logReading(value: startingValue, date: startDate, for: tracker)
        // A connected-source tracker always gets the live balance as its
        // second reading straight away (forced, even if it happens to equal
        // the starting value) so it never sits with only the seed entry.
        if !tracker.isManualEntry {
            let store = store
            Task { _ = try? await store.refreshFromSource(tracker, force: true) }
        }
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
