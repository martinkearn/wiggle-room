//
//  RingsView.swift
//  Ringet
//

import SwiftUI
import Foundation

/// The primary two-ring visualization (§3.4), functionally accurate rather
/// than decorative:
/// - **Outer ring ("pace")** fills according to elapsed time within the
///   period. Always neutral gray — it's a clock, not a status indicator.
/// - **Inner ring ("actual")** fills according to how much of the total
///   budget has actually been consumed so far. Green if ahead of pace,
///   amber-red if behind (§3.2).
///
/// Reads less filled than the outer ring → ahead of pace (less consumed
/// than elapsed time implies). More filled → behind pace.
struct RingsView: View {
    let tracker: Tracker
    let now: Date
    var lineWidth: CGFloat = 14

    private var pace: TrackerPace {
        tracker.pace(actualValue: tracker.latestReading?.value ?? tracker.startingValue, asOf: now)
    }

    private var paceFraction: Double {
        guard pace.periodHours > 0 else { return 0 }
        return min(max(pace.hoursElapsed / pace.periodHours, 0), 1)
    }

    private var actualFraction: Double {
        guard tracker.totalAllowance != 0 else { return 0 }
        let ratio = pace.consumedSoFar / tracker.totalAllowance
        return min(max((ratio as NSDecimalNumber).doubleValue, 0), 1)
    }

    private var actualColor: Color {
        pace.isAheadOfPace ? RingetColors.aheadOfPace : RingetColors.behindPace
    }

    var body: some View {
        ZStack {
            ring(fraction: paceFraction, color: RingetColors.paceRing)
            ring(fraction: actualFraction, color: actualColor)
                .padding(lineWidth + 6)
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

/// Shared color language for pace status (§3.2) — calm, not alarming.
enum RingetColors {
    /// Outer ring — a clock, not a status indicator.
    static let paceRing = Color.gray
    /// Calm, confident green — avoid neon/alert greens.
    static let aheadOfPace = Color(red: 0.20, green: 0.60, blue: 0.40)
    /// Amber-leaning red — corrective, not alarming.
    static let behindPace = Color(red: 0.80, green: 0.40, blue: 0.25)
}

#Preview {
    RingsView(tracker: PreviewData.makeSampleTracker(), now: .now)
        .frame(width: 220, height: 220)
        .padding()
}
