//
//  TrackerDetailView.swift
//  WiggleRoom
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
    /// The zoom-level lens (§4.5) the dashboard is currently scoped to —
    /// re-scopes the rings, figures, and trend chart together. Only shown
    /// as a picker when `tracker.availableZoomLevels` offers more than just
    /// `.overall`.
    @State private var zoomLevel: ZoomLevel = .overall
    // Set from `.onAppear`, not here: a default value initializes whenever
    // SwiftUI happens to construct this struct, which can be well before
    // the screen actually becomes visible (e.g. NavigationLink destinations
    // are sometimes built ahead of the tap) — that made the countdown start
    // already expired.
    @State private var nextUpdateAt = Date.now
    @State private var secondsUntilUpdate = 60

    /// Ever-incrementing rather than a toggled `Bool` — each increment
    /// always spins a fresh full turn forward from wherever the last one
    /// left off, so back-to-back updates never fight over rotation
    /// direction the way flipping true/false/true would.
    @State private var targetFlipCount = 0

    /// Ticks once a second, both for the visible countdown and to roll the
    /// live pace/target figures over once a minute (see the `onReceive`
    /// below for why that rollover isn't a separate, longer-period timer).
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now, zoomLevel: zoomLevel)
    }

    private var availableZoomLevels: [ZoomLevel] {
        tracker.availableZoomLevels
    }

    /// The zoomed window's own end — the days-remaining caption and the
    /// trend chart's readings should both scope to the sub-period, not the
    /// tracker's full period, once zoomed in.
    private var zoomWindowEnd: Date {
        tracker.subPeriod(for: zoomLevel, asOf: now)?.end ?? tracker.endDate
    }

    private var windowedReadingCount: Int {
        guard let subPeriod = tracker.subPeriod(for: zoomLevel, asOf: now) else {
            return tracker.sortedReadings.count
        }
        return tracker.sortedReadings.filter { $0.date >= subPeriod.start && $0.date <= subPeriod.end }.count
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

                if availableZoomLevels.count > 1 {
                    zoomLevelPicker
                }

                RingsView(tracker: tracker, now: now, zoomLevel: zoomLevel)
                    .frame(width: 260, height: 260)

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
                } else if windowedReadingCount > 1 {
                    TrendChartView(tracker: tracker, zoomLevel: zoomLevel, now: now)
                        .frame(height: 240)
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
        .onReceive(secondTimer) { date in
            // Folded the minute rollover into this same 1-second tick rather
            // than relying on a separate 60-second `Timer.publish` — a
            // `let`-stored timer publisher gets recreated fresh every time
            // this view's body re-evaluates, which happens on every second's
            // tick here; a 1-second timer only ever needs to survive ~1s
            // between those recreations, but a 60-second one never gets a
            // full uninterrupted minute to actually fire, so it silently
            // never rolls over — the countdown reaches 0 and just sits
            // there. Comparing against `nextUpdateAt` directly instead
            // means rollover no longer depends on any timer surviving longer
            // than the interval it's already proven to survive.
            if date >= nextUpdateAt {
                now = date
                nextUpdateAt = date.addingTimeInterval(60)
            }
            secondsUntilUpdate = max(0, Int(nextUpdateAt.timeIntervalSince(date).rounded()))
        }
        // Keyed on the reading's own id, not its value — logging a reading
        // that happens to match the previous one is still a genuine update
        // and should still visibly register, not silently no-op.
        .onChange(of: tracker.latestReading?.id) { _, _ in
            withAnimation(.easeInOut(duration: 0.7)) {
                targetFlipCount += 1
            }
        }
    }

    /// Two visually separate cards, not one shared row — Current Balance
    /// and Target Right Now are different things updated in different ways
    /// (one by logging a reading, one automatically by the clock), and the
    /// "Update Current Value" button belongs specifically to the first one,
    /// not to the pair of them together.
    private var figuresRow: some View {
        HStack(alignment: .top, spacing: 12) {
            card(tint: pace.status.color) {
                figureContent(title: tracker.currentValueLabel, value: pace.currentValue, caption: remainingInAllowanceCaption)
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
                .tint(WiggleRoomColors.brand)
            }

            card(tint: WiggleRoomColors.paceRing) {
                figureContent(title: "Target Right Now", value: pace.targetValueToday, caption: tracker.remainingAtEndCaption)
            }
            // A little "just updated" flourish when a new reading lands —
            // a full turn rather than a half-flip so the card never rests
            // mirror-reversed mid-animation if interrupted by a second
            // rapid update.
            .rotation3DEffect(
                .degrees(Double(targetFlipCount) * 360),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.35
            )
        }
        .padding(.horizontal)
    }

    private func card(tint: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }

    /// The whole screen's live figures (the ring, the difference, Target
    /// Right Now) recompute on this cadence — not just one card — so this
    /// sits at the very top of the screen rather than under a single figure.
    private var screenUpdateCaption: String? {
        guard now < tracker.endDate else { return nil }
        return "Updates in \(secondsUntilUpdate)s"
    }

    private var remainingInAllowanceCaption: String? {
        pace.remainingInAllowanceCaption(for: tracker)
    }

    private func figureContent(title: String, value: Decimal, caption: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(tracker.formattedValue(value))
                .font(.wiggleNumber(size: 24, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var periodRemainingText: String {
        tracker.periodRemainingText(asOf: now, until: zoomWindowEnd)
    }

    /// Segmented zoom-level control (§4.5, §7.1) sitting above the rings —
    /// re-scopes the whole dashboard (rings, figures, chart) to the selected
    /// sub-period. Only shown when the tracker's own length actually offers
    /// more than `.overall` (see `Tracker.availableZoomLevels`).
    private var zoomLevelPicker: some View {
        Picker("Zoom", selection: $zoomLevel) {
            ForEach(availableZoomLevels) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        TrackerDetailView(tracker: PreviewData.makeSampleTracker())
    }
    .modelContainer(PreviewData.container)
    .environment(PreviewData.store)
}
