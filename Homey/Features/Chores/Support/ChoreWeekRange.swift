import Foundation

enum ChoreWeekRange {
    static func makeCalendar(weekStartsOn: Int?, timezone: String?) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        calendar.firstWeekday = resolvedFirstWeekday(weekStartsOn)
        return calendar
    }

    static func currentWeek(weekStartsOn: Int?, timezone: String?, now: Date = Date()) -> (start: Date, end: Date)? {
        week(containing: now, calendar: makeCalendar(weekStartsOn: weekStartsOn, timezone: timezone))
    }

    static func week(containing date: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let start = startOfWeek(containing: date, calendar: calendar)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return nil
        }
        return (start, end)
    }

    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromWeekStart, to: startOfDay) ?? startOfDay
    }

    private static func resolvedFirstWeekday(_ weekStartsOn: Int?) -> Int {
        switch weekStartsOn {
        case 1:
            return 1
        case 2:
            return 2
        default:
            return Calendar.autoupdatingCurrent.firstWeekday
        }
    }
}
