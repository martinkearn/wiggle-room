//
//  TrackerClone.swift
//  WiggleRoom
//

import Foundation

/// What a cloned tracker's form is prefilled with: the next period and a name
/// that won't collide with the original's. Pure functions of the original's
/// dates and name, so the rules are testable without a form or a store.
enum TrackerClone {
    /// The period that follows `startDate`...`endDate`.
    ///
    /// A calendar-month tracker, one that starts at midnight on the 1st and
    /// ends on the 1st of the next month or on the last day of its own month,
    /// rolls to the next calendar month, so February and March don't drift.
    /// Any other period starts the day after the original ends and keeps its
    /// length in days. The time of day of both ends is kept.
    static func nextPeriod(
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        if let month = calendarMonthShape(startDate: startDate, endDate: endDate, calendar: calendar),
           let nextStart = calendar.date(byAdding: .month, value: 1, to: startDate) {
            switch month {
            case .endsOnNextFirst:
                if let nextEnd = calendar.date(byAdding: .month, value: 1, to: nextStart) {
                    return (nextStart, nextEnd)
                }
            case .endsOnLastDay:
                if let nextEnd = lastDay(ofMonthContaining: nextStart, timeOf: endDate, calendar: calendar) {
                    return (nextStart, nextEnd)
                }
            }
        }

        let startOfStart = calendar.startOfDay(for: startDate)
        let startOfEnd = calendar.startOfDay(for: endDate)
        let lengthInDays = calendar.dateComponents([.day], from: startOfStart, to: startOfEnd).day ?? 0
        let nextStart = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        let nextEnd = calendar.date(byAdding: .day, value: lengthInDays, to: nextStart) ?? nextStart
        return (nextStart, nextEnd)
    }

    /// The original's name with a suffix naming the new period's month, such
    /// as "Groceries – Nov 2026". A suffix the original got from an earlier
    /// clone is replaced rather than stacked.
    static func name(
        from original: String,
        originalStart: Date,
        newStart: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let oldSuffix = suffix(for: originalStart, calendar: calendar, locale: locale)
        var base = original.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix(oldSuffix) {
            base = String(base.dropLast(oldSuffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return base + suffix(for: newStart, calendar: calendar, locale: locale)
    }

    private static func suffix(for date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.month(.abbreviated).year()
        return " \u{2013} " + date.formatted(style)
    }

    private enum CalendarMonthShape {
        case endsOnNextFirst
        case endsOnLastDay
    }

    private static func calendarMonthShape(
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> CalendarMonthShape? {
        guard calendar.component(.day, from: startDate) == 1,
              calendar.startOfDay(for: startDate) == startDate
        else { return nil }

        if let nextFirst = calendar.date(byAdding: .month, value: 1, to: startDate), endDate == nextFirst {
            return .endsOnNextFirst
        }
        if let lastDay = lastDay(ofMonthContaining: startDate, timeOf: endDate, calendar: calendar),
           calendar.isDate(endDate, inSameDayAs: lastDay) {
            return .endsOnLastDay
        }
        return nil
    }

    /// The last day of `date`'s month, carrying the time of day of `timeOf`.
    private static func lastDay(ofMonthContaining date: Date, timeOf: Date, calendar: Calendar) -> Date? {
        guard let days = calendar.range(of: .day, in: .month, for: date)?.count else { return nil }
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = days
        let time = calendar.dateComponents([.hour, .minute, .second], from: timeOf)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components)
    }
}
