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
    @State private var isPresentingReadingHistory = false
    @State private var now = Date.now
    // Set from `.onAppear`, not here: a default value initializes whenever
    // SwiftUI happens to construct this struct, which can be well before
    // the screen actually becomes visible (e.g. NavigationLink destinations
    // are sometimes built ahead of the tap) — that made the countdown start
    // already expired.
    @State private var nextUpdateAt = Date.now
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
                // The whole screen's figures update on this cadence (Target
                // Right Now, the ring, the difference) — not just one card —
                // so the countdown lives up top rather than tucked under a
                // single figure.
                if let screenUpdateCaption {
                    Text(screenUpdateCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }

                RingsView(tracker: tracker, now: now)
                    .frame(width: 260, height: 260)

                figuresRow

                VStack(spacing: 2) {
                    Text(periodRemainingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let remainingAtEndCaption {
                        Text(remainingAtEndCaption)
                            .font(.caption)
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
                    if tracker.isManualEntry {
                        Button {
                            isPresentingReadingHistory = true
                        } label: {
                            Label("Update History", systemImage: "clock")
                        }
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
        .sheet(isPresented: $isPresentingReadingHistory) {
            NavigationStack {
                ReadingHistoryView(tracker: tracker)
            }
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
        .onAppear {
            let appearedAt = Date.now
            now = appearedAt
            nextUpdateAt = appearedAt.addingTimeInterval(60)
            secondsUntilUpdate = 60
        }
        .onReceive(minuteTimer) { date in
            now = date
            nextUpdateAt = date.addingTimeInterval(60)
        }
        .onReceive(secondTimer) { date in
            secondsUntilUpdate = max(0, Int(nextUpdateAt.timeIntervalSince(date).rounded()))
        }
    }

    /// Two visually separate cards, not one shared row — Current Balance
    /// and Target Right Now are different things updated in different ways
    /// (one by logging a reading, one automatically by the clock), and the
    /// "Update Current Value" button belongs specifically to the first one,
    /// not to the pair of them together.
    private var figuresRow: some View {
        HStack(alignment: .top, spacing: 12) {
            card {
                figureContent(title: tracker.currentValueLabel, value: pace.currentValue)
                Button {
                    isPresentingLogReading = true
                } label: {
                    Label("Update", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }

            card {
                figureContent(title: "Target Right Now", value: pace.targetValueToday)
            }
        }
        .padding(.horizontal)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    /// The whole screen's live figures (the ring, the difference, Target
    /// Right Now) recompute on this cadence — not just one card — so this
    /// sits at the very top of the screen rather than under a single figure.
    private var screenUpdateCaption: String? {
        guard now < tracker.endDate else { return nil }
        return "Updates in \(secondsUntilUpdate)s"
    }

    /// How much would be left over at the end of the tracker's period, shown
    /// only when the starting value and total budget actually differ (the
    /// "spend it all" case needs no extra explanation).
    private var remainingAtEndCaption: String? {
        guard let remainder = tracker.projectedRemainder else { return nil }
        if remainder > 0 {
            return "\(tracker.formattedValue(remainder)) will remain at the end"
        } else {
            return "Budget exceeds starting value by \(tracker.formattedValue(abs(remainder)))"
        }
    }

    private func figureContent(title: String, value: Decimal, caption: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tracker.formattedValue(value))
                .font(.title2.monospacedDigit().weight(.semibold))
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
