import Combine
import Foundation

@MainActor
final class HomeCalendarMealsViewModel: ObservableObject {
    @Published private(set) var plannedMeals: [PlannedMeal] = []
    @Published private(set) var meals: [Meal] = []
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var visibleWeekAnchor: Date
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let plannerService: MealPlannerService
    private let mealService: MealServicing
    private var calendar: Calendar
    private var activeHomeId: UUID?
    private var activeWeekStartsOn: Int?
    private var activeTimezone: String?
    private var notificationTask: Task<Void, Never>?

    init(
        plannerService: MealPlannerService? = nil,
        mealService: MealServicing? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.plannerService = plannerService ?? MealPlannerService(calendar: calendar)
        self.mealService = mealService ?? MealService()
        self.calendar = calendar
        visibleWeekAnchor = calendar.startOfDay(for: Date())
        Self.configureFormatters(calendar: calendar)

        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                await self?.reload()
            }
        }
    }

    deinit {
        notificationTask?.cancel()
    }

    func configure(homeId: UUID?, weekStartsOn: Int?, timezone: String?) async {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)
        plannerService.configureWeekStart(weekStartsOn)
        plannerService.configureTimezone(timezone)

        if activeHomeId != homeId {
            visibleWeekAnchor = calendar.startOfDay(for: Date())
            plannedMeals = []
            meals = []
            categories = []
        }

        activeHomeId = homeId
        activeWeekStartsOn = weekStartsOn
        activeTimezone = timezone

        await reload()
    }

    func reload() async {
        guard let activeHomeId else {
            plannedMeals = []
            meals = []
            categories = []
            errorMessage = "Choose a Home before planning meals."
            return
        }

        guard let range = visibleWeekRange else {
            errorMessage = MealPlannerServiceError.invalidDateRange.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedPlannedMeals = plannerService.fetchPlannedMeals(homeId: activeHomeId, startDate: range.start, endDate: range.end)
            async let loadedMeals = mealService.fetchMeals(homeId: activeHomeId)
            async let loadedCategories = plannerService.fetchCategories(homeId: activeHomeId)
            let (plannedMeals, meals, categories) = try await (loadedPlannedMeals, loadedMeals, loadedCategories)
            self.plannedMeals = plannedMeals
            self.meals = meals
            self.categories = categories
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveToPreviousWeek() {
        moveWeek(by: -1)
    }

    func moveToNextWeek() {
        moveWeek(by: 1)
    }

    func moveToToday() {
        visibleWeekAnchor = calendar.startOfDay(for: Date())
        Task { await reload() }
    }

    func weekDays() -> [Date] {
        guard let range = visibleWeekRange else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
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
            let monthYear = Self.monthYearFormatter.string(from: range.start)
            let startDay = Self.dayFormatter.string(from: range.start)
            let endDay = Self.dayFormatter.string(from: inclusiveEnd)
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

    func plannedMeals(on day: Date, mealType: MealType) -> [PlannedMeal] {
        plannedMeals
            .filter { plannedMeal in
                calendar.isDate(plannedMeal.startsAt, inSameDayAs: day) && plannedMeal.mealType == mealType
            }
            .sortedForMealPlanner()
    }

    func addMeal(_ meal: Meal, to date: Date, mealType: MealType, permissions: HomePermissions) async {
        guard permissions.meals.canPlanMeals else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard let activeHomeId, !isSaving else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let plannedMeal = try await plannerService.createPlannedMeal(
                homeId: activeHomeId,
                meal: meal,
                mealType: mealType,
                date: date,
                plannedServings: meal.servings,
                mealNotes: nil,
                timezone: activeTimezone
            )
            replace(plannedMeal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveMeal(_ plannedMeal: PlannedMeal, to date: Date, mealType: MealType, permissions: HomePermissions) async {
        guard permissions.meals.canPlanMeals else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let moved = try await plannerService.movePlannedMeal(plannedMeal, to: date, mealType: mealType, timezone: activeTimezone)
            replace(moved)
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    func removeMeal(_ plannedMeal: PlannedMeal, permissions: HomePermissions) async {
        guard permissions.meals.canRemovePlannedMeals else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await plannerService.removePlannedMeal(calendarEventId: plannedMeal.calendarEventId)
            plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    func mealMatches(_ meal: Meal, mealType: MealType, searchText: String) -> Bool {
        let matchesMealType = meal.mealTypes.isEmpty || meal.mealTypes.contains(mealType)
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSearch.isEmpty else {
            return matchesMealType
        }

        return matchesMealType && meal.name.lowercased().contains(normalizedSearch)
    }

    private func moveWeek(by value: Int) {
        guard let next = calendar.date(byAdding: .weekOfYear, value: value, to: visibleWeekAnchor) else {
            return
        }
        visibleWeekAnchor = calendar.startOfDay(for: next)
        Task { await reload() }
    }

    private func replace(_ plannedMeal: PlannedMeal) {
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        plannedMeals.append(plannedMeal)
        plannedMeals = plannedMeals.sortedForMealPlanner()
    }

    private func configureWeekStart(_ weekStartsOn: Int?) {
        let firstWeekday = weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
        calendar.firstWeekday = firstWeekday
        Self.configureFormatters(calendar: calendar)
    }

    private func configureTimezone(_ timezone: String?) {
        if let timezone, let timeZone = TimeZone(identifier: timezone) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .autoupdatingCurrent
        }
        Self.configureFormatters(calendar: calendar)
    }

    private func startOfWeek(containing date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leadingDays, to: startOfDay) ?? startOfDay
    }

    private static let dayFormatter = DateFormatter()
    private static let monthYearFormatter = DateFormatter()
    private static let monthDayFormatter = DateFormatter()
    private static let monthDayYearFormatter = DateFormatter()

    private static func configureFormatters(calendar: Calendar) {
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "d"

        monthYearFormatter.calendar = calendar
        monthYearFormatter.timeZone = calendar.timeZone
        monthYearFormatter.dateFormat = "MMMM yyyy"

        monthDayFormatter.calendar = calendar
        monthDayFormatter.timeZone = calendar.timeZone
        monthDayFormatter.dateFormat = "MMMM d"

        monthDayYearFormatter.calendar = calendar
        monthDayYearFormatter.timeZone = calendar.timeZone
        monthDayYearFormatter.dateFormat = "MMMM d, yyyy"
    }
}
