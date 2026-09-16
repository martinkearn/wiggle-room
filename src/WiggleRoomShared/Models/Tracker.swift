//
//  Tracker.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// Whether a tracker's value depletes from a starting value (e.g. a bank
/// balance) or accumulates upward from a baseline (e.g. odometer mileage).
enum TrackerDirection: String, Codable, Hashable {
    case decreasing
    case increasing
}

/// A single tracker: a quantity that should move from `startingValue` toward
/// an end-of-period target at a steady pace. See spec §4.1.
///
/// Persisted via SwiftData with CloudKit sync (§6). CloudKit requires every
/// attribute to be optional or have a default, and every relationship to be
/// optional — hence the `= ...` defaults below even where a real tracker
/// always has a real value.
@Model
final class Tracker {
    var id: UUID = UUID()
    var name: String = ""
    var unit: String = ""
    var direction: TrackerDirection = TrackerDirection.decreasing
    var connectedSource: ConnectedSource?
    var sourceTargetId: String?
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var startingValue: Decimal = 0
    var totalAllowance: Decimal = 0

    /// A lightweight local-notification reminder to log a new reading, on a
    /// user-set cadence in days (§5.5 — a nice-to-have, only meaningful for
    /// a manual-entry tracker). `nil` means no reminder. See
    /// `ReminderScheduler`, which schedules/cancels the actual notification
    /// whenever this changes.
    var reminderCadenceDays: Int?

    /// Whether the "closed under budget/on track" celebration has already
    /// been shown for this tracker's completion — a one-shot flag so
    /// re-opening a long-finished tracker's dashboard doesn't replay the
    /// celebration every time. Set the moment it's shown; see
    /// `TrackerDetailView`.
    var hasCelebratedCompletion: Bool = false

    /// Every reading ever logged for this tracker (§4.6 — timestamped
    /// history, not a single overwritten current value). Optional array for
    /// CloudKit compatibility; use `sortedReadings`/`latestReading` rather
    /// than reading this directly.
    @Relationship(deleteRule: .cascade, inverse: \ValueSnapshot.tracker)
    var readings: [ValueSnapshot]? = []

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        direction: TrackerDirection,
        connectedSource: ConnectedSource,
        sourceTargetId: String? = nil,
        startDate: Date,
        endDate: Date,
        startingValue: Decimal,
        totalAllowance: Decimal,
        reminderCadenceDays: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.direction = direction
        self.connectedSource = connectedSource
        self.sourceTargetId = sourceTargetId
        self.startDate = startDate
        self.endDate = endDate
        self.startingValue = startingValue
        self.totalAllowance = totalAllowance
        self.reminderCadenceDays = reminderCadenceDays
        self.readings = []
    }
}

extension Tracker {
    /// All logged readings, oldest first.
    var sortedReadings: [ValueSnapshot] {
        (readings ?? []).sorted { $0.date < $1.date }
    }

    /// The most recently logged reading, if any.
    var latestReading: ValueSnapshot? {
        sortedReadings.last
    }

    /// The value this tracker's history implies as of a given instant — the
    /// most recent reading at or before `date`, or `startingValue` if `date`
    /// is at/before the period start or there's no reading that early yet.
    /// Used by zoom levels (§4.5) to find "what the value was at the start
    /// of this month" without a separately-maintained snapshot.
    func actualValue(atOrBefore date: Date) -> Decimal {
        guard date > startDate, let reading = sortedReadings.last(where: { $0.date <= date }) else {
            return startingValue
        }
        return reading.value
    }
}

extension Tracker {
    /// Units that read as currency (symbol prefixed directly onto the
    /// number, e.g. "£1,234.56") rather than a suffix unit (e.g.
    /// "1,234 miles"). Anything not in this list is treated as a suffix
    /// unit.
    private static let currencySymbols: Set<String> = [
        "£", "$", "€", "¥", "₹", "₩", "₽", "₺", "₪", "R$", "kr", "Fr"
    ]

    var isCurrencyUnit: Bool {
        Tracker.isCurrencyUnit(unit)
    }

    static func isCurrencyUnit(_ unit: String) -> Bool {
        currencySymbols.contains(unit)
    }

    /// Whether this tracker is manually logged (as opposed to a real
    /// auto-fetching connection) — the only source type that supports
    /// hand-editing/deleting individual readings, since a real provider's
    /// history should reflect what it actually reported.
    var isManualEntry: Bool {
        connectedSource?.providerId == "manual"
    }

    /// A decreasing tracker denominated in currency reads naturally as a
    /// budget ("under/over budget"), which draws a much clearer good/bad
    /// line for money than generic on-track language does. Every other
    /// tracker shape (increasing, or non-currency units like mileage) keeps
    /// the neutral wording instead.
    var usesBudgetLanguage: Bool {
        direction == .decreasing && isCurrencyUnit
    }

    /// "Current Balance" reads naturally for a currency tracker (it's a
    /// bank balance, a budget remaining); plain "Current" stays for
    /// everything else (mileage, etc.), where "balance" wouldn't make
    /// sense. Shared by the dashboard's figure card and the ring legend so
    /// they always say exactly the same thing about the same ring.
    var currentValueLabel: String {
        isCurrencyUnit ? "Current Balance" : "Current"
    }

