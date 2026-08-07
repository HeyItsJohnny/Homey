import Combine
import Foundation

@MainActor
final class DashboardCalendarViewModel: ObservableObject {
    @Published private(set) var eventsTodayCount = 0
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let calendarService: CalendarService
    private var activeHomeId: UUID?
    private var loadTask: Task<Void, Never>?
    private var realtimeReloadTask: Task<Void, Never>?
    private var realtimeSubscription: CalendarRealtimeSubscription?
    private let calendar: Calendar

    init(calendarService: CalendarService? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.calendarService = calendarService ?? CalendarService(calendar: calendar)
        self.calendar = calendar
    }

    func load(homeId: UUID?) {
        guard let homeId else {
            Task { await clear() }
            return
        }

        if activeHomeId != homeId {
            Task {
                await stopRealtimeUpdates()
                clearCalendarData()
                activeHomeId = homeId
                await startRealtimeUpdates(homeId: homeId)
                scheduleLoad(homeId: homeId)
            }
        } else {
            scheduleLoad(homeId: homeId)
        }
    }

    func reload() {
        load(homeId: activeHomeId)
    }

    func clear() async {
        loadTask?.cancel()
        await stopRealtimeUpdates()
        activeHomeId = nil
        clearCalendarData()
    }

    func stopRealtimeUpdates() async {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
        await realtimeSubscription?.cancel()
        realtimeSubscription = nil
    }

    private func scheduleLoad(homeId: UUID) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadCalendarData(homeId: homeId)
        }
    }

    private func loadCalendarData(homeId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let now = Date()
            async let todayEvents = calendarService.fetchEventsForDay(homeId: homeId, date: now)
            async let upcoming = calendarService.fetchUpcomingEvents(homeId: homeId, from: now, limit: 3)
            async let loadedCategories = calendarService.fetchCategories(homeId: homeId)

            let loadedTodayEvents = try await todayEvents
            let loadedUpcomingEvents = try await upcoming
            let resolvedCategories = try await loadedCategories

            guard !Task.isCancelled else {
                return
            }

            eventsTodayCount = loadedTodayEvents
                .filter { $0.overlapsDay(now, calendar: calendar) }
                .count
            upcomingEvents = loadedUpcomingEvents
            categories = resolvedCategories
        } catch {
            guard !Task.isCancelled else {
                return
            }

            errorMessage = error.localizedDescription
            eventsTodayCount = 0
            upcomingEvents = []
        }
    }

    private func startRealtimeUpdates(homeId: UUID) async {
        do {
            realtimeSubscription = try await calendarService.subscribeToCalendarChanges(homeId: homeId) { [weak self] in
                self?.scheduleRealtimeReload()
            }
        } catch {
            #if DEBUG
            print("Dashboard calendar Realtime unavailable: \(String(reflecting: error))")
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

            await self?.loadCalendarDataForActiveHome()
        }
    }

    private func loadCalendarDataForActiveHome() async {
        guard let activeHomeId else {
            return
        }

        await loadCalendarData(homeId: activeHomeId)
    }

    private func clearCalendarData() {
        eventsTodayCount = 0
        upcomingEvents = []
        categories = []
        errorMessage = nil
        isLoading = false
    }
}

extension Notification.Name {
    static let homeyCalendarEventsDidChange = Notification.Name("homeyCalendarEventsDidChange")
}

enum HomeyCalendarRefreshReason {
    static let userInfoKey = "reason"
    static let calendarEventsChanged = "calendar_events_changed"
    static let choreEditSaved = "chore_edit_saved"
}
