//
//  TrackerType.swift
//  WiggleRoom
//

import Foundation

/// The unit a tracker's numbers are denominated in (§3 of the tracker-types
/// spec).
///
/// Precision and the amber floor are properties of the *unit*, not of the
/// tracker type: kg and lb differ within Weight loss, while £/$/€ are shared
/// by both money types. A `TrackerType` declares which of these it permits
/// and which one it defaults to.
enum TrackerUnit: String, CaseIterable, Hashable, Codable, Identifiable {
    case sterling = "£"
    case dollar = "$"
    case euro = "€"
    case miles = "mi"
    case kilometres = "km"
    case kilograms = "kg"
    case pounds = "lb"
    /// The unit of the plain-number types, which have no unit at all. Its raw
    /// value is a word rather than a symbol precisely because it has no
    /// symbol to use — see `symbol` and `Tracker.unit`.
    case number = "number"

    /// Where the symbol sits relative to the number: a currency symbol is
    /// prefixed with no space ("£684"), most others are suffixed with one
    /// ("8,400 mi"), and a unit with no symbol shows the bare figure
    /// ("8,400").
    enum Placement {
        case prefix
        case suffix
        case bare
    }

    var id: String { rawValue }

    /// The symbol shown alongside a figure in this unit — empty for a unit
    /// that has none. This is *display* only; `Tracker.unit` stores
    /// `rawValue`.
    var symbol: String {
        switch self {
        case .sterling, .dollar, .euro, .miles, .kilometres, .kilograms, .pounds: rawValue
        case .number: ""
        }
    }

    var placement: Placement {
        switch self {
        case .sterling, .dollar, .euro: .prefix
        case .miles, .kilometres, .kilograms, .pounds: .suffix
        case .number: .bare
        }
    }

    /// The most decimal places a value in this unit is ever shown with. A
    /// whole value still drops its decimals entirely (see
    /// `Tracker.formattedValue`), so this is a ceiling, not a fixed width.
    var precision: Int {
        switch self {
        case .sterling, .dollar, .euro: 2
        case .kilograms: 1
        case .miles, .kilometres, .pounds, .number: 0
        }
    }

    /// The narrowest the amber band may ever be for this unit (§7). It
    /// guarantees amber is never narrower than the noise in the data itself,
    /// and is at least two loggable increments so it's always reachable.
    var amberFloor: Decimal {
        switch self {
        case .sterling, .dollar, .euro: Decimal(string: "0.02") ?? 0
        case .miles, .kilometres, .pounds, .number: 2
        case .kilograms: 1
        }
    }

    /// Whether a value in this unit can carry decimals at all. A
    /// zero-precision unit rounds typed input rather than storing precision
    /// nobody logged on purpose — see `roundingHint`.
    var allowsDecimals: Bool { precision > 0 }

    /// Shown inline on the log screen for a unit that can't hold decimals,
    /// so the rounding the app applies is stated rather than silent.
    var roundingHint: String? {
        switch self {
        case .miles: "Round up to the nearest whole mile."
        case .kilometres: "Round up to the nearest whole km."
        case .pounds: "Round up to the nearest whole pound."
        case .number: "Round up to the nearest whole number."
        case .sterling, .dollar, .euro, .kilograms: nil
        }
    }

    /// Rounds a typed value to what this unit can actually hold. A
    /// zero-precision unit rounds *up* (away from zero), matching the hint
    /// the log screen shows and staying on the conservative side for the
    /// distance-and-weight units — an extra mile against an allowance, an
    /// extra pound still to lose. A plain number shares that rule for
    /// consistency: rounding is a property of the unit, and the two
    /// plain-number types run in opposite directions, so no single rounding
    /// rule can be the conservative one for both.
    func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, precision, precision == 0 ? .up : .plain)
        return result
    }
}

/// Whether a tracker is framed as an allowance to stay inside, or a goal to
/// reach (§6). It decides how the whole-period number is *entered*: an
/// allowance is a movement ("a £500 budget"), a goal is an end value ("£5,000
/// in the account", "85 kg"). Storage is uniform either way — see
/// `Tracker.totalAllowance`.
///
/// `nonisolated` because the target defaults to main-actor isolation, which
/// would otherwise isolate this enum's implicit `Equatable` conformance too —
/// and `Tracker.projectedRemainder` compares orientations from a nonisolated
/// context. The sibling enums escape it only by accident of having a raw
/// value, whose derived conformances are nonisolated already.
nonisolated enum TrackerOrientation {
    case allowance
    case goal
}