    /// Formats a value in this tracker's unit, placing a currency symbol on
    /// the left with no space (e.g. "£1,234.56") or any other unit on the
    /// right with a space (e.g. "1,234 miles"). `signed` prefixes a "+" for
    /// non-negative values (negative values always show their own "-"). A
    /// whole number shows no decimal places ("£684"); anything with a
    /// fractional part always shows exactly 2 ("£692.40", never "£692.4").
    func formattedValue(_ value: Decimal, signed: Bool = false) -> String {
        Tracker.formattedValue(value, unit: unit, signed: signed)
    }

    /// Unit-string version of `formattedValue(_:signed:)`, usable before a
    /// `Tracker` exists yet — e.g. while a user is still filling in the "New
    /// Tracker" form.
    static func formattedValue(_ value: Decimal, unit: String, signed: Bool = false) -> String {
        let absoluteValue = abs(value)
        let isWhole = (absoluteValue as NSDecimalNumber).doubleValue.truncatingRemainder(dividingBy: 1) == 0
        let magnitude = absoluteValue.formatted(.number.precision(.fractionLength(isWhole ? 0 : 2)))
        let sign: String
        if value < 0 {
            sign = "-"
        } else if signed {
            sign = "+"
        } else {
            sign = ""
        }
        return isCurrencyUnit(unit) ? "\(sign)\(unit)\(magnitude)" : "\(sign)\(magnitude) \(unit)"
    }
}

extension Tracker {
    /// How much would be left over at the end of the period given the
    /// current starting value and total budget — only meaningful for a
    /// decreasing (spend-down) tracker, and only worth surfacing when it's
    /// not simply zero (i.e. starting value and budget aren't the same).
    /// A negative result means the budget exceeds the starting value.
    static func projectedRemainder(direction: TrackerDirection, startingValue: Decimal, totalAllowance: Decimal) -> Decimal? {
        guard direction == .decreasing else { return nil }
        let remainder = startingValue - totalAllowance
        return remainder != 0 ? remainder : nil
    }

    var projectedRemainder: Decimal? {
        Tracker.projectedRemainder(direction: direction, startingValue: startingValue, totalAllowance: totalAllowance)
    }

    /// How much would be left over at the end of the tracker's period, worded
    /// for display — `nil` exactly when `projectedRemainder` is (i.e. the
    /// "spend it all" case needs no extra explanation). Shared by the
    /// dashboard's Target Right Now card and the extra-large widget, which
    /// mirrors that dashboard layout as closely as a widget's static
    /// rendering allows.
    var remainingAtEndCaption: String? {
        guard let remainder = projectedRemainder else { return nil }
        if remainder > 0 {
            return "\(formattedValue(remainder)) will remain at the end"
        } else {
            return "Budget exceeds starting value by \(formattedValue(abs(remainder)))"
        }
    }

    /// "3 days remaining" / "6 hours remaining" / "Period ended", as of a
    /// given instant — the days-remaining line under the dashboard's rings,
    /// also reused by the extra-large widget. `until` defaults to the
    /// tracker's own `endDate`, but a zoom level (§4.5) passes its
    /// sub-period's end instead, so the caption reads correctly when zoomed
    /// (e.g. "12 days remaining" in the current month, not the whole lease).
    func periodRemainingText(asOf now: Date, until: Date? = nil) -> String {
        let calendar = Calendar.current
        let until = until ?? endDate
        if now >= until {
            return "Period ended"
        }
        let days = calendar.dateComponents([.day], from: now, to: until).day ?? 0
        if days >= 1 {
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        }
        let hours = max(calendar.dateComponents([.hour], from: now, to: until).hour ?? 0, 0)
        return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
    }
}

extension Tracker {
    /// Which zoom levels (§4.5) make sense to offer for this tracker, based
    /// on its own period length — a week-long tracker has no need for a
    /// "This year" tab. `.overall` is always available. A shorter level is
    /// offered once the tracker's period meaningfully exceeds it, so the
    /// zoomed sub-period is a real narrowing rather than ~the whole thing.
    var availableZoomLevels: [ZoomLevel] {
        let totalDays = endDate.timeIntervalSince(startDate) / 86400
        var levels: [ZoomLevel] = [.overall]
        if totalDays > 366 { levels.append(.thisYear) }
        if totalDays > 31 { levels.append(.thisMonth) }
        if totalDays > 7 { levels.append(.thisWeek) }
        return levels
    }

    /// The calendar-aligned sub-period (§4.5) for a zoom level, clamped to
    /// this tracker's own overall period — so the zoomed window never
    /// extends before `startDate` or after `endDate` even when the calendar
    /// month/year/week it falls in does. `nil` for `.overall` (no
    /// sub-period — use the tracker's own bounds directly) or when the
    /// clamped window is empty (e.g. `asOf` is exactly at `endDate`, or the
    /// tracker's own period doesn't overlap the calendar unit at all).
    func subPeriod(for zoomLevel: ZoomLevel, asOf: Date) -> DateInterval? {
        guard zoomLevel != .overall else { return nil }
        let calendar = Calendar.current
        let clampedNow = min(max(asOf, startDate), endDate)

        let interval: DateInterval?
        switch zoomLevel {
        case .overall:
            interval = nil
        case .thisYear:
            interval = calendar.dateInterval(of: .year, for: clampedNow)
        case .thisMonth:
            interval = calendar.dateInterval(of: .month, for: clampedNow)
        case .thisWeek:
            interval = calendar.dateInterval(of: .weekOfYear, for: clampedNow)
        }
        guard let interval else { return nil }

        let start = max(interval.start, startDate)
        let end = min(interval.end, endDate)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
