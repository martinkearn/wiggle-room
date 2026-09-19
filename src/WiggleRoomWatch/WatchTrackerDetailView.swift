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

    private func card(tint: Color, title: String, value: Decimal, caption: String?) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(tracker.formattedValue(value))
                .font(.wiggleNumber(size: 22, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var figureCards: some View {
        if tracker.isCompleted(asOf: now) {
            let final = finalPace
            card(
                tint: (final?.status ?? .warning).color,
                title: "Final \(tracker.currentValueLabel)",
                value: final?.currentValue ?? tracker.startingValue,
                caption: final.map { "\($0.statusLine(for: tracker)) \($0.displayDifference(for: tracker))" }
            )
        } else {
            card(tint: pace.status.color, title: tracker.currentValueLabel,
                 value: pace.currentValue, caption: pace.remainingInAllowanceCaption(for: tracker))
            card(tint: WiggleRoomColors.paceRing, title: "Current Target",
                 value: pace.targetValueToday,
                 caption: "Final target will be \(tracker.formattedValue(tracker.projectedFinalValue))")
            if tracker.sortedReadings.count > 1, let estimated = tracker.estimatedFinalValue {
                let difference = tracker.estimatedFinalDifference ?? 0
                card(
                    tint: difference >= 0 ? WiggleRoomColors.good : WiggleRoomColors.bad,
                    title: "Estimated Final Balance",
                    value: estimated,
                    caption: difference == 0
                        ? "Right on target"
                        : "Trending \(difference > 0 ? "under" : "over") target by \(tracker.formattedValue(abs(difference)))"
                )
            }
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
                    if tracker.isCompleted(asOf: now) {
                        CompletedBadge()
                    }

                    RingsView(tracker: tracker, now: now, lineWidth: 8, showsStatusLabel: false)
                        .frame(width: 120, height: 120)

                    figureCards

                    Text(tracker.periodRemainingText(asOf: now))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if tracker.sortedReadings.count > 1 {
                        TrendChartView(tracker: tracker, now: now)
                            .frame(height: 130)
                    }

                    if tracker.latestReading == nil {
                        Text("No readings logged yet — log one to see your pace.")
                            .font(.caption2)
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
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRefreshingFromSource)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle(tracker.name)
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
