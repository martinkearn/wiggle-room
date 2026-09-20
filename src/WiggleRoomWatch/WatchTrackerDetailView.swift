//
//  WatchTrackerDetailView.swift
//  WiggleRoomWatch
//

import SwiftUI

/// The glanceable detail screen — reuses `RingsView` (identical to the
/// phone) since the two-ring encoding (§3.4) is exactly as useful at watch
/// size as it is on the phone, plus a "Log" action for manual trackers
/// (§7.3's stretch goal, promoted to a real feature since manual entry is
/// the only provider in scope tonight).
struct WatchTrackerDetailView: View {
    @Environment(TrackerStore.self) private var store
    let tracker: Tracker

    @State private var isPresentingLogReading = false
    /// Fully manual as of 2026-09-18, same as the phone/Mac dashboard — no
    /// ongoing ticker while this screen is open. Set on appear and again
    /// after any refresh completes; the "Refresh" button is how a user
    /// updates it deliberately. Multiple devices each independently
    /// auto-polling on their own timer turned out to be a real, avoidable
    /// source of extra Starling requests. Background refresh is unaffected.
    @State private var now: Date = .now
    @State private var isRefreshingFromSource = false

    private func refreshFromSourceIfNeeded() async {
        guard !tracker.isManualEntry, !tracker.isCompleted(asOf: now), !isRefreshingFromSource else { return }
        isRefreshingFromSource = true
        defer { isRefreshingFromSource = false }
        _ = try? await store.refreshFromSource(tracker)
        now = Date.now
    }

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    /// Pace pinned to the tracker's end date using the last logged reading —
    /// the stable final figure once completed (same as the phone's `finalPace`).
    private var finalPace: TrackerPace? {
        guard let latest = tracker.latestReading else { return nil }
        return tracker.pace(actualValue: latest.value, asOf: tracker.endDate)
    }

    /// Time only when it's today, otherwise date and time.
    private static func timingText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "at " + date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private var sourceTimingCaptions: [String] {
        guard !tracker.isManualEntry else { return [] }
        return [
            tracker.lastCheckedDate.map { "Checked \(Self.timingText($0))" },
            tracker.latestReading.map { "Changed \(Self.timingText($0.date))" }
        ].compactMap { $0 }
    }

    private func card(tint: Color, title: String, value: Decimal, captions: [String], variant: Int = 0) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(WiggleRoomFont.fraunces(size: 12, weight: 600, opticalSize: 20, soft: 70))
                .foregroundStyle(.secondary)
            Text(tracker.formattedValue(value))
                .font(.wiggleNumber(size: 22, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            // One stack for every sub-line so spacing is identical on every card.
            VStack(spacing: 2) {
                ForEach(captions, id: \.self) { line in
                    Text(line)
                        .font(.wiggleText(.caption2))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(tint.opacity(0.14), in: WobblyCard.shape(variant, scale: 0.7))
    }

    @ViewBuilder
    private var figureCards: some View {
        if tracker.isCompleted(asOf: now) {
            let final = finalPace
            card(
                tint: (final?.status ?? .warning).color,
                title: "Final \(tracker.currentValueLabel)",
                value: final?.currentValue ?? tracker.startingValue,
                captions: [final.map { "\($0.statusLine(for: tracker)) \($0.displayDifference(for: tracker))" }].compactMap { $0 }
            )
        } else {
            card(tint: pace.status.color, title: tracker.currentValueLabel,
                 value: pace.currentValue,
                 captions: [pace.remainingInAllowanceCaption(for: tracker)].compactMap { $0 } + sourceTimingCaptions)
            card(tint: tracker.accentColor, title: "Current Budget",
                 value: pace.targetValueToday,
                 captions: ["Tracker budget \(tracker.formattedValue(tracker.totalAllowance))",
                           "Final budget \(tracker.formattedValue(tracker.projectedFinalValue))",
                           tracker.sortedReadings.count > 1 ? tracker.estimatedFinalValue.map { "Estimated final \(tracker.formattedValue($0))" } : nil]
                    .compactMap { $0 },
                 variant: 1)
        }
    }

    var body: some View {
        // Same guard as the phone/Mac dashboard (`TrackerDetailView`) —
        // `tracker` is a direct object reference, and SwiftData's own
        // fine-grained Observation re-invokes this body if the tracker is
        // deleted anywhere (e.g. Reset App Data on another device), which
        // crashes hard on the first property read afterward unless checked
        // first. See that view's own comment for the full explanation.
        if tracker.modelContext == nil {
            ContentUnavailableView(
                "Tracker Deleted",
                systemImage: "trash",
                description: Text("This tracker no longer exists.")
            )
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    Text(tracker.name)
                        .font(WiggleRoomFont.headline(20, weight: 700))
                        .multilineTextAlignment(.center)
                    if tracker.isCompleted(asOf: now) {
                        CompletedBadge()
                    }

                    RingsView(tracker: tracker, now: now, lineWidth: 8, showsStatusLabel: false)
                        .frame(width: 120, height: 120)
                        .padding(10)
                        .background(
                            Circle().fill(RadialGradient(
                                colors: [tracker.accentColor.opacity(0.30), .clear],
                                center: .center, startRadius: 10, endRadius: 90
                            ))
                        )

                    figureCards

                    Text(tracker.periodRemainingText(asOf: now))
                        .font(.wiggleText(.caption2))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if tracker.sortedReadings.count > 1 {
                        TrendChartView(tracker: tracker, now: now, showsLegend: false)
                            .frame(height: 130)
                    }

                    if tracker.latestReading == nil {
                        Text("No readings logged yet — log one to see your pace.")
                            .font(.wiggleText(.caption2))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if !tracker.isCompleted(asOf: now) {
                        if tracker.isManualEntry {
                            Button {
                                isPresentingLogReading = true
                            } label: {
                                Label("Log", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                Task { await refreshFromSourceIfNeeded() }
                            } label: {
                                Label("Update", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingFromSource)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("")
            .onAppear {
                now = Date.now
                // Always refresh once when a tracker is first opened, even
                // with no ongoing ticker — opening the screen is itself the
                // signal "I want current data."
                Task { await refreshFromSourceIfNeeded() }
            }
            .sheet(isPresented: $isPresentingLogReading) {
                WatchLogReadingView(tracker: tracker)
            }
        }
    }
}

#Preview {
    let tracker = SharedPreviewData.makeSampleTracker()
    return NavigationStack {
        WatchTrackerDetailView(tracker: tracker)
    }
    .modelContainer(SharedPreviewData.container)
    .environment(TrackerStore(modelContext: SharedPreviewData.container.mainContext))
}
