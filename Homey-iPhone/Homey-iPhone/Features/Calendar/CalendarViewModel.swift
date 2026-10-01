import Combine
import Foundation

enum PhoneCalendarEditScope { case occurrence, series }

@MainActor
final class PhoneCalendarViewModel: ObservableObject {
    @Published private(set) var events: [PhoneCalendarEvent] = []
    @Published private(set) var categories: [PhoneCalendarCategory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var visibleMonth = Date()
    @Published private(set) var selectedDate = Date()

    private let service = PhoneCalendarService()
    private var activeHomeID: UUID?
    private var activeLoadID = UUID()
    private(set) var calendar = Calendar(identifier: .gregorian)
    private(set) var timezone = TimeZone.current

    var userCategories: [PhoneCalendarCategory] { categories.filter { !$0.isChoreCategory } }
    var monthTitle: String { formatter("MMMM yyyy").string(from: visibleMonth) }
    var selectedDateTitle: String { formatter("EEEE, MMMM d").string(from: selectedDate) }
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[start...] + symbols[..<start])
    }

    func configure(home: HomeSummary, force: Bool = false) async {
        let homeChanged = activeHomeID != home.id
        if homeChanged {
            activeLoadID = UUID()
            events = []
            categories = []
            errorMessage = nil
            activeHomeID = home.id
        }
        timezone = home.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        calendar.timeZone = timezone
        calendar.firstWeekday = home.weekStartsOn == 2 ? 2 : 1
        if homeChanged {
            let today = calendar.startOfDay(for: Date())
            visibleMonth = today
            selectedDate = today
        }
        await load(home: home, force: force)
    }

    func load(home: HomeSummary, force: Bool = true) async {
        guard activeHomeID == home.id else { return }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadID == loadID { isLoading = false }
        }
        do {
            let range = visibleRange()
            let result = try await service.fetchUserEvents(homeID: home.id, start: range.start, end: range.end)
            guard activeLoadID == loadID, activeHomeID == home.id else { return }
            events = result.events
            categories = result.categories
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func select(_ date: Date, home: HomeSummary) async {
        selectedDate = calendar.startOfDay(for: date)
        if !calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = date
            await load(home: home)
        }
    }

    func moveMonth(_ offset: Int, home: HomeSummary) async {
        guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = next
        selectedDate = clampedDate(in: next)
        await load(home: home)
    }

    func moveToToday(home: HomeSummary) async {
        let today = calendar.startOfDay(for: Date())
        visibleMonth = today
        selectedDate = today
        await load(home: home)
    }

    func visibleDates() -> [Date] {
        let range = visibleRange()
        var dates: [Date] = []
        var date = range.start
        while date < range.end {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return dates
    }

    func events(on date: Date) -> [PhoneCalendarEvent] {
        events.filter { $0.overlaps(date, calendar: calendar) }.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.occurrenceStartsAt != $1.occurrenceStartsAt { return $0.occurrenceStartsAt < $1.occurrenceStartsAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func indicatorColors(on date: Date) -> [String] {
        var seen = Set<String>()
        return events(on: date).compactMap { $0.categoryColorHex ?? "4A86E8" }.filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }

    func create(_ draft: PhoneCalendarDraft, home: HomeSummary) async -> Bool {
        await mutate {
            try await service.create(homeID: home.id, draft: draft, timezone: timezone, calendar: calendar)
        } reload: {
            selectedDate = calendar.startOfDay(for: draft.startsAt)
            visibleMonth = selectedDate
            await load(home: home)
        }
    }

    func update(_ event: PhoneCalendarEvent, draft: PhoneCalendarDraft, scope: PhoneCalendarEditScope, home: HomeSummary) async -> Bool {
        await mutate {
            if scope == .occurrence {
                try await service.updateOccurrence(event: event, draft: draft, timezone: timezone, calendar: calendar)
            } else {
                try await service.updateSeries(eventID: event.eventID, draft: draft, timezone: timezone, calendar: calendar)
            }
        } reload: { await load(home: home) }
    }

    func delete(_ event: PhoneCalendarEvent, scope: PhoneCalendarEditScope, home: HomeSummary) async -> Bool {
        await mutate {
            if scope == .occurrence { try await service.deleteOccurrence(event: event) }
            else { try await service.deleteSeries(eventID: event.eventID) }
        } reload: { await load(home: home) }
    }

    func refreshedEvent(matching event: PhoneCalendarEvent) -> PhoneCalendarEvent? {
        events.first { $0.occurrenceID == event.occurrenceID } ?? events.first { $0.eventID == event.eventID }
    }

    private func mutate(_ action: () async throws -> Void, reload: () async -> Void) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await action()
            await reload()
            NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: self)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func visibleRange() -> (start: Date, end: Date) {
        guard let month = calendar.dateInterval(of: .month, for: visibleMonth) else {
            let start = calendar.startOfDay(for: visibleMonth)
            return (start, calendar.date(byAdding: .day, value: 42, to: start) ?? start)
        }
        let monthStart = calendar.startOfDay(for: month.start)
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -leading, to: monthStart) ?? monthStart
        let dayCount = calendar.dateComponents([.day], from: start, to: month.end).day ?? 35
        let cellCount = Int(ceil(Double(dayCount) / 7.0)) * 7
        let end = calendar.date(byAdding: .day, value: cellCount, to: start) ?? month.end
        return (start, end)
    }

    private func clampedDate(in month: Date) -> Date {
        let day = calendar.component(.day, from: selectedDate)
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = day
        if let value = calendar.date(from: components), calendar.isDate(value, equalTo: month, toGranularity: .month) {
            return calendar.startOfDay(for: value)
        }
        let interval = calendar.dateInterval(of: .month, for: month)
        return interval.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) }.map(calendar.startOfDay) ?? month
    }

    private func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter()
        value.calendar = calendar
        value.timeZone = timezone
        value.dateFormat = format
        return value
    }
}
