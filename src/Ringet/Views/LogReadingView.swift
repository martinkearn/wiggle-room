//
//  LogReadingView.swift
//  Ringet
//

import SwiftUI

/// "Update current value" (§5.5): the user enters a value and a timestamp
/// (defaulting to now) for a manual tracker. This is how `actualValue`
/// (§4.2) gets set for any manual tracker — there is no automatic refresh.
struct LogReadingView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let tracker: Tracker

    @State private var valueText = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(tracker.unit.isEmpty ? "Value" : tracker.unit) {
                        TextField("0", text: $valueText)
                            .decimalKeyboardIfAvailable()
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $date)
                } footer: {
                    Text(footerHint)
                }
            }
            .navigationTitle("Update Current Value")
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
        }
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
        store.logReading(value: value, date: date, for: tracker)
        dismiss()
    }
}

#Preview {
    LogReadingView(tracker: PreviewData.makeSampleTracker())
        .environment(PreviewData.store)
}
