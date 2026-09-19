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
    /// user-set cadence in minutes (§5.5 — a nice-to-have, only meaningful
    /// for a manual-entry tracker). `nil` means no reminder. See
    /// `ReminderScheduler`, which schedules/cancels the actual notification
    /// whenever this changes.
    var reminderCadenceMinutes: Int?

    /// The last time `BackgroundRefreshScheduler` actually *attempted* a
    /// Starling fetch for this tracker — `nil` for a manual tracker, or an
    /// auto-fetch one that's never had a background attempt yet. Deliberately
    /// tracks attempts, not successful *changes*: `latestReading?.date`
    /// only moves when the value actually changes, so it can't answer
    /// "is this tracker due for another background check yet?" on its
    /// own — a tracker that's been static for days would look permanently
    /// overdue by that measure. Set on every attempt regardless of outcome
    /// (a no-change poll or a failure still counts as "checked"), so a
    /// persistently-failing source doesn't get hammered every wake-up.
    /// Per-tracker (not a single app-wide timestamp) so each tracker's own
    /// background cadence — including a burst-detected one running faster
    /// than its neighbors — is independent of every other tracker's.
    var lastAutoFetchAttempt: Date?

    /// When the source was last successfully asked for this tracker's
    /// balance (by any refresh path), whether or not the value changed —
    /// shown on the detail screen as "Checked". Set by
    /// `TrackerStore.refreshFromSource`.
    var lastCheckedDate: Date?

    /// Whether the "closed under budget/on track" celebration has already
    /// been shown for this tracker's completion — a one-shot flag so
    /// re-opening a long-finished tracker's dashboard doesn't replay the
    /// celebration every time. Set the moment it's shown; see
    /// `TrackerDetailView`.
    var hasCelebratedCompletion: Bool = false

    /// Position in the All Trackers list when the sort setting is Custom
    /// (Settings → Tracker Order). Synced like the rest of the record.
    var sortOrder: Int = 0

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
        reminderCadenceMinutes: Int? = nil
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
        self.reminderCadenceMinutes = reminderCadenceMinutes
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

    /// Whether this tracker's period has already ended as of a given
    /// instant — the single source of truth for "completed," used to gate
    /// balance updates/reminders and to switch the dashboard and other
    /// surfaces into their completed presentation.
    func isCompleted(asOf now: Date = .now) -> Bool {
        now >= endDate
    }

    /// Whether `startDate`/`endDate` carry a meaningful time of day, rather
    /// than both sitting at midnight — mirrors the "Set specific times"
    /// toggle in the Add/Edit Tracker form (`AddTrackerView`), so a date
    /// display elsewhere (the dashboard's header) can decide whether
    /// showing a time alongside the date is actually telling the user
    /// something they set, or just repeating an implicit midnight default.
    var hasExplicitTimes: Bool {
        let calendar = Calendar.current
        return !calendar.isDate(startDate, equalTo: calendar.startOfDay(for: startDate), toGranularity: .minute)
            || !calendar.isDate(endDate, equalTo: calendar.startOfDay(for: endDate), toGranularity: .minute)
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
    /// non-negative values (negative values always show their own "-"). For
    /// a currency unit, a whole number shows no decimal places ("£684") and
    /// anything with a fractional part always shows exactly 2 ("£692.40",
    /// never "£692.4"). A non-currency unit (mileage and the like) never
    /// shows decimal places at all — a fraction of a mile isn't a
    /// meaningful reading, so it's rounded to the nearest whole number
    /// rather than surfacing precision nobody logged on purpose.
    func formattedValue(_ value: Decimal, signed: Bool = false) -> String {
        Tracker.formattedValue(value, unit: unit, signed: signed)
    }

    /// Unit-string version of `formattedValue(_:signed:)`, usable before a
    /// `Tracker` exists yet — e.g. while a user is still filling in the "New
    /// Tracker" form.
    static func formattedValue(_ value: Decimal, unit: String, signed: Bool = false) -> String {
        let absoluteValue = abs(value)
        let showsDecimals = isCurrencyUnit(unit)
        let isWhole = (absoluteValue as NSDecimalNumber).doubleValue.truncatingRemainder(dividingBy: 1) == 0
        let fractionLength = showsDecimals && !isWhole ? 2 : 0
        let magnitude = absoluteValue.formatted(.number.precision(.fractionLength(fractionLength)))
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

    /// The tracker's target balance at the very end of its period, assuming
    /// the full allowance is used exactly on schedule — `startingValue`
    /// moved by `totalAllowance` in whichever direction the tracker runs.
    /// This is the same figure `pace(actualValue:asOf:)` would report as
    /// `targetValueToday` if evaluated at `endDate` itself, exposed
    /// directly since it depends only on the tracker's own configuration,
    /// not on any particular reading or instant.
    var projectedFinalValue: Decimal {
        switch direction {
        case .decreasing: startingValue - totalAllowance
        case .increasing: startingValue + totalAllowance
        }
    }

    /// How much would be left over at the end of the tracker's period, worded
    /// for display — `nil` exactly when `projectedRemainder` is (i.e. the
    /// "spend it all" case needs no extra explanation). Shared by the
    /// dashboard's Current Target card and the extra-large widget, which
    /// mirrors that dashboard layout as closely as a widget's static
    /// rendering allows.
    var remainingAtEndCaption: String? {
        guard let remainder = projectedRemainder else { return nil }
        if remainder > 0 {
            return "\(formattedValue(remainder)) should remain at the end"
        } else {
            return "Budget exceeds starting value by \(formattedValue(abs(remainder)))"
        }
    }

    /// "3 days remaining" / "6 hours remaining" / "42 minutes remaining" /
    /// "Period ended", as of a given instant — the days-remaining line under
    /// the dashboard's rings, also reused by the extra-large widget.
    func periodRemainingText(asOf now: Date) -> String {
        let calendar = Calendar.current
        if now >= endDate {
            return "Period ended"
        }
        let days = calendar.dateComponents([.day], from: now, to: endDate).day ?? 0
        if days >= 1 {
            return "\(days) day\(days == 1 ? "" : "s") remaining"
        }
        let hours = max(calendar.dateComponents([.hour], from: now, to: endDate).hour ?? 0, 0)
        if hours >= 1 {
            return "\(hours) hour\(hours == 1 ? "" : "s") remaining"
        }
        let minutes = max(calendar.dateComponents([.minute], from: now, to: endDate).minute ?? 0, 0)
        return "\(minutes) minute\(minutes == 1 ? "" : "s") remaining"
    }
}