/// Every piece of type-dependent wording, in one place, so no surface can
/// drift from another (§5, §11).
///
/// Two nouns are needed throughout, not one: the dashboard shows the
/// whole-period figure and today's figure side by side, so reusing a single
/// word for both (e.g. "Target" twice on a Saving tracker) makes the screen
/// unreadable.
struct TrackerTerminology {
    /// The current reading's own name — "Balance", "Mileage", "Weight".
    let currentFigure: String
    /// Today's on-pace figure — "Budget today", "Target today".
    let paceFigure: String
    /// The whole-period figure — "Budget", "Goal", "Allowance".
    let wholePeriodFigure: String
    /// Where the value is meant to land at the very end — "Final budget",
    /// "Goal weight".
    let finalFigure: String
    /// Traffic-light labels (§4).
    let goodLabel: String
    let amberLabel: String
    let badLabel: String
    /// Suffix for the "how much is left" line — "left in this budget",
    /// "still to save".
    let remainingCaption: String
    /// The bare noun for the pace line itself — "Budget", "Target",
    /// "Allowance". Used where a label has room for one word only: the
    /// chart's legend, and the ring's amber caption below.
    let paceNoun: String
    /// Headline for the completion celebration.
    let celebration: String

    /// The small caption under the ring's centre figure while amber, where
    /// the number shown is a signed distance rather than a clean over/under.
    var differenceCaption: String { "difference from \(paceNoun.lowercased())" }
}

/// What a tracker actually tracks (§1). The type is chosen at creation and
/// sets everything else — units, direction, polarity, wording, which sources
/// can back it — and cannot be changed afterwards.
///
/// Every type is a combination of two genuinely independent axes:
/// **direction** (which way the number travels) and **polarity** (which side
/// of the pace line is the good side). Collapsing those into one axis is what
/// made a Saving tracker that's £400 ahead report as red "Over Budget".
/// Because those axes carry all the behaviour, a new type is a matter of
/// wording and units rather than new maths: Spending Credit runs like
/// Mileage, and the two plain-number types like Saving Money and Weight loss.
enum TrackerType: String, CaseIterable, Hashable, Codable, Identifiable {
    case spendingMoney
    case spendingCredit
    case savingMoney
    case mileage
    case weightLoss
    case numberRising
    case numberFalling

    var id: String { rawValue }

    /// The fallback for an unrecognised stored value — see
    /// `Tracker.trackerType`. Newer builds may write a type this one has
    /// never heard of; falling back keeps that record readable rather than
    /// faulting.
    static let fallback: TrackerType = .spendingMoney

    var displayName: String {
        switch self {
        case .spendingMoney: "Spending Money"
        case .spendingCredit: "Spending Credit"
        case .savingMoney: "Saving Money"
        case .mileage: "Mileage"
        case .weightLoss: "Weight loss"
        case .numberRising: "Rising Number"
        case .numberFalling: "Falling Number"
        }
    }

    /// One line describing the type, shown under the picker while it's the
    /// selected one.
    var summary: String {
        switch self {
        case .spendingMoney: "A balance falling against a spending budget."
        case .spendingCredit: "A credit balance rising against a spending limit."
        case .savingMoney: "A balance rising toward a savings goal."
        case .mileage: "An odometer reading against a mileage allowance."
        case .weightLoss: "Weight falling toward a target weight."
        case .numberRising: "A plain number rising toward a target."
        case .numberFalling: "A plain number falling toward a target."
        }
    }

    /// Which way the tracked value travels over the period.
    var direction: TrackerDirection {
        switch self {
        case .spendingMoney, .weightLoss, .numberFalling: .decreasing
        case .spendingCredit, .savingMoney, .mileage, .numberRising: .increasing
        }
    }

    /// Which side of the pace line is the *good* side. This is the axis the
    /// old direction-only model had no room for: Spending Money and Saving
    /// Money are both "higher is better" despite running in opposite
    /// directions, and Spending Credit is the mirror of that — the same
    /// money, spent the same way, but counted upward on a card, so a *lower*
    /// balance is the good news.
    var higherIsBetter: Bool {
        switch self {
        case .spendingMoney, .savingMoney, .numberRising: true
        case .spendingCredit, .mileage, .weightLoss, .numberFalling: false
        }
    }

    var orientation: TrackerOrientation {
        switch self {
        case .spendingMoney, .spendingCredit, .mileage: .allowance
        case .savingMoney, .weightLoss, .numberRising, .numberFalling: .goal
        }
    }

