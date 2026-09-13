//
//  TrackerDetailView.swift
//  Ringet
//

import SwiftUI
import SwiftData
import Combine

/// Tracker detail / dashboard (§7.1): the two-ring visual as the primary
/// visual, current value, target value today, ahead/behind figure, days
/// remaining, a "Log a Reading" button (manual sources only — no
/// auto-fetch providers exist yet, so no refresh button), and a trend
/// chart once at least one reading exists.
struct TrackerDetailView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tracker: Tracker

    @State private var isPresentingLogReading = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var now = Date.now

    /// Keeps hours-remaining/pace figures live while the dashboard is open,
    /// without needing any actual data refresh (manual sources have none).
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                RingsView(tracker: tracker, now: now)
                    .frame(width: 220, height: 220)
                    .padding(.top, 12)

                statusLabel

                figuresRow

                Text(periodRemainingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                    Label("Log a Reading", systemImage: "plus.circle.fill")
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
        .onReceive(refreshTimer) { now = $0 }
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(statusColor)
    }

    private var statusText: String {
        guard tracker.latestReading != nil else { return "No data yet" }
        return pace.isAheadOfPace ? "Ahead of pace" : "Behind pace"
    }

    private var statusColor: Color {
        guard tracker.latestReading != nil else { return .secondary }
        return pace.isAheadOfPace ? RingetColors.aheadOfPace : RingetColors.behindPace
    }

    private var figuresRow: some View {
        HStack {
            figure(title: "Current", value: pace.currentValue)
            Spacer()
            figure(title: "Target today", value: pace.targetValueToday)
            Spacer()
            figure(
                title: "Difference",
                value: pace.difference,
                signed: true,
                tint: pace.isAheadOfPace ? RingetColors.aheadOfPace : RingetColors.behindPace
            )
        }
        .padding(.horizontal)
    }

    private func figure(title: String, value: Decimal, signed: Bool = false, tint: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatted(value, signed: signed))
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ value: Decimal, signed: Bool = false) -> String {
        let magnitude = value.formatted(.number.precision(.fractionLength(0...2)))
        let sign = (signed && value >= 0) ? "+" : ""
        return "\(sign)\(magnitude) \(tracker.unit)"
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
