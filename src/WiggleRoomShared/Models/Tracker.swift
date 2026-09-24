//
//  Tracker.swift
//  WiggleRoom
//

import Foundation
import SwiftData

/// Whether a tracker's value depletes from a starting value (e.g. a bank
/// balance) or accumulates upward from a baseline (e.g. odometer mileage).
///
/// Derived from `TrackerType` rather than chosen independently — direction
/// alone can't say which side of the pace line is the good side. See
/// `TrackerType.higherIsBetter`.
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

    /// This tracker's unit symbol, always one of `TrackerUnit`'s raw values.
    /// Read it through `trackerUnit`, which falls back to the type's default
    /// rather than trusting the stored string.
    var unit: String = ""

    /// What this tracker tracks, stored as a plain `String` rather than a
    /// `RawRepresentable` enum property deliberately. More types are
    /// expected, and a newer device writing a raw value this build has never
    /// heard of must not fault an older device that syncs the record — an
    /// enum-typed SwiftData attribute would. Read it through `trackerType`,
    /// which falls back gracefully.
    ///
    /// Chosen at creation and fixed thereafter: it sets the units, the
    /// direction, which side of the pace line is good, all the wording, and
    /// which sources can back the tracker, so changing it later would
    /// reinterpret every reading already logged.
    var typeRawValue: String = TrackerType.spendingMoney.rawValue

    var connectedSource: ConnectedSource?
    var sourceTargetId: String?
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var startingValue: Decimal = 0

    /// The canonical whole-period movement, whichever way the type frames it
    /// to the user: the budget/allowance itself for an allowance type, or the
    /// distance from `startingValue` to the stated goal for a goal type. See
    /// `TrackerType.totalAllowance(startingValue:targetValue:)`.
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

    /// Index into `TrackerPalette.all` — this tracker's identity colour.
    /// -1 means "never chosen" (a tracker from before colours existed), in
    /// which case `resolvedColorIndex` derives a stable one from its id.
    var colorIndex: Int = -1

    /// SF Symbol name for this tracker's badge; empty means the default for
    /// its type (see `glyphSymbol`).
    var glyph: String = ""

    /// Every reading ever logged for this tracker (§4.6 — timestamped
    /// history, not a single overwritten current value). Optional array for
    /// CloudKit compatibility; use `sortedReadings`/`latestReading` rather
    /// than reading this directly.
    @Relationship(deleteRule: .cascade, inverse: \ValueSnapshot.tracker)
    var readings: [ValueSnapshot]? = []

    init(
        id: UUID = UUID(),
        name: String,
        type: TrackerType,
        unit: TrackerUnit? = nil,
        connectedSource: ConnectedSource?,
        sourceTargetId: String? = nil,
        startDate: Date,
        endDate: Date,
        startingValue: Decimal,
        totalAllowance: Decimal,
        reminderCadenceMinutes: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.unit = (unit ?? type.defaultUnit).symbol
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
    /// What this tracker tracks, resolved from `typeRawValue` with a
    /// graceful fallback for a value written by a newer build.
    var trackerType: TrackerType {
        get { TrackerType(rawValue: typeRawValue) ?? .fallback }
        set { typeRawValue = newValue.rawValue }
    }

    /// This tracker's unit, resolved from `unit` with a fallback to the
    /// type's default for anything unrecognised.
    var trackerUnit: TrackerUnit {
        get { TrackerUnit(rawValue: unit) ?? trackerType.defaultUnit }
        set { unit = newValue.symbol }
    }

    /// Every piece of type-dependent wording — see `TrackerTerminology`.
    var terminology: TrackerTerminology { trackerType.terminology }

    /// Which way the value travels over the period. Still used for ring
    /// fill, `consumedSoFar`, and the chart's reference line; no longer a
    /// thing the user picks.
    var direction: TrackerDirection { trackerType.direction }

    /// Which side of the pace line is the good side.
    var higherIsBetter: Bool { trackerType.higherIsBetter }

    /// Whether this tracker uses manual entry rather than an auto-fetching
    /// connection. All tracker types still support manual history changes.
    var isManualEntry: Bool {
        connectedSource?.providerId == "manual"
    }

    /// Formats a value in this tracker's unit, placing a currency symbol on
    /// the left with no space ("£1,234.56") or any other unit on the right
    /// with a space ("8,400 mi"). `signed` prefixes a "+" for non-negative
    /// values (negative values always show their own "-"). A whole value
    /// drops its decimals entirely ("£684", "85 kg"); anything with a
    /// fractional part shows exactly the unit's own precision ("£692.40",
    /// "84.6 kg") — and for a zero-precision unit that means no decimals at
    /// all, since a fraction of a mile isn't a meaningful reading.
    func formattedValue(_ value: Decimal, signed: Bool = false) -> String {
        Tracker.formattedValue(value, unit: trackerUnit, signed: signed)
    }

    /// Unit-only version of `formattedValue(_:signed:)`, usable before a
    /// `Tracker` exists yet — e.g. while a user is still filling in the "New
    /// Tracker" form.
    static func formattedValue(_ value: Decimal, unit: TrackerUnit, signed: Bool = false) -> String {
        let absoluteValue = abs(value)
        let isWhole = (absoluteValue as NSDecimalNumber).doubleValue.truncatingRemainder(dividingBy: 1) == 0
        let fractionLength = isWhole ? 0 : unit.precision
        let magnitude = absoluteValue.formatted(.number.precision(.fractionLength(fractionLength)))
        let sign: String
        if value < 0 {
            sign = "-"
        } else if signed {
            sign = "+"
        } else {
            sign = ""
        }
        switch unit.placement {
        case .prefix: return "\(sign)\(unit.symbol)\(magnitude)"
        case .suffix: return "\(sign)\(magnitude) \(unit.symbol)"
        }
    }
}

