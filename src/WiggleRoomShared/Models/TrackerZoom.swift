//
//  TrackerZoom.swift
//  WiggleRoom
//

import Foundation

/// Zoom on a long tracker: the rings and chart magnify a five-day window
/// around today, like a pinch-zoom on a static image. Nothing here changes
/// a stored value or any whole-period figure — the centre number, status
/// colour and figure cards always stay whole-period. Only what the rings
/// and chart *draw* is magnified.
///
/// Every surface asks `zoomWindow(asOf:)` rather than reading `isZoomed`
/// directly, so a tracker that has stopped being eligible (completed, or
/// its dates edited down to five days or fewer) renders unzoomed
/// everywhere without its stored flag having to change.
enum TrackerZoom {
    /// Two days either side of today, plus today.
    static let windowDayCount = 5
    static let daysBeforeToday = 2

    /// The zoom window as of `now`: five local calendar days, from the start
    /// of the day two days ago, slid (keeping its length) so it never
    /// extends outside the tracking period.
    static func window(
        periodStart: Date,
        periodEnd: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        var start = calendar.date(byAdding: .day, value: -daysBeforeToday, to: today) ?? today
        let fullEnd = calendar.date(byAdding: .day, value: windowDayCount, to: start)
            ?? start.addingTimeInterval(Double(windowDayCount) * 86_400)
        let length = fullEnd.timeIntervalSince(start)
        var end = fullEnd

        if start < periodStart {
            start = periodStart
            end = start.addingTimeInterval(length)
        }
        if end > periodEnd {
            end = periodEnd
            start = max(end.addingTimeInterval(-length), periodStart)
        }
        return DateInterval(start: start, end: end)
    }
}

/// How far each ring is filled, plus whether the inner ring's true value
/// lies outside what it can show. `overflow` is only ever set when zoomed:
/// unzoomed, the inner ring simply clamps as it always has.
struct RingFractions: Equatable {
    enum Overflow: Equatable {
        /// The value is behind the start of the window's slice — the ring
        /// is pinned empty.
        case belowEmpty
        /// The value is past the end of the window's slice — the ring is
        /// pinned full.
        case beyondFull
    }

    let elapsed: Double
    let consumed: Double
    var overflow: Overflow?
}

extension Tracker {
    /// Whether this tracker can be zoomed at all: its period is longer than
    /// the zoom window, and it hasn't completed.
    func canZoom(asOf now: Date) -> Bool {
        !isCompleted(asOf: now)
            && endDate.timeIntervalSince(startDate) > Double(TrackerZoom.windowDayCount) * 86_400
    }

    /// The window the rings and chart should currently show, or `nil` to
    /// show the whole period — either because the tracker isn't zoomed or
    /// because it's no longer eligible.
    func zoomWindow(asOf now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard isZoomed, canZoom(asOf: now) else { return nil }
        return TrackerZoom.window(periodStart: startDate, periodEnd: endDate, now: now, calendar: calendar)
    }

    /// The next moment a zoomed tracker's window moves — local midnight —
    /// so widget timelines can reload then rather than showing yesterday's
    /// window for up to one more reload interval. `nil` when not zoomed.
    func nextZoomWindowChange(after now: Date, calendar: Calendar = .current) -> Date? {
        guard zoomWindow(asOf: now, calendar: calendar) != nil else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }

    /// Expected consumption at a given instant — the pace line's own figure.
    private func expectedConsumption(at date: Date) -> Decimal {
        pace(actualValue: startingValue, asOf: date).expectedConsumedByNow
    }

    /// Both rings' fills for the tracker's latest reading as of `now`,
    /// magnified to the zoom window when the tracker is zoomed.
    func ringFractions(asOf now: Date) -> RingFractions {
        ringFractions(actualValue: latestReading?.value ?? startingValue, asOf: now, window: zoomWindow(asOf: now))
    }

    /// Unzoomed (`window == nil`): the share of the whole period elapsed, and
    /// the share of the whole allowance consumed.
    ///
    /// Zoomed: each ring shows only the slice of its whole-period ring that
    /// falls inside `window`, stretched to fill the circle. The inner ring
    /// maps the pace line's expected consumption at the window's start and
    /// end onto empty and full, so a tracker exactly on pace has both rings
    /// level, just as it does unzoomed — the same relationship, magnified.
    func ringFractions(actualValue: Decimal, asOf now: Date, window: DateInterval?) -> RingFractions {
        let pace = pace(actualValue: actualValue, asOf: now)
        guard let window else {
            let elapsed = pace.periodHours > 0 ? min(max(pace.hoursElapsed / pace.periodHours, 0), 1) : 0
            let consumed: Double
            if totalAllowance != 0 {
                consumed = min(max((pace.consumedSoFar / totalAllowance as NSDecimalNumber).doubleValue, 0), 1)
            } else {
                consumed = 0
            }
            return RingFractions(elapsed: elapsed, consumed: consumed)
        }

        let elapsed = window.duration > 0
            ? min(max(now.timeIntervalSince(window.start) / window.duration, 0), 1)
            : 0

        let expectedAtStart = expectedConsumption(at: window.start)
        let expectedAtEnd = expectedConsumption(at: window.end)
        let span = expectedAtEnd - expectedAtStart
        guard span != 0 else { return RingFractions(elapsed: elapsed, consumed: 0) }
        let raw = ((pace.consumedSoFar - expectedAtStart) / span as NSDecimalNumber).doubleValue
        let overflow: RingFractions.Overflow? = raw < 0 ? .belowEmpty : raw > 1 ? .beyondFull : nil
        return RingFractions(elapsed: elapsed, consumed: min(max(raw, 0), 1), overflow: overflow)
    }

    /// "Sat 18 – Wed 22 Jul" — the days a zoom window covers. The window's
    /// end is exclusive (midnight after the last day), so the last day shown
    /// is the one just before it. The month is only repeated on the first
    /// day when the window spans two months.
    static func zoomRangeText(_ window: DateInterval, calendar: Calendar = .current) -> String {
        let lastDay = window.end.addingTimeInterval(-1)
        let dayStyle = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        let dayMonthStyle = dayStyle.month(.abbreviated)
        let sameMonth = calendar.isDate(window.start, equalTo: lastDay, toGranularity: .month)
        let first = window.start.formatted(sameMonth ? dayStyle : dayMonthStyle)
        return "\(first) \u{2013} \(lastDay.formatted(dayMonthStyle))"
    }
}
