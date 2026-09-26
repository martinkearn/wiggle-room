//
//  SourceReading.swift
//  WiggleRoom
//

import Foundation

/// One reading fetched from a provider: the value, and the moment the
/// provider says it belongs to.
///
/// The date matters for a source that reports historic readings rather than a
/// live figure. Apple Health hands back the weigh-in's own timestamp, so a
/// 07:12 reading picked up by the evening poll lands on the trend chart at
/// 07:12 rather than stacking every reading at the time it was collected. For
/// a live-balance provider it is simply "now" — see
/// `SourceProvider.fetchCurrentReading`'s default implementation.
nonisolated struct SourceReading: Equatable {
    let value: Decimal
    let date: Date

    init(value: Decimal, date: Date) {
        self.value = value
        self.date = date
    }
}

/// Whether a reading fetched from a provider is worth recording.
///
/// A pure decision, deliberately separate from `TrackerStore
/// .refreshFromSource` that applies it: it is the part with real edge cases
/// (historic samples, hand-typed corrections, a period that hasn't started),
/// and it is testable on its own without a provider, a store, or a device.
nonisolated enum SourceReadingPolicy {
    /// - Parameters:
    ///   - reading: what the provider returned.
    ///   - roundedValue: `reading.value` rounded at the tracker's unit's own
    ///     precision. Compared instead of the raw value so a provider
    ///     reporting more decimal places than the app displays — Health
    ///     stores weight as a double, so 84.6 kg can arrive as 84.63999… —
    ///     doesn't register as a change on every poll.
    ///   - latestValue: the tracker's latest reading's value, `nil` if it has
    ///     none yet.
    ///   - latestDate: that reading's date.
    ///   - trackerStartDate: the tracker's own `startDate`.
    ///   - force: set when a reading should be recorded even if unchanged —
    ///     used right after a tracker is created or connected, so its first
    ///     reading always lands.
    static func shouldLog(
        reading: SourceReading,
        roundedValue: Decimal,
        latestValue: Decimal?,
        latestDate: Date?,
        trackerStartDate: Date,
        force: Bool
    ) -> Bool {
        // A reading from before the tracker began isn't this tracker's
        // history — a Health-backed tracker created today shouldn't import
        // last week's weigh-in as a mid-period point. `force` doesn't
        // override this, which also means a tracker whose period hasn't
        // started yet collects nothing until it does.
        guard reading.date >= trackerStartDate else { return false }
        guard !force else { return true }
        guard let latestValue, let latestDate else { return true }
        // Nothing new: either the value hasn't moved, or the provider is
        // still reporting a reading this tracker already has. The second test
        // matters for a provider that reports historic readings — without it,
        // a past-dated sample sitting behind a hand-typed correction would be
        // re-inserted on every single poll, forever, because its value
        // differs from the latest reading's.
        return reading.date > latestDate && roundedValue != latestValue
    }
}
