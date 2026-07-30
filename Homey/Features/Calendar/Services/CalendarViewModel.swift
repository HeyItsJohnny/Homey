import Combine
import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var visibleMonth: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var selectedDayEvents: [CalendarEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingEvent = false
    @Published private(set) var isDeletingEvent = false
    @Published private(set) var errorMessage: String?

    private let calendarService: CalendarService
    private var calendar: Calendar
    private var loadedHomeId: UUID?
    private var activeHomeId: UUID?
    private var realtimeSubscription: CalendarRealtimeSubscription?
    private var realtimeReloadTask: Task<Void, Never>?

    init(calendarService: CalendarService? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.calendarService = calendarService ?? CalendarService(calendar: calendar)
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        self.visibleMonth = today
        self.selectedDate = today
    }

    func configureWeekStart(_ weekStartsOn: Int?) {
        let firstWeekday = weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
        guard calendar.firstWeekday != firstWeekday else {
            return
        }

        calendar.firstWeekday = firstWeekday
        updateSelectedDayEvents()
    }

    func loadInitialData(homeId: UUID?) async {
        guard let homeId else {
            await stopRealtimeUpdates()
            clearForMissingHome()
            return
        }

        if activeHomeId != homeId {
            await stopRealtimeUpdates()
            activeHomeId = homeId
            loadedHomeId = nil
            events = []
            categories = []
            selectedDayEvents = []
            let today = calendar.startOfDay(for: Date())
            visibleMonth = today
            selectedDate = today
            await startRealtimeUpdates(homeId: homeId)
        }

        await reload()
    }

    func reload() async {
        guard let activeHomeId else {
            clearForMissingHome()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedEvents = calendarService.fetchEventsForVisibleMonth(homeId: activeHomeId, month: visibleMonth)
            async let loadedCategories = calendarService.fetchCategories(homeId: activeHomeId)
            events = try await loadedEvents
            categories = try await loadedCategories
            loadedHomeId = activeHomeId
            updateSelectedDayEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        updateSelectedDayEvents()
    }

    func moveToPreviousMonth() async {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: visibleMonth) else {
            return
        }

        visibleMonth = calendar.startOfDay(for: newMonth)
        selectedDate = clampedSelectedDate(for: visibleMonth)
        await reload()
    }

    func moveToNextMonth() async {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else {
            return
        }

        visibleMonth = calendar.startOfDay(for: newMonth)
        selectedDate = clampedSelectedDate(for: visibleMonth)
        await reload()
    }

    func moveToToday() async {
        let today = calendar.startOfDay(for: Date())
        visibleMonth = today
        selectedDate = today
        await reload()
    }

    func focus(on date: Date) async {
        let focusedDate = calendar.startOfDay(for: date)
        selectedDate = focusedDate

        if !calendar.isDate(focusedDate, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = focusedDate
            await reload()
        } else {
            updateSelectedDayEvents()
        }
    }

    func stopRealtimeUpdates() async {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
        await realtimeSubscription?.cancel()
        realtimeSubscription = nil
    }

    func createEvent(
        homeId: UUID?,
        title: String,
        notes: String?,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?,
        assignedUserIds: [UUID]
    ) async -> Bool {
        guard let homeId else {
            errorMessage = "Choose a Home before adding events."
            return false
        }

        guard !isSavingEvent else {
            return false
        }

        let normalizedRange = normalizedEventRange(startDate: startDate, endDate: endDate, isAllDay: isAllDay)
        isSavingEvent = true
        errorMessage = nil
        defer { isSavingEvent = false }

        do {
            _ = try await calendarService.createEvent(
                homeId: homeId,
                title: title,
                notes: notes,
                location: location,
                startsAt: normalizedRange.start,
                endsAt: normalizedRange.end,
                isAllDay: isAllDay,
                timezone: timezone,
                categoryId: categoryId,
                assignedUserIds: assignedUserIds
            )
            selectedDate = calendar.startOfDay(for: normalizedRange.start)
            visibleMonth = normalizedRange.start
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateEvent(
        eventId: UUID,
        title: String,
        notes: String?,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?,
        assignedUserIds: [UUID]
    ) async -> Bool {
        guard !isSavingEvent else {
            return false
        }

        let normalizedRange = normalizedEventRange(startDate: startDate, endDate: endDate, isAllDay: isAllDay)
        isSavingEvent = true
        errorMessage = nil
        defer { isSavingEvent = false }

        do {
            try await calendarService.updateEvent(
                eventId: eventId,
                title: title,
                notes: notes,
                location: location,
                startsAt: normalizedRange.start,
                endsAt: normalizedRange.end,
                isAllDay: isAllDay,
                timezone: timezone,
                categoryId: categoryId,
                assignedUserIds: assignedUserIds
            )
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteEvent(eventId: UUID) async -> Bool {
        guard !isDeletingEvent else {
            return false
        }

        isDeletingEvent = true
        errorMessage = nil
        defer { isDeletingEvent = false }

        do {
            try await calendarService.deleteEvent(eventId: eventId)
            events.removeAll { $0.id == eventId }
            updateSelectedDayEvents()
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func visibleDays() -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let lastDayInMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            return []
        }

        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndDay = calendar.startOfDay(for: lastDayInMonth)
        let leadingDays = daysFromStartOfWeek(to: monthStart)
        let trailingDays = daysToEndOfWeek(from: monthEndDay)

        guard let visibleStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart),
              let visibleEnd = calendar.date(byAdding: .day, value: trailingDays, to: monthEndDay) else {
            return []
        }

        var days: [Date] = []
        var day = visibleStart

        while day <= visibleEnd {
            days.append(day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return days
    }

    func weekdaySymbols() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    func events(on day: Date) -> [CalendarEvent] {
        events
            .filter { event in
                event.overlapsDay(day, calendar: calendar)
            }
            .sortedForAgenda()
    }

    func isDateInVisibleMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
    }

    func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func startRealtimeUpdates(homeId: UUID) async {
        do {
            realtimeSubscription = try await calendarService.subscribeToCalendarChanges(homeId: homeId) { [weak self] in
                self?.scheduleRealtimeReload()
            }
        } catch {
            #if DEBUG
            print("Calendar Realtime unavailable: \(String(reflecting: error))")
            #endif
        }
    }

    private func scheduleRealtimeReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await self?.reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
        }
    }

    private func normalizedEventRange(startDate: Date, endDate: Date, isAllDay: Bool) -> (start: Date, end: Date) {
        if isAllDay {
            let normalizedStart = calendar.startOfDay(for: startDate)
            let normalizedEndDate = max(calendar.startOfDay(for: endDate), normalizedStart)
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: normalizedEndDate) ?? normalizedStart
            return (normalizedStart, exclusiveEnd)
        }

        return (startDate, endDate)
    }

    private func clearForMissingHome() {
        activeHomeId = nil
        loadedHomeId = nil
        events = []
        categories = []
        selectedDayEvents = []
        errorMessage = "Choose a Home to view its calendar."
        isLoading = false
    }

    private func updateSelectedDayEvents() {
        selectedDayEvents = events(on: selectedDate)
    }

    private func clampedSelectedDate(for month: Date) -> Date {
        let selectedDay = calendar.component(.day, from: selectedDate)
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = selectedDay

        if let date = calendar.date(from: components), calendar.isDate(date, equalTo: month, toGranularity: .month) {
            return calendar.startOfDay(for: date)
        }

        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let finalDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            return calendar.startOfDay(for: month)
        }

        return calendar.startOfDay(for: finalDay)
    }

    private func daysFromStartOfWeek(to date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func daysToEndOfWeek(from date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let endOfWeekday = ((calendar.firstWeekday + 5) % 7) + 1
        return (endOfWeekday - weekday + 7) % 7
    }
}

extension CalendarEvent {
    func overlapsDay(_ day: Date, calendar: Calendar) -> Bool {
        let startOfDay = calendar.startOfDay(for: day)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return false
        }

        return startsAt < startOfNextDay && endsAt >= startOfDay
    }
}

extension Array where Element == CalendarEvent {
    func sortedForAgenda() -> [CalendarEvent] {
        sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay && !rhs.isAllDay
            }

            if lhs.startsAt != rhs.startsAt {
                return lhs.startsAt < rhs.startsAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
