//
//  ChartZoom.swift
//  WiggleRoom
//

import Foundation

/// How closely a tracker's trend chart is zoomed: the whole period, or a
/// month or a week centred on today. Zoom only ever changes what the chart
/// draws — the rings, centre figure, status colour and figure cards always
/// stay whole-period — and never changes a reading or any other figure.
///
/// Every surface asks `chartZoomWindow(asOf:)` rather than reading
/// `chartZoom` directly, so a level that has stopped applying (the tracker
/// completed, or its dates were edited shorter) draws the whole period
/// everywhere without its stored value having to change.
enum ChartZoom: String, CaseIterable {
    /// The whole tracking period. The default.
    case full
    /// Fifteen days either side of today. Only for periods of two months
    /// or more.
    case month
    /// Three days either side of today. Only for periods longer than a week.
    case week

    /// Local calendar days drawn either side of today, or `nil` for the
    /// whole period.
    var daysEitherSide: Int? {
        switch self {
        case .full: nil
        case .month: 15
        case .week: 3
        }
    }

    var title: String {
        switch self {
        case .full: "Whole period"
        case .month: "Month"
        case .week: "Week"
        }
    }

    /// The window `zoom` shows as of `now`: whole local calendar days, from
    /// the start of the day `daysEitherSide` before today to the end of the
    /// day `daysEitherSide` after it, so today is always the centre. It is
    /// deliberately not slid to stay inside the tracking period; near
    /// either end the chart simply has empty space on that side. `nil` for
    /// the whole period.
    static func window(for zoom: ChartZoom, around now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let days = zoom.daysEitherSide else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today),
              let end = calendar.date(byAdding: .day, value: days + 1, to: today)
        else { return nil }
        return DateInterval(start: start, end: end)
    }
}

extension Tracker {
    /// The stored zoom level, resolved from `chartZoomRawValue`. Read
    /// through `effectiveChartZoom(asOf:)` for what to draw.
    var chartZoom: ChartZoom {
        get { ChartZoom(rawValue: chartZoomRawValue) ?? .full }
        set { chartZoomRawValue = newValue.rawValue }
    }

    /// The zoom levels that apply right now, widest first. Always includes
    /// `.full`. A tracker can only zoom while it is in progress, since a
    /// window centred on today means nothing before the period starts or
    /// after it ends.
    func availableChartZooms(asOf now: Date, calendar: Calendar = .current) -> [ChartZoom] {
        guard now >= startDate, !isCompleted(asOf: now) else { return [.full] }
        var levels: [ChartZoom] = [.full]
        if let twoMonths = calendar.date(byAdding: .month, value: 2, to: startDate), endDate >= twoMonths {
            levels.append(.month)
        }
        if let oneWeek = calendar.date(byAdding: .day, value: 7, to: startDate), endDate > oneWeek {
            levels.append(.week)
        }
        return levels
    }

    /// The stored level if it currently applies, otherwise the whole period.
    func effectiveChartZoom(asOf now: Date, calendar: Calendar = .current) -> ChartZoom {
        availableChartZooms(asOf: now, calendar: calendar).contains(chartZoom) ? chartZoom : .full
    }

    /// The span the chart should currently show, or `nil` to show the whole
    /// period — either because the chart isn't zoomed or because its level
    /// no longer applies.
    func chartZoomWindow(asOf now: Date, calendar: Calendar = .current) -> DateInterval? {
        ChartZoom.window(for: effectiveChartZoom(asOf: now, calendar: calendar), around: now, calendar: calendar)
    }

    /// The next moment a zoomed chart's window moves — local midnight — so
    /// widget timelines can reload then rather than showing yesterday's
    /// window for up to one more reload interval. `nil` when not zoomed.
    func nextChartZoomWindowChange(after now: Date, calendar: Calendar = .current) -> Date? {
        guard chartZoomWindow(asOf: now, calendar: calendar) != nil else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }

    /// "Sat 18 – Fri 24 Jul" — the days a zoom window covers. The window's
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
