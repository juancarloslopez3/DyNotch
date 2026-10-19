import SwiftUI

/// The days of the month around a date in weeks, starting on the calendar's first weekday.
/// Days of the months either side fill out the first and last weeks.
nonisolated struct MonthGrid: Equatable, Sendable {
    struct Day: Hashable, Identifiable, Sendable {
        /// Its start.
        let date: Date
        let number: Int
        /// In the month, rather than filling out a week before or after it.
        let isInMonth: Bool

        var id: Date { date }
    }

    /// The first of the month.
    let month: Date
    let weeks: [[Day]]
    /// From the start of the first day shown to the end of the last.
    let interval: DateInterval

    init(containing date: Date, calendar: Calendar = .current) {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let month = calendar.component(.month, from: first)
        let days = (0..<((lead + count + 6) / 7 * 7)).compactMap { offset -> Day? in
            guard let day = calendar.date(byAdding: .day, value: offset - lead, to: first) else { return nil }
            return Day(date: day, number: calendar.component(.day, from: day), isInMonth: calendar.component(.month, from: day) == month)
        }
        self.month = first
        weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        let start = days.first?.date ?? first
        let end = days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0.date) } ?? start
        interval = DateInterval(start: start, end: max(end, start))
    }

    /// The week `date` is in.
    func week(containing date: Date, calendar: Calendar = .current) -> [Day] {
        weeks.first { $0.contains { calendar.isDate($0.date, inSameDayAs: date) } } ?? weeks.first ?? []
    }

    /// The weekday initials over the days, in order.
    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let first = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[first...] + symbols[..<first])
    }
}

/// The month at a glance: weekday initials over the weeks, today circled in red and, when the
/// rows have room, dots under the days with events in their calendars' colors. `weekOnly`
/// shows just this week, for a card with little height.
struct MiniMonthView: View {
    let today: Date
    var marks: [Date: [Color]] = [:]
    var weekOnly = false

    private static let headerHeight: CGFloat = 13
    private static let dotSize: CGFloat = 3.5

    var body: some View {
        let calendar = Calendar.current
        let grid = MonthGrid(containing: today, calendar: calendar)
        let weeks = weekOnly ? [grid.week(containing: today, calendar: calendar)] : grid.weeks
        let symbols = MonthGrid.weekdaySymbols(calendar: calendar)
        GeometryReader { proxy in
            let rowHeight = (proxy.size.height - Self.headerHeight) / CGFloat(max(weeks.count, 1))
            let showsMarks = rowHeight >= 22
            // Whole points: a circle a fraction of a point off leaves specks on the glass around it.
            let circle = max(min(20, rowHeight - (showsMarks ? Self.dotSize + 2 : 1), proxy.size.width / 7 - 2).rounded(.down), 12)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(symbols.indices, id: \.self) { index in
                        Text(symbols[index])
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Self.headerHeight, alignment: .top)
                ForEach(weeks, id: \.first?.id) { week in
                    HStack(spacing: 0) {
                        ForEach(week) { day in
                            VStack(spacing: 2) {
                                DayNumber(day: day, isToday: calendar.isDate(day.date, inSameDayAs: today), size: circle)
                                if showsMarks {
                                    EventDots(colors: marks[day.date] ?? [], size: Self.dotSize)
                                        .opacity(day.isInMonth ? 1 : 0.4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: rowHeight)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(today.formatted(date: .complete, time: .omitted))
    }
}

/// A day's number, white in a red circle for today and dimmed for a day of another month.
private struct DayNumber: View {
    let day: MonthGrid.Day
    let isToday: Bool
    let size: CGFloat

    var body: some View {
        Text(verbatim: String(day.number))
            .font(.system(size: min(10.5, size * 0.62), weight: isToday ? .bold : .medium).monospacedDigit())
            .foregroundStyle(isToday ? .white : .white.opacity(day.isInMonth ? 0.85 : 0.28))
            .frame(width: size, height: size)
            .background {
                if isToday {
                    Circle().fill(.red)
                }
            }
    }
}

/// Up to three dots in a row, keeping their height when there are none so rows line up.
private struct EventDots: View {
    let colors: [Color]
    let size: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(colors.indices.prefix(3), id: \.self) { index in
                Circle()
                    .fill(colors[index])
                    .frame(width: size, height: size)
            }
        }
        .frame(height: size)
    }
}

/// This week on one row, each day's initial over its number, today circled in red.
struct WeekStripView: View {
    let today: Date

    var body: some View {
        let calendar = Calendar.current
        let week = MonthGrid(containing: today, calendar: calendar).week(containing: today, calendar: calendar)
        let symbols = MonthGrid.weekdaySymbols(calendar: calendar)
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.element.id) { index, day in
                let isToday = calendar.isDate(day.date, inSameDayAs: today)
                VStack(spacing: 0) {
                    Text(index < symbols.count ? symbols[index] : "")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isToday ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    DayNumber(day: day, isToday: isToday, size: 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(today.formatted(date: .complete, time: .omitted))
    }
}

/// Today the way the Calendar app's icon shows it: the weekday in red over the day's number.
struct TodayBadge: View {
    let today: Date

    var body: some View {
        VStack(spacing: -2) {
            Text(today, format: .dateTime.weekday(.abbreviated))
                .textCase(.uppercase)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.red)
            Text(today, format: .dateTime.day())
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(today.formatted(date: .complete, time: .omitted))
    }
}
