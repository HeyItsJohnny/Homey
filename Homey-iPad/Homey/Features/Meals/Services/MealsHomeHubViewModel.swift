import Combine
import Foundation

@MainActor
final class MealsHomeHubViewModel: ObservableObject {
    static let visibleMealTypes: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    @Published private(set) var selectedDate = Date()
    @Published private(set) var itemsByType: [MealType: [MealPlanItem]] = [:]
    @Published private(set) var homeMeals: [Meal] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var deletingEntryIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?

    private let entryService = MealPlanEntryService()
    private let mealService = MealService()
    private var calendar = Calendar(identifier: .gregorian)
    private var activeHomeID: UUID?
    private var activeDateKey = ""
    private var activeLoadID = UUID()

    init() {
        calendar.timeZone = .autoupdatingCurrent
        selectedDate = calendar.startOfDay(for: Date())
    }

    func configure(homeID: UUID?, timezoneIdentifier: String) async {
        guard let homeID else {
            reset()
            return
        }

        var nextCalendar = Calendar(identifier: .gregorian)
        nextCalendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .autoupdatingCurrent

        let homeChanged = activeHomeID != homeID
        if homeChanged {
            selectedDate = nextCalendar.startOfDay(for: Date())
            itemsByType = [:]
            homeMeals = []
            deletingEntryIDs = []
            errorMessage = nil
        }

        calendar = nextCalendar
        let nextDateKey = Self.dateKey(for: selectedDate, calendar: calendar)
        let contextChanged = homeChanged || activeDateKey != nextDateKey
        activeHomeID = homeID
        activeDateKey = nextDateKey

        if contextChanged || (itemsByType.isEmpty && homeMeals.isEmpty) {
            await refreshMealPlanner()
        }
    }

    func moveSelectedDate(by offset: Int) async {
        guard activeHomeID != nil,
              let nextDate = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: selectedDate)) else {
            return
        }

        selectedDate = nextDate
        activeDateKey = Self.dateKey(for: nextDate, calendar: calendar)
        itemsByType = [:]
        errorMessage = nil
        await refreshMealPlanner()
    }

    func returnToToday() async {
        let today = calendar.startOfDay(for: Date())
        guard !calendar.isDate(selectedDate, inSameDayAs: today) else { return }
        selectedDate = today
        activeDateKey = Self.dateKey(for: today, calendar: calendar)
        itemsByType = [:]
        errorMessage = nil
        await refreshMealPlanner()
    }

    func refreshMealPlanner() async {
        errorMessage = nil
        guard let homeID = activeHomeID else { return }

        let requestedDate = Self.dateKey(for: selectedDate, calendar: calendar)
        activeDateKey = requestedDate
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        defer {
            if activeLoadID == loadID { isLoading = false }
        }

        do {
            async let loadedEntries = entryService.fetchEntries(homeID: homeID, date: requestedDate)
            async let loadedMeals = mealService.fetchMeals(homeId: homeID)
            let (entries, meals) = try await (loadedEntries, loadedMeals)
            try Task.checkCancellation()
            guard activeLoadID == loadID,
                  activeHomeID == homeID,
                  Self.dateKey(for: selectedDate, calendar: calendar) == requestedDate else {
                return
            }

            let mealsByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
            let items = entries.compactMap { entry in
                mealsByID[entry.mealID].map { MealPlanItem(entry: entry, meal: $0) }
            }

            homeMeals = meals
            itemsByType = Dictionary(grouping: items, by: { $0.entry.mealType })
                .mapValues(Self.sortItems)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeLoadID == loadID else { return }
            errorMessage = "We couldn't refresh the meal plan for this date."
        }
    }

    func addMeal(_ meal: Meal, to mealType: MealType) async -> Bool {
        guard let homeID = activeHomeID, !isSaving else { return false }
        let requestedDate = Self.dateKey(for: selectedDate, calendar: calendar)
        let nextSortOrder = (items(for: mealType).map(\.entry.sortOrder).max() ?? -1) + 1
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await entryService.saveEntry(
                homeID: homeID,
                mealID: meal.id,
                date: requestedDate,
                mealType: mealType,
                sortOrder: nextSortOrder
            )
            try Task.checkCancellation()
            guard activeHomeID == homeID,
                  Self.dateKey(for: selectedDate, calendar: calendar) == requestedDate else {
                return false
            }
            await refreshMealPlanner()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled, activeHomeID == homeID else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeMeal(_ item: MealPlanItem) async {
        guard let homeID = activeHomeID, !deletingEntryIDs.contains(item.id) else { return }
        let requestedDate = Self.dateKey(for: selectedDate, calendar: calendar)
        deletingEntryIDs.insert(item.id)
        errorMessage = nil
        defer { deletingEntryIDs.remove(item.id) }

        do {
            try await entryService.deleteEntry(homeID: homeID, entryID: item.id)
            try Task.checkCancellation()
            guard activeHomeID == homeID,
                  Self.dateKey(for: selectedDate, calendar: calendar) == requestedDate else {
                return
            }
            await refreshMealPlanner()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeHomeID == homeID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func items(for mealType: MealType) -> [MealPlanItem] {
        itemsByType[mealType] ?? []
    }

    func isDeleting(_ item: MealPlanItem) -> Bool {
        deletingEntryIDs.contains(item.id)
    }

    var isViewingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: Date())
    }

    var selectedDateLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    private func reset() {
        activeHomeID = nil
        activeDateKey = ""
        activeLoadID = UUID()
        selectedDate = calendar.startOfDay(for: Date())
        itemsByType = [:]
        homeMeals = []
        deletingEntryIDs = []
        isLoading = false
        isSaving = false
        errorMessage = nil
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func sortItems(_ items: [MealPlanItem]) -> [MealPlanItem] {
        items.sorted {
            if $0.entry.sortOrder != $1.entry.sortOrder {
                return $0.entry.sortOrder < $1.entry.sortOrder
            }
            return $0.entry.id.uuidString < $1.entry.id.uuidString
        }
    }
}
