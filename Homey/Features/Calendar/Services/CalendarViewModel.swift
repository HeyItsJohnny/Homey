import Combine
import Foundation

enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case month
    case week

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .month:
            return "Month"
        case .week:
            return "Week"
        }
    }
}

enum CalendarEventFilter: String, CaseIterable, Identifiable {
    case all
    case meals
    case chores
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .meals:
            return "Meals"
        case .chores:
            return "Chores"
        case .calendar:
            return "Calendar"
        }
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var displayMode: CalendarDisplayMode = .week
    @Published private(set) var eventFilter: CalendarEventFilter = .all
    @Published private(set) var visibleMonth: Date
    @Published private(set) var visibleWeekAnchor: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var selectedDayEvents: [CalendarEvent] = []
    @Published private(set) var linkedEventPresentations: [String: CalendarLinkedEventPresentation] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingEvent = false
    @Published private(set) var isDeletingEvent = false
    @Published private(set) var errorMessage: String?

    private let calendarService: CalendarService
    private let enrichmentService: CalendarLinkedEventEnrichmentService
    private var calendar: Calendar
    private var loadedHomeId: UUID?
    private var activeHomeId: UUID?
    private var realtimeSubscription: CalendarRealtimeSubscription?
    private var realtimeReloadTask: Task<Void, Never>?

    init(
        calendarService: CalendarService? = nil,
        enrichmentService: CalendarLinkedEventEnrichmentService? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendarService = calendarService ?? CalendarService(calendar: calendar)
        self.enrichmentService = enrichmentService ?? CalendarLinkedEventEnrichmentService()
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        self.visibleMonth = today
        self.visibleWeekAnchor = today
        self.selectedDate = today
    }

    func configureWeekStart(_ weekStartsOn: Int?) {
        let firstWeekday = weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
        guard calendar.firstWeekday != firstWeekday else {
            return
        }

        calendar.firstWeekday = firstWeekday
        visibleWeekAnchor = selectedDate
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
            linkedEventPresentations = [:]
            let today = calendar.startOfDay(for: Date())
            visibleMonth = today
            visibleWeekAnchor = today
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
            let requestMode = displayMode
            let requestMonth = visibleMonth
            let requestWeekRange = visibleWeekRange()
            let requestHomeId = activeHomeId

            async let loadedEvents: [CalendarEvent] = {
                switch requestMode {
                case .month:
                    return try await calendarService.fetchEventsForVisibleMonth(homeId: requestHomeId, month: requestMonth)
                case .week:
                    guard let requestWeekRange else {
                        throw CalendarServiceError.invalidDateRange
                    }
                    return try await calendarService.fetchEvents(
                        homeId: requestHomeId,
                        rangeStart: requestWeekRange.start,
                        rangeEnd: requestWeekRange.end
                    )
                }
            }()
            async let loadedCategories = calendarService.fetchCategories(homeId: activeHomeId)

            let resolvedEvents = try await loadedEvents
            let resolvedCategories = try await loadedCategories
            let resolvedLinkedPresentations = await enrichmentService.presentations(
                for: resolvedEvents,
                homeId: requestHomeId
            )

            guard activeHomeId == requestHomeId,
                  displayMode == requestMode else {
                return
            }

            events = resolvedEvents
            categories = resolvedCategories
            linkedEventPresentations = resolvedLinkedPresentations
            loadedHomeId = activeHomeId
            updateSelectedDayEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadAfterExternalCalendarChange(reason: String) async {
        guard let activeHomeId else {
            return
        }

        let visibleRange = currentVisibleRange()
        logCalendarRefresh(reason: reason, homeId: activeHomeId, visibleRange: visibleRange)
        await reload()
        logCalendarReloadComplete()
    }

    func setDisplayMode(_ mode: CalendarDisplayMode) async {
        guard displayMode != mode else {
            return
        }

        displayMode = mode
        switch mode {
        case .month:
            visibleMonth = selectedDate
        case .week:
            visibleWeekAnchor = selectedDate
        }
        await reload()
    }

    func setEventFilter(_ filter: CalendarEventFilter) {
        guard eventFilter != filter else {
            return
        }

        eventFilter = filter
        updateSelectedDayEvents()
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
        visibleWeekAnchor = today
        selectedDate = today
        await reload()
    }

    func moveToPreviousPeriod() async {
        switch displayMode {
        case .month:
            await moveToPreviousMonth()
        case .week:
            await moveToPreviousWeek()
        }
    }

    func moveToNextPeriod() async {
        switch displayMode {
        case .month:
            await moveToNextMonth()
        case .week:
            await moveToNextWeek()
        }
    }

    func moveToPreviousWeek() async {
        await moveWeek(by: -1)
    }

    func moveToNextWeek() async {
        await moveWeek(by: 1)
    }

    func focus(on date: Date) async {
        let focusedDate = calendar.startOfDay(for: date)
        selectedDate = focusedDate
        visibleWeekAnchor = focusedDate

        if displayMode == .week {
            await reload()
        } else if !calendar.isDate(focusedDate, equalTo: visibleMonth, toGranularity: .month) {
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
        assignedUserIds: [UUID],
        recurrence: CalendarRecurrenceInput = CalendarRecurrenceInput()
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
                assignedUserIds: assignedUserIds,
                recurrence: recurrence
            )
            selectedDate = calendar.startOfDay(for: normalizedRange.start)
            visibleMonth = normalizedRange.start
            visibleWeekAnchor = normalizedRange.start
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
        assignedUserIds: [UUID],
        recurrence: CalendarRecurrenceInput = CalendarRecurrenceInput()
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
                assignedUserIds: assignedUserIds,
                recurrence: recurrence
            )
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateOccurrence(
        eventId: UUID,
        occurrenceStartsAt: Date,
        title: String,
        notes: String?,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?
    ) async -> Bool {
        guard !isSavingEvent else {
            return false
        }

        let normalizedRange = normalizedEventRange(startDate: startDate, endDate: endDate, isAllDay: isAllDay)
        isSavingEvent = true
        errorMessage = nil
        defer { isSavingEvent = false }

        do {
            try await calendarService.updateOccurrence(
                eventId: eventId,
                occurrenceStartsAt: occurrenceStartsAt,
                title: title,
                startsAt: normalizedRange.start,
                endsAt: normalizedRange.end,
                timezone: timezone,
                isAllDay: isAllDay,
                notes: notes,
                location: location,
                categoryId: categoryId
            )
            selectedDate = calendar.startOfDay(for: normalizedRange.start)
            visibleMonth = normalizedRange.start
            visibleWeekAnchor = normalizedRange.start
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            await reload()
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
            events.removeAll { $0.eventId == eventId }
            updateSelectedDayEvents()
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteOccurrence(eventId: UUID, occurrenceStartsAt: Date) async -> Bool {
        guard !isDeletingEvent else {
            return false
        }

        isDeletingEvent = true
        errorMessage = nil
        defer { isDeletingEvent = false }

        do {
            try await calendarService.deleteOccurrence(eventId: eventId, occurrenceStartsAt: occurrenceStartsAt)
            events.removeAll { $0.eventId == eventId && $0.occurrenceStartsAt == occurrenceStartsAt }
            updateSelectedDayEvents()
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            await reload()
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

    func weekDays() -> [Date] {
        guard let range = visibleWeekRange() else {
            return []
        }

        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: range.start)
        }
    }

    func visibleWeekRange() -> (start: Date, end: Date)? {
        let weekStart = startOfWeek(containing: visibleWeekAnchor)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return nil
        }

        return (weekStart, weekEnd)
    }

    func visibleWeekEvents() -> [CalendarEvent] {
        guard let range = visibleWeekRange() else {
            return []
        }

        return filteredEvents
            .filter { $0.overlapsRange(start: range.start, end: range.end) }
            .sortedForCalendarDisplay()
    }

    func isDateInVisibleWeek(_ date: Date) -> Bool {
        guard let range = visibleWeekRange() else {
            return false
        }

        return date >= range.start && date < range.end
    }

    func weekdaySymbols() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    func events(on day: Date) -> [CalendarEvent] {
        filteredEvents
            .filter { event in
                event.overlapsDay(day, calendar: calendar)
            }
            .sortedForAgenda()
    }

    var filteredEventCount: Int {
        filteredEvents.count
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
            linkedEventPresentations = [:]
            errorMessage = "Choose a Home to view its calendar."
            isLoading = false
        }

    private func updateSelectedDayEvents() {
        selectedDayEvents = events(on: selectedDate)
    }

    private var filteredEvents: [CalendarEvent] {
        events.filter { event in
            switch eventFilter {
            case .all:
                return true
            case .meals:
                return linkedEventPresentations[event.id]?.plannedMeal != nil || event.matchesCalendarCategoryName("Meals")
            case .chores:
                return linkedEventPresentations[event.id]?.chore != nil || event.matchesCalendarCategoryName("Chores")
            case .calendar:
                return linkedEventPresentations[event.id] == nil
                    && !event.matchesCalendarCategoryName("Meals")
                    && !event.matchesCalendarCategoryName("Chores")
            }
        }
    }

    func linkedPresentation(for event: CalendarEvent) -> CalendarLinkedEventPresentation? {
        linkedEventPresentations[event.id]
    }

    private func currentVisibleRange() -> (start: Date, end: Date)? {
        switch displayMode {
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else {
                return nil
            }
            return (monthInterval.start, monthInterval.end)
        case .week:
            return visibleWeekRange()
        }
    }

    private func logCalendarRefresh(reason: String, homeId: UUID, visibleRange: (start: Date, end: Date)?) {
        #if DEBUG
        print("========== CHORE CALENDAR REFRESH ==========")
        print("reason: \(reason)")
        print("home_id: \(homeId.uuidString)")
        print("visible_range_start: \(visibleRange.map { CalendarRefreshLogFormatter.string(from: $0.start) } ?? "nil")")
        print("visible_range_end: \(visibleRange.map { CalendarRefreshLogFormatter.string(from: $0.end) } ?? "nil")")
        print("============================================")
        #endif
    }

    private func logCalendarReloadComplete() {
        #if DEBUG
        print("========== CALENDAR RELOAD COMPLETE ==========")
        print("event_count: \(events.count)")
        print("==============================================")
        #endif
    }

    private func moveWeek(by value: Int) async {
        let selectedWeekdayOffset = daysFromStartOfWeek(to: selectedDate)
        let currentWeekStart = startOfWeek(containing: visibleWeekAnchor)
        guard let newWeekStart = calendar.date(byAdding: .weekOfYear, value: value, to: currentWeekStart),
              let newSelectedDate = calendar.date(byAdding: .day, value: selectedWeekdayOffset, to: newWeekStart) else {
            return
        }

        visibleWeekAnchor = newWeekStart
        visibleMonth = newSelectedDate
        selectedDate = calendar.startOfDay(for: newSelectedDate)
        await reload()
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

    private func startOfWeek(containing date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let leadingDays = daysFromStartOfWeek(to: startOfDay)
        return calendar.date(byAdding: .day, value: -leadingDays, to: startOfDay) ?? startOfDay
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

private enum CalendarRefreshLogFormatter {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

extension CalendarEvent {
    func overlapsDay(_ day: Date, calendar: Calendar) -> Bool {
        let startOfDay = calendar.startOfDay(for: day)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return false
        }

        return occurrenceStartsAt < startOfNextDay && occurrenceEndsAt > startOfDay
    }

    func overlapsRange(start: Date, end: Date) -> Bool {
        occurrenceStartsAt < end && occurrenceEndsAt > start
    }
}

private extension CalendarEvent {
    func matchesCalendarCategoryName(_ expectedName: String) -> Bool {
        guard let categoryName else {
            return false
        }

        return normalizedCalendarCategoryName(categoryName) == normalizedCalendarCategoryName(expectedName)
    }

    private func normalizedCalendarCategoryName(_ name: String) -> String {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.hasSuffix("s") {
            return String(normalized.dropLast())
        }

        return normalized
    }
}

extension Array where Element == CalendarEvent {
    func sortedForAgenda() -> [CalendarEvent] {
        sortedForCalendarDisplay(allDayFirst: true)
    }

    func sortedForCalendarDisplay(allDayFirst: Bool = false) -> [CalendarEvent] {
        sorted { lhs, rhs in
            if allDayFirst && lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay && !rhs.isAllDay
            }

            if lhs.occurrenceStartsAt != rhs.occurrenceStartsAt {
                return lhs.occurrenceStartsAt < rhs.occurrenceStartsAt
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
