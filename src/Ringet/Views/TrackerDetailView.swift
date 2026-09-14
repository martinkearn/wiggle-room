//
//  TrackerDetailView.swift
//  Ringet
//

import SwiftUI
import SwiftData
import Combine

/// Tracker detail / dashboard (§7.1): the two-ring visual as the primary
/// visual (with the difference-from-target as its centerpiece — that's the
/// key number, per §3.2), current value, live target, days remaining, an
/// "Update Current Value" button (manual sources only — no auto-fetch
/// providers exist yet, so no refresh button), and a trend chart once at
/// least one reading exists.
struct TrackerDetailView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker

    @State private var isPresentingLogReading = false
    @State private var isPresentingEditTracker = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var now = Date.now
    @State private var nextUpdateAt = Date.now.addingTimeInterval(60)
    @State private var secondsUntilUpdate = 60

    /// Recomputes the live pace/target figures once a minute — the period
    /// is fixed, so each minute has one exact target value, no finer-grained
    /// updates are needed. `secondTimer` only drives the visible countdown
    /// to that update, so a user watching the screen sees it's still live.
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                RingsView(tracker: tracker, now: now)
                    .frame(width: 260, height: 260)
                    .padding(.top, 12)

                figuresRow

                VStack(spacing: 2) {
                    Text(periodRemainingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if now < tracker.endDate {
                        Text("Updates in \(secondsUntilUpdate)s")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if tracker.latestReading == nil {
                    Text("No readings logged yet — log one to see your pace.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if tracker.sortedReadings.count > 1 {
                    TrendChartView(tracker: tracker)
                        .frame(height: 220)
                        .padding(.horizontal)
                }

                Button {
                    isPresentingLogReading = true
                } label: {
                    Label("Update Current Value", systemImage: "pencil.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(tracker.name)
        .inlineNavigationBarIfAvailable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isPresentingEditTracker = true
                    } label: {
                        Label("Edit Tracker", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        isPresentingDeleteConfirmation = true
                    } label: {
                        Label("Delete Tracker", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPresentingLogReading) {
            LogReadingView(tracker: tracker)
        }
        .sheet(isPresented: $isPresentingEditTracker) {
            AddTrackerView(existingTracker: tracker)
        }
        .confirmationDialog(
            "Delete \u{201C}\(tracker.name)\u{201D}?",
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Tracker", role: .destructive) {
                store.deleteTracker(tracker)
                dismiss()
            }
        } message: {
            Text("This removes the tracker and all its logged readings. This can't be undone.")
        }
        .onReceive(minuteTimer) { date in
            now = date
            nextUpdateAt = date.addingTimeInterval(60)
        }
        .onReceive(secondTimer) { date in
            secondsUntilUpdate = max(0, Int(nextUpdateAt.timeIntervalSince(date).rounded()))
        }
    }

    private var figuresRow: some View {
        HStack {
            figure(title: "Current", value: pace.currentValue)
            Spacer()
            figure(title: "Target Right Now", value: pace.targetValueToday)
        }
        .padding(.horizontal)
    }

    private func figure(title: String, value: Decimal) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tracker.formattedValue(value))
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var periodRemainingText: String {
        let calendar = Calendar.current
        if now >= tracker.endDate {
            return "Period ended"
        }
        let days = calendar.dateComponents([.day], from: now, to: tracker.endDate).day ?? 0
        if days >= 1 {
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        }
        let hours = max(calendar.dateComponents([.hour], from: now, to: tracker.endDate).hour ?? 0, 0)
        return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
    }
}

#Preview {
    NavigationStack {
        TrackerDetailView(tracker: PreviewData.makeSampleTracker())
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
}
