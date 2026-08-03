import Combine
import Foundation

@MainActor
final class MealPlannerViewModel: ObservableObject {
    @Published private(set) var plannedMeals: [PlannedMeal] = []
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var visibleWeekAnchor: Date
    @Published private(set) var selectedDate: Date
    @Published var displayMode: MealPlannerDisplayMode = .weekly
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let service: MealPlannerService
    private var calendar: Calendar
    private var activeHomeId: UUID?
    private var activeTimezone: String?
    private var activeLoadRange: (start: Date, end: Date)?
    private var loadTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?

    init(service: MealPlannerService? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.service = service ?? MealPlannerService(calendar: calendar)
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        visibleWeekAnchor = today
        selectedDate = today
        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                await self?.reload()
            }
        }
    }

    deinit {
        loadTask?.cancel()
        notificationTask?.cancel()
    }

    func load(homeId: UUID?, weekStartsOn: Int?, timezone: String?) {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)
        activeTimezone = timezone
        activeLoadRange = nil

        guard let homeId else {
            clear()
            return
        }

        let today = calendar.startOfDay(for: Date())
        visibleWeekAnchor = today
        selectedDate = today

        if activeHomeId != homeId {
            activeHomeId = homeId
            plannedMeals = []
        }

        scheduleLoad(homeId: homeId)
    }

    func loadPreview(homeId: UUID?, weekStartsOn: Int?, timezone: String?) {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)
        activeTimezone = timezone
        activeLoadRange = upcomingPreviewRange

        guard let homeId else {
            clear()
            return
        }

        if activeHomeId != homeId {
            activeHomeId = homeId
            plannedMeals = []
            let today = calendar.startOfDay(for: Date())
            visibleWeekAnchor = today
            selectedDate = today
        }

        scheduleLoad(homeId: homeId)
    }

    func reload() async {
        guard let activeHomeId else {
            clear()
            return
        }
        if activeLoadRange != nil {
            activeLoadRange = upcomingPreviewRange
        }
        await loadPlannedMeals(homeId: activeHomeId)
    }

    func moveToPreviousWeek() {
        moveWeek(by: -1)
    }

    func moveToNextWeek() {
        moveWeek(by: 1)
    }

    func moveToToday() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        visibleWeekAnchor = today
        if let activeHomeId {
            scheduleLoad(homeId: activeHomeId)
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }

    func weekDays() -> [Date] {
        guard let range = visibleWeekRange else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: range.start)
        }
    }

    func upcomingPreviewDays(count: Int = 3) -> [Date] {
        let start = calendar.startOfDay(for: Date())
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    var visibleWeekRange: (start: Date, end: Date)? {
        let start = startOfWeek(containing: visibleWeekAnchor)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return nil
        }
        return (start, end)
    }

    var visibleWeekTitle: String {
        guard let range = visibleWeekRange,
              let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end) else {
            return "This Week"
        }

        if calendar.isDate(range.start, equalTo: inclusiveEnd, toGranularity: .month) {
            let startDay = Self.dayFormatter.string(from: range.start)
            let endDay = Self.dayFormatter.string(from: inclusiveEnd)
            let monthYear = Self.monthYearFormatter.string(from: range.start)
            return "\(monthYear) \(startDay)-\(endDay)"
        }

        if calendar.component(.year, from: range.start) == calendar.component(.year, from: inclusiveEnd) {
            return "\(Self.monthDayFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
        }

        return "\(Self.monthDayYearFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
    }

    var plannedMealCount: Int {
        Set(plannedMeals.map(\.id)).count
    }

    var uniqueRecipeCount: Int {
        Set(plannedMeals.map { $0.meal.id }).count
    }

    func plannedMeals(on day: Date, mealType: MealType? = nil) -> [PlannedMeal] {
        plannedMeals
            .filter { plannedMeal in
                calendar.isDate(plannedMeal.startsAt, inSameDayAs: day)
                    && (mealType == nil || plannedMeal.mealType == mealType)
            }
            .sortedForMealPlanner()
    }

    func mealsForMonth() -> [Date: [PlannedMeal]] {
        Dictionary(grouping: plannedMeals) { calendar.startOfDay(for: $0.startsAt) }
    }

    func addMeal(_ meal: Meal, to date: Date, mealType: MealType, servings: Decimal?, notes: String?, permissions: HomePermissions) async {
        guard permissions.meals.canView else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard let activeHomeId else { return }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let plannedMeal = try await service.createPlannedMeal(
                homeId: activeHomeId,
                meal: meal,
                mealType: mealType,
                date: date,
                plannedServings: servings,
                mealNotes: notes,
                timezone: activeTimezone
            )
            replacePlannedMeal(plannedMeal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveMeal(_ plannedMeal: PlannedMeal, to date: Date, mealType: MealType, permissions: HomePermissions) async {
        guard permissions.meals.canView else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        let previous = plannedMeals
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        defer { isSaving = false }

        do {
            let moved = try await service.movePlannedMeal(plannedMeal, to: date, mealType: mealType, timezone: activeTimezone)
            replacePlannedMeal(moved)
        } catch {
            plannedMeals = previous
            errorMessage = error.localizedDescription
        }
    }

    func removeMeal(_ plannedMeal: PlannedMeal, permissions: HomePermissions) async {
        guard permissions.meals.canView else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        let previous = plannedMeals
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        defer { isSaving = false }

        do {
            try await service.removePlannedMeal(calendarEventId: plannedMeal.calendarEventId)
        } catch {
            plannedMeals = previous
            errorMessage = error.localizedDescription
        }
    }

    private func configureWeekStart(_ weekStartsOn: Int?) {
        let firstWeekday = weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
        guard calendar.firstWeekday != firstWeekday else { return }
        calendar.firstWeekday = firstWeekday
        service.configureWeekStart(weekStartsOn)
        visibleWeekAnchor = selectedDate
    }

    private func configureTimezone(_ timezone: String?) {
        if let timezone, let timeZone = TimeZone(identifier: timezone) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .autoupdatingCurrent
        }
        service.configureTimezone(timezone)
    }

    private func clear() {
        loadTask?.cancel()
        activeHomeId = nil
        activeLoadRange = nil
        plannedMeals = []
        categories = []
        isLoading = false
        errorMessage = nil
    }

    private func scheduleLoad(homeId: UUID) {
        loadTask?.cancel()
        if activeLoadRange != nil {
            activeLoadRange = upcomingPreviewRange
        }
        loadTask = Task { [weak self] in
            await self?.loadPlannedMeals(homeId: homeId)
        }
    }

    private func loadPlannedMeals(homeId: UUID) async {
        guard let range = activeLoadRange ?? visibleWeekRange else {
            errorMessage = MealPlannerServiceError.invalidDateRange.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedMeals = service.fetchPlannedMeals(homeId: homeId, startDate: range.start, endDate: range.end)
            async let loadedCategories = service.fetchCategories(homeId: homeId)
            let loaded = try await loadedMeals
            let resolvedCategories = try await loadedCategories
            guard !Task.isCancelled, activeHomeId == homeId else { return }
            plannedMeals = loaded
            categories = resolvedCategories
        } catch {
            guard !Task.isCancelled, activeHomeId == homeId else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func moveWeek(by value: Int) {
        let selectedWeekdayOffset = daysFromStartOfWeek(to: selectedDate)
        let currentWeekStart = startOfWeek(containing: visibleWeekAnchor)
        guard let newWeekStart = calendar.date(byAdding: .weekOfYear, value: value, to: currentWeekStart),
              let newSelectedDate = calendar.date(byAdding: .day, value: selectedWeekdayOffset, to: newWeekStart) else {
            return
        }

        visibleWeekAnchor = newWeekStart
        selectedDate = calendar.startOfDay(for: newSelectedDate)
        if let activeHomeId {
            scheduleLoad(homeId: activeHomeId)
        }
    }

    private func replacePlannedMeal(_ plannedMeal: PlannedMeal) {
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        if let range = activeLoadRange ?? visibleWeekRange,
           plannedMeal.startsAt < range.end,
           plannedMeal.endsAt > range.start {
            plannedMeals.append(plannedMeal)
        }
        plannedMeals = plannedMeals.sortedForMealPlanner()
    }

    private var upcomingPreviewRange: (start: Date, end: Date)? {
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 3, to: start) else {
            return nil
        }
        return (start, end)
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()
}

enum MealPlannerDisplayMode: String, CaseIterable, Identifiable {
    case weekly
    case monthly
    case list

    static let visibleModes: [MealPlannerDisplayMode] = [.weekly, .list]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .list: "List"
        }
    }
}