    var permittedUnits: [TrackerUnit] {
        switch self {
        case .spendingMoney, .spendingCredit, .savingMoney: [.sterling, .dollar, .euro]
        case .mileage: [.miles, .kilometres]
        case .weightLoss: [.kilograms, .pounds]
        case .numberRising, .numberFalling: [.number]
        }
    }

    var defaultUnit: TrackerUnit {
        switch self {
        case .spendingMoney, .spendingCredit, .savingMoney: .sterling
        case .mileage: .miles
        case .weightLoss: .kilograms
        case .numberRising, .numberFalling: .number
        }
    }

    var defaultGlyph: String {
        switch self {
        case .spendingMoney: "creditcard.fill"
        case .spendingCredit: "cart.fill"
        case .savingMoney: "banknote.fill"
        case .mileage: "car.fill"
        case .weightLoss: "scalemass.fill"
        case .numberRising: "chart.line.uptrend.xyaxis"
        case .numberFalling: "chart.line.downtrend.xyaxis"
        }
    }

    /// Weight is better measured weekly than daily, so a new weight tracker
    /// arrives with a weekly reminder already set — the app teaches the
    /// behaviour visibly rather than hiding the assumption inside a status
    /// band (§7). Every other type starts with no reminder.
    var defaultReminderCadenceMinutes: Int? {
        switch self {
        case .weightLoss: 10_080
        case .spendingMoney, .spendingCredit, .savingMoney, .mileage, .numberRising, .numberFalling: nil
        }
    }

    /// The cadences the reminder control offers for this type — real,
    /// type-appropriate presets rather than a generic minutes value. Weight
    /// omits Monthly: a weigh-in that infrequent tells you nothing about
    /// pace within a period.
    var reminderPresets: [(label: String, minutes: Int)] {
        let daily = (label: "Daily", minutes: 1_440)
        let everyFewDays = (label: "Every 3 Days", minutes: 4_320)
        let weekly = (label: "Weekly", minutes: 10_080)
        let fortnightly = (label: "Every 2 Weeks", minutes: 20_160)
        let monthly = (label: "Monthly", minutes: 43_200)
        switch self {
        case .weightLoss: return [daily, everyFewDays, weekly, fortnightly]
        case .spendingMoney, .spendingCredit, .savingMoney, .mileage, .numberRising, .numberFalling:
            return [daily, everyFewDays, weekly, fortnightly, monthly]
        }
    }

    /// The label on the form's first value field.
    var startingValueLabel: String {
        switch self {
        case .spendingMoney, .spendingCredit, .savingMoney: "Starting balance"
        case .mileage: "Starting mileage"
        case .weightLoss: "Starting weight"
        case .numberRising, .numberFalling: "Starting value"
        }
    }

    /// The label on the form's second value field — a movement for an
    /// allowance type, an end value for a goal type (§6).
    var targetValueLabel: String {
        switch self {
        case .spendingMoney: "Budget"
        case .spendingCredit: "Limit"
        case .savingMoney: "Goal"
        case .mileage: "Allowance"
        case .weightLoss: "Goal weight"
        case .numberRising, .numberFalling: "Target"
        }
    }

    var startingValueHint: String {
        switch self {
        case .spendingMoney: "The balance this budget starts from."
        case .spendingCredit: "What's already on the card today — usually zero at the start of a period."
        case .savingMoney: "What's in the account today."
        case .mileage: "Today's odometer reading."
        case .weightLoss: "What you weigh today."
        case .numberRising, .numberFalling: "The number you're starting from."
        }
    }

    var targetValueHint: String {
        switch self {
        case .spendingMoney: "How much you can spend across the whole period."
        case .spendingCredit: "How much you can put on the card across the whole period."
        case .savingMoney: "The balance you want to reach by the end."
        case .mileage: "How far you can travel across the whole period."
        case .weightLoss: "The weight you want to reach by the end."
        case .numberRising, .numberFalling: "The number you want to reach by the end."
        }
    }

    /// Shown under the form when the entered values don't make sense for
    /// this type — see `isValidPair(startingValue:targetValue:)`.
    /// The footer under the log screen's value field — what number the user
    /// is actually being asked for.
    var logHint: String {
        switch self {
        case .spendingMoney, .savingMoney: "Enter the balance now — what's actually in the account."
        case .spendingCredit: "Enter the balance now — what's actually on the card."
        case .mileage: "Enter the current odometer reading."
        case .weightLoss: "Enter what you weigh now."
        case .numberRising, .numberFalling: "Enter the number as it stands now."
        }
    }

