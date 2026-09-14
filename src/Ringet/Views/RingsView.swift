//
//  RingsView.swift
//  Ringet
//

import SwiftUI
import Foundation

/// The primary two-ring visualization (§3.4), functionally accurate rather
/// than decorative:
/// - **Outer ring ("elapsed")** fills according to elapsed time within the
///   period. Always neutral gray — it's a clock, not a status indicator.
/// - **Inner ring ("progress")** fills according to how much of the total
///   budget has actually been consumed so far. Colored traffic-light style
///   per `PaceStatus` (§3.2): green on track, amber near target, red needs
///   attention.
///
/// There are only ever these two rings — no more are added for additional
/// trackers or metrics. `showsCenterContent` hides the difference/status
/// overlay and legend for small indicator-sized uses (e.g. list rows),
/// where there isn't room for them to be legible.
struct RingsView: View {
    let tracker: Tracker
    let now: Date
    var lineWidth: CGFloat = 20
    var showsCenterContent: Bool = true

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    private var status: PaceStatus {
        pace.status
    }

    private var statusColor: Color { status.color }

    private var paceFraction: Double {
        guard pace.periodHours > 0 else { return 0 }
        return min(max(pace.hoursElapsed / pace.periodHours, 0), 1)
    }

    private var actualFraction: Double {
        guard tracker.totalAllowance != 0 else { return 0 }
        let ratio = pace.consumedSoFar / tracker.totalAllowance
        return min(max((ratio as NSDecimalNumber).doubleValue, 0), 1)
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    ring(fraction: paceFraction, color: RingetColors.paceRing)
                    ring(fraction: actualFraction, color: statusColor)
                        .padding(lineWidth + 10)

                    if showsCenterContent {
                        // Constrained to the ring's own inner diameter so long
                        // values shrink to fit instead of overflowing past it.
                        centerContent
                            .frame(width: side - (lineWidth + 10) * 2 - 24)
                    }
                }
                .frame(width: side, height: side)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .aspectRatio(1, contentMode: .fit)

            if showsCenterContent {
                legend
            }
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        if tracker.latestReading != nil {
            VStack(spacing: 4) {
                Text(centerStatusLine.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
                Text(centerAmountText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !tracker.usesBudgetLanguage || status == .warning {
                    Text("difference from target")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No data yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// For a budget tracker that's actually over or under (not just at) —
    /// "Over Budget by", "Under Budget by" — the color and word already say
    /// which direction, so the amount itself doesn't need to. Everything
    /// else keeps the plain status label.
    private var centerStatusLine: String {
        let label = status.label(for: tracker)
        guard tracker.usesBudgetLanguage, status != .warning else { return label }
        return "\(label) by"
    }

    private var centerAmountText: String {
        pace.displayDifference(for: tracker)
    }

    /// Uses the exact same wording as the figure cards below (§7.1's
    /// Current Balance/Target Right Now), in the same left-to-right order,
    /// so it's unambiguous which ring is which — not a separately-worded
    /// "Progress"/"Time elapsed" pair a reader has to map onto the figures
    /// themselves.
    private var legend: some View {
        HStack(spacing: 20) {
            legendItem(color: statusColor, label: tracker.currentValueLabel)
            legendItem(color: RingetColors.paceRing, label: "Target Right Now")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func ring(fraction: Double, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Shared color language for pace status (§3.2) — calm, not alarming, but
/// unambiguously traffic-light: green/amber/red map to `PaceStatus`.
enum RingetColors {
    /// Outer ring — a clock, not a status indicator.
    static let paceRing = Color.gray
    /// On track.
    static let good = Color(red: 0.20, green: 0.60, blue: 0.40)
    /// Near target — a small tolerance band, not yet a problem.
    static let warning = Color(red: 0.85, green: 0.60, blue: 0.10)
    /// Needs attention.
    static let bad = Color(red: 0.80, green: 0.25, blue: 0.20)
}

#Preview {
    RingsView(tracker: PreviewData.makeSampleTracker(), now: .now)
        .frame(width: 260, height: 260)
        .padding()
}