extension Tracker {
    /// How much would be left over at the end of the period given the
    /// current starting value and total allowance — only meaningful for a
    /// spend-down allowance (a budget deliberately smaller than the balance
    /// it's drawn from), and only worth surfacing when it isn't simply zero.
    /// A negative result means the budget exceeds the starting value. A goal
    /// type has no such leftover: its allowance is defined as the distance to
    /// the goal, so the difference is the goal itself, not a remainder.
    static func projectedRemainder(type: TrackerType, startingValue: Decimal, totalAllowance: Decimal) -> Decimal? {
        guard type.orientation == .allowance, type.direction == .decreasing else { return nil }
        let remainder = startingValue - totalAllowance
        return remainder != 0 ? remainder : nil
    }

    var projectedRemainder: Decimal? {
        Tracker.projectedRemainder(type: trackerType, startingValue: startingValue, totalAllowance: totalAllowance)
    }

    /// The tracker's target value at the very end of its period, assuming
    /// the full allowance is used exactly on schedule — `startingValue`
    /// moved by `totalAllowance` in whichever direction the tracker runs.
    /// This is the same figure `pace(actualValue:asOf:)` would report as
    /// `targetValueToday` if evaluated at `endDate` itself, exposed
    /// directly since it depends only on the tracker's own configuration,
    /// not on any particular reading or instant. For a goal type it *is* the
    /// goal the user typed.
    var projectedFinalValue: Decimal {
        switch direction {
        case .decreasing: startingValue - totalAllowance
        case .increasing: startingValue + totalAllowance
        }
    }

    /// The whole-period figure as the user thinks of it (§6): the movement
    /// itself for an allowance type ("a £500 budget"), the end value for a
    /// goal type ("£5,000 in the account"). This is what Add/Edit Tracker
    /// collects and what the dashboard prints beside
    /// `terminology.wholePeriodFigure`.
    var wholePeriodValue: Decimal {
        switch trackerType.orientation {
        case .allowance: totalAllowance
        case .goal: projectedFinalValue
        }
    }

    /// How much would be left over at the end of the tracker's period, worded
    /// for display — `nil` exactly when `projectedRemainder` is (i.e. the
    /// "spend it all" case needs no extra explanation). Shared by the
    /// dashboard's pace card and the extra-large widget, which mirrors that
    /// dashboard layout as closely as a widget's static rendering allows.
    var remainingAtEndCaption: String? {
        guard let remainder = projectedRemainder else { return nil }
        if remainder > 0 {
            return "\(formattedValue(remainder)) left at the end"
        } else {
            return "\(terminology.wholePeriodFigure) is \(formattedValue(abs(remainder))) more than the starting value"
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
