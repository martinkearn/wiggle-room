//
//  WatchLogReadingView.swift
//  WiggleRoomWatch
//

import SwiftUI

/// Minimal on-wrist version of the phone's "Update Current Value" screen —
/// just enough to log a value without reaching for the phone. Editing/
/// deleting past readings (supported on iOS) stays a phone-only action;
/// watch screen space is better spent on the one thing people actually want
/// to do here.
struct WatchLogReadingView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker

    @State private var valueText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                TextField(tracker.unit, text: $valueText)
                    .focused($isFocused)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(Self.parseDecimal(valueText) == nil)
            }
            .navigationTitle("Log \(tracker.unit)")
            .task { isFocused = true }
        }
    }

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
        store.logReading(value: value, date: .now, for: tracker)
        dismiss()
    }
}

#Preview {
    let tracker = SharedPreviewData.makeSampleTracker()
    return WatchLogReadingView(tracker: tracker)
        .modelContainer(SharedPreviewData.container)
        .environment(TrackerStore(modelContext: SharedPreviewData.container.mainContext))
}
