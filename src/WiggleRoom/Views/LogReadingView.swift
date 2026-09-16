//
//  LogReadingView.swift
//  WiggleRoom
//

import SwiftUI

/// "Update current value" (§5.5): the user enters a value and a timestamp
/// for a manual tracker. This is how `actualValue` (§4.2) gets set for any
/// manual tracker — there is no automatic refresh. Also doubles as the
/// **edit** screen for a previously-logged reading: pass `existingReading:`
/// and it prefills the form and mutates that reading in place on save,
/// with a Delete action alongside it.
struct LogReadingView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let tracker: Tracker
    var existingReading: ValueSnapshot?

    @State private var valueText = ""
    @State private var date = Date.now
    @State private var isPresentingDeleteConfirmation = false
    @FocusState private var isValueFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    valueInput
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 12)
                    DatePicker("Date", selection: $date)
                } footer: {
                    Text(footerHint)
                }

                if existingReading != nil {
                    Section {
                        Button("Delete Update", role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existingReading == nil ? "Update Current Value" : "Edit Update")
            .inlineNavigationBarIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Self.parseDecimal(valueText) == nil)
                }
            }
            .confirmationDialog(
                "Delete this update?",
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Update", role: .destructive) {
                    if let existingReading {
                        store.deleteReading(existingReading)
                    }
                    dismiss()
                }
            }
            .onAppear {
                guard let existingReading else { return }
                valueText = existingReading.value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
                date = existingReading.date
            }
            .task {
                isValueFieldFocused = true
            }
        }
    }

    /// A large, centered, easy-to-tap numeric field — this is the one thing
    /// almost every visit to this screen exists to fill in, so it gets more
    /// visual weight than a standard form row.
    private var valueInput: some View {
        HStack(spacing: 6) {
            if tracker.isCurrencyUnit {
                Text(tracker.unit)
                    .font(.wiggleNumber(size: 34))
                    .foregroundStyle(.secondary)
            }
            TextField("0", text: $valueText)
                .decimalKeyboardIfAvailable()
                .focused($isValueFieldFocused)
                .font(.wiggleNumber(size: 34))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: false)
            if !tracker.isCurrencyUnit {
                Text(tracker.unit)
                    .font(.wiggleNumber(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isValueFieldFocused = true }
    }

    private var footerHint: String {
        switch tracker.direction {
        case .decreasing:
            return "Enter your current remaining balance (e.g. 2400 if you've spent 600 of a 3000 budget)."
        case .increasing:
            return "Enter your current reading (e.g. today's odometer value)."
        }
    }

    /// See `AddTrackerView.parseDecimal` — plain `Decimal(string:)` silently
    /// truncates at a grouping separator ("2,800" → 2) instead of failing.
    private static func parseDecimal(_ text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let number = formatter.number(from: text) {
            return number.decimalValue
        }
        return Decimal(string: text)
    }

    private func save() {
        guard let value = Self.parseDecimal(valueText) else { return }
        if let existingReading {
            existingReading.value = value
            existingReading.date = date
            store.saveChanges()
        } else {
            store.logReading(value: value, date: date, for: tracker)
        }
        dismiss()
    }
}

#Preview {
    LogReadingView(tracker: PreviewData.makeSampleTracker())
        .environment(PreviewData.store)
}