    var validationMessage: String {
        switch self {
        case .spendingMoney: "The budget must be more than zero."
        case .spendingCredit: "The limit must be more than zero."
        case .savingMoney: "The goal must be higher than the starting balance."
        case .mileage: "The allowance must be more than zero."
        case .weightLoss: "The goal weight must be lower than the starting weight."
        case .numberRising: "The target must be higher than the starting value."
        case .numberFalling: "The target must be lower than the starting value."
        }
    }

    /// Extra guidance under the form, for the one type that has some.
    var formFooter: String? {
        switch self {
        case .weightLoss: "Weekly weigh-ins give a truer picture than daily ones, which swing with water and food."
        case .spendingMoney, .spendingCredit, .savingMoney, .mileage, .numberRising, .numberFalling: nil
        }
    }

    var terminology: TrackerTerminology {
        switch self {
        case .spendingMoney:
            TrackerTerminology(
                currentFigure: "Balance",
                paceFigure: "Budget today",
                wholePeriodFigure: "Budget",
                finalFigure: "Final budget",
                goodLabel: "Below Budget",
                amberLabel: "Just Over Budget",
                badLabel: "Over Budget",
                remainingCaption: "left in this budget",
                paceNoun: "Budget",
                celebration: "Closed Below Budget!"
            )
        case .spendingCredit:
            TrackerTerminology(
                currentFigure: "Balance",
                paceFigure: "Limit today",
                wholePeriodFigure: "Limit",
                finalFigure: "Final limit",
                goodLabel: "Below Limit",
                amberLabel: "Just Over Limit",
                badLabel: "Over Limit",
                remainingCaption: "left in this limit",
                paceNoun: "Limit",
                celebration: "Closed Below Limit!"
            )
        case .savingMoney:
            TrackerTerminology(
                currentFigure: "Balance",
                paceFigure: "Target today",
                wholePeriodFigure: "Goal",
                finalFigure: "Goal",
                goodLabel: "Ahead of Target",
                amberLabel: "Slightly Behind Target",
                badLabel: "Behind Target",
                remainingCaption: "still to save",
                paceNoun: "Target",
                celebration: "Goal Reached!"
            )
        case .mileage:
            TrackerTerminology(
                currentFigure: "Mileage",
                paceFigure: "Allowance today",
                wholePeriodFigure: "Allowance",
                finalFigure: "Final allowance",
                goodLabel: "Below Allowance",
                amberLabel: "Just Over Allowance",
                badLabel: "Over Allowance",
                remainingCaption: "left in this allowance",
                paceNoun: "Allowance",
                celebration: "Closed Below Allowance!"
            )
        case .weightLoss:
            TrackerTerminology(
                currentFigure: "Weight",
                paceFigure: "Target today",
                wholePeriodFigure: "Goal weight",
                finalFigure: "Goal weight",
                goodLabel: "Ahead of Target",
                amberLabel: "Slightly Behind Target",
                badLabel: "Behind Target",
                remainingCaption: "still to lose",
                paceNoun: "Target",
                celebration: "Target Weight Reached!"
            )
        case .numberRising, .numberFalling:
            // A plain number has no domain noun to borrow, so both plain
            // types share one neutral set. They still read correctly in
            // opposite directions because the status labels describe the
            // pace line, not the direction of travel.
            TrackerTerminology(
                currentFigure: "Value",
                paceFigure: "Target today",
                wholePeriodFigure: "Target",
                finalFigure: "Target",
                goodLabel: "Ahead of Target",
                amberLabel: "Slightly Behind Target",
                badLabel: "Behind Target",
                remainingCaption: "still to go",
                paceNoun: "Target",
                celebration: "Target Reached!"
            )
        }
    }

    /// Whether the two numbers the form collects are a sensible pair for this
    /// type (§4). For an allowance type the second figure is a movement and
    /// must be positive; for a goal type it's an end value that has to sit on
    /// the correct side of the starting value.
    func isValidPair(startingValue: Decimal, targetValue: Decimal) -> Bool {
        switch self {
        case .spendingMoney, .spendingCredit, .mileage:
            return targetValue > 0
        case .savingMoney, .numberRising:
            return targetValue > startingValue
        case .weightLoss, .numberFalling:
            return targetValue < startingValue
        }
    }

    /// The canonical `Tracker.totalAllowance` for a pair of form values.
    /// Storage stays uniform across orientations: a goal type's allowance is
    /// simply the distance from where it starts to where it's going, so the
    /// pace engine needs no knowledge of the distinction (§6).
    func totalAllowance(startingValue: Decimal, targetValue: Decimal) -> Decimal {
        switch orientation {
        case .allowance: targetValue
        case .goal: abs(targetValue - startingValue)
        }
    }
}
