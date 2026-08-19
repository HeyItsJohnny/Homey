import Combine
import Foundation

@MainActor
final class GlobalMealsExploreViewModel: ObservableObject {
    @Published private(set) var trendingMeals: [GlobalMeal] = []
    @Published private(set) var meals: [GlobalMeal] = []
    @Published private(set) var selectedDetail: GlobalMealDetail?
    @Published private(set) var addStates: [UUID: GlobalMealAddState] = [:]
    @Published private(set) var isLoadingInitial = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var hasMorePages = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var addedHomeMealId: UUID?
    @Published var filters = GlobalMealsFilters() {
        didSet { resetAndReloadForActiveHome() }
    }
    @Published var searchText = "" {
        didSet { scheduleDebouncedReload() }
    }

    private let service: GlobalMealsServicing
    private let pageSize = 24
    private var activeHomeId: UUID?
    private var selectedMealType: MealType?
    private var page = 0
    private var loadedMealIds: Set<UUID> = []
    private var homeMealIdsByGlobalMealId: [UUID: UUID] = [:]
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var importRefreshTask: Task<Void, Never>?

    init(service: GlobalMealsServicing? = nil) {
        self.service = service ?? GlobalMealsService()
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
        importRefreshTask?.cancel()
    }

    func configure(homeId: UUID?, selectedMealType: MealType?) {
        let didChangeScope = activeHomeId != homeId || self.selectedMealType != selectedMealType
        activeHomeId = homeId
        self.selectedMealType = selectedMealType

        guard didChangeScope else { return }
        resetAndReloadForActiveHome()
    }

    func reload() {
        resetAndReloadForActiveHome()
    }

    func refreshAfterGlobalRecipeImport(globalRecipeId: UUID, homeMealId: UUID?, homeId: UUID?, selectedMealType: MealType?) {
        guard let resolvedHomeId = activeHomeId ?? homeId else { return }
        activeHomeId = resolvedHomeId
        self.selectedMealType = selectedMealType

        loadTask?.cancel()
        searchTask?.cancel()
        importRefreshTask?.cancel()

        importRefreshTask = Task { [weak self] in
            await self?.refreshAfterImport(globalRecipeId: globalRecipeId, homeMealId: homeMealId)
        }
    }

    func loadNextPageIfNeeded(currentMeal: GlobalMeal?) {
        guard let currentMeal else { return }
        guard meals.suffix(6).contains(where: { $0.id == currentMeal.id }) else { return }
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoadingInitial, !isLoadingMore, hasMorePages else { return }
        guard activeHomeId != nil else { return }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadPage(reset: false)
        }
    }

    func loadDetail(for meal: GlobalMeal) async {
        isLoadingDetail = true
        errorMessage = nil
        defer { isLoadingDetail = false }

        do {
            selectedDetail = try await service.fetchDetail(globalMealId: meal.id)
        } catch {
            errorMessage = "Homey couldn't load this community recipe."
        }
    }

    func dismissDetail() {
        selectedDetail = nil
    }

    func addToHome(_ meal: GlobalMeal) async -> GlobalMealAddResult? {
        guard let activeHomeId else {
            errorMessage = "Select a Home before adding recipes."
            return nil
        }

        if let existingHomeMealId = homeMealIdsByGlobalMealId[meal.id] {
            addedHomeMealId = existingHomeMealId
            successMessage = "Already in Your Recipes"
            return .alreadyExists(homeMealId: existingHomeMealId)
        }

        guard addStates[meal.id] != .adding else { return nil }
        addStates[meal.id] = .adding
        errorMessage = nil
        successMessage = nil

        do {
            #if DEBUG
            print("Add to Home started")
            print("selected_home_id: \(activeHomeId.uuidString)")
            print("global_recipe_id: \(meal.id.uuidString)")
            #endif

            let result = try await service.addGlobalMealToHome(globalMeal: meal, homeId: activeHomeId)
            let homeMealId = result.homeMealId
            homeMealIdsByGlobalMealId[meal.id] = homeMealId
            addStates[meal.id] = .added(homeMealId: homeMealId)
            addedHomeMealId = homeMealId
            successMessage = result.photoCopyFailed ? "Recipe added, but its photo could not be copied." : "Added to Your Recipes"

            #if DEBUG
            print("Home recipes refreshed after global add")
            print("selected_home_id: \(activeHomeId.uuidString)")
            print("returned_home_meal_id: \(homeMealId.uuidString)")
            #endif

            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            return result
        } catch {
            addStates[meal.id] = .available
            errorMessage = "Homey couldn't add this recipe to your Home."
            return nil
        }
    }

    func clearFeedback() {
        successMessage = nil
        errorMessage = nil
    }

    private func resetAndReloadForActiveHome() {
        searchTask?.cancel()
        loadTask?.cancel()
        page = 0
        loadedMealIds = []
        meals = []
        hasMorePages = true
        selectedDetail = nil
        errorMessage = nil
        successMessage = nil
        addedHomeMealId = nil
        addStates = [:]

        guard activeHomeId != nil else {
            trendingMeals = []
            isLoadingInitial = false
            isLoadingMore = false
            return
        }

        loadTask = Task { [weak self] in
            await self?.loadInitialData()
        }
    }

    private func scheduleDebouncedReload() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.resetAndReloadForActiveHome()
        }
    }

    private func refreshAfterImport(globalRecipeId: UUID, homeMealId: UUID?) async {
        guard activeHomeId != nil else { return }

        let currentPage = page
        let browseCountBefore = meals.count
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let homeMealId {
            homeMealIdsByGlobalMealId[globalRecipeId] = homeMealId
            addStates[globalRecipeId] = .added(homeMealId: homeMealId)
        }

        #if DEBUG
        print("Explore refresh after import started")
        print("refresh_after_import_started: true")
        print("global_recipe_id: \(globalRecipeId.uuidString)")
        if let homeMealId { print("home_meal_id: \(homeMealId.uuidString)") }
        print("current_sort: \(filters.sort.title)")
        print("current_filters: cuisine=\(filters.cuisine), maximum_total_time=\(filters.maximumTotalTimeMinutes.map(String.init) ?? "none")")
        print("current_search: \(searchText)")
        print("current_page: \(currentPage)")
        print("in_home_state_updated: \(homeMealId != nil)")
        #endif

        do {
            async let fetchedMeal = service.fetchGlobalMeal(globalMealId: globalRecipeId)
            async let fetchedTrending = service.fetchTrending(limit: 10)
            async let fetchedFirstPage = service.fetchMeals(
                page: 0,
                pageSize: pageSize,
                filters: filters,
                selectedMealType: selectedMealType,
                searchText: searchText
            )

            let importedMeal = try await fetchedMeal
            let firstPageMeals = try await fetchedFirstPage
            let latestTrendingMeals = try await fetchedTrending

            guard !Task.isCancelled else { return }

            trendingMeals = latestTrendingMeals
            mergeMeals(firstPageMeals)
            mergeGlobalRecipe(importedMeal, normalizedSearch: normalizedSearch)
            refreshPaginationAfterImport(firstPageCount: firstPageMeals.count, previousPage: currentPage)
            refreshAddStates()

            #if DEBUG
            print("Explore refresh after import completed")
            print("new_recipe_fetched: true")
            print("merged_recipe_id: \(importedMeal.id.uuidString)")
            print("browse_count_before: \(browseCountBefore)")
            print("browse_count_after: \(meals.count)")
            print("trending_updated: true")
            print("refresh_after_import_completed: true")
            #endif
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Homey couldn't load community recipes."
            #if DEBUG
            print("Explore refresh after import failed")
            print("global_recipe_id: \(globalRecipeId.uuidString)")
            print(String(reflecting: error))
            #endif
        }
    }

    private func loadInitialData() async {
        isLoadingInitial = true
        isLoadingMore = false
        defer { isLoadingInitial = false }

        do {
            guard let activeHomeId else { return }
            async let loadedTrending = service.fetchTrending(limit: 10)
            async let loadedHomeMeals = service.fetchExistingHomeMeals(homeId: activeHomeId)

            trendingMeals = try await loadedTrending
            let homeMeals = try await loadedHomeMeals
            homeMealIdsByGlobalMealId = Dictionary(uniqueKeysWithValues: homeMeals.compactMap { meal in
                guard let originId = meal.globalOriginIdForExplore else { return nil }
                return (originId, meal.id)
            })
            refreshAddStates()
            await loadPage(reset: true)
        } catch {
            trendingMeals = []
            meals = []
            errorMessage = "Homey couldn't load community recipes."
        }
    }

    private func loadPage(reset: Bool) async {
        if reset {
            page = 0
            loadedMealIds = []
            meals = []
            hasMorePages = true
        }

        guard hasMorePages else { return }

        if reset {
            isLoadingInitial = true
        } else {
            isLoadingMore = true
        }
        defer {
            if reset {
                isLoadingInitial = false
            } else {
                isLoadingMore = false
            }
        }

        do {
            let loadedMeals = try await service.fetchMeals(
                page: page,
                pageSize: pageSize,
                filters: filters,
                selectedMealType: selectedMealType,
                searchText: searchText
            )
            let uniqueMeals = loadedMeals.filter { loadedMealIds.insert($0.id).inserted }
            meals.append(contentsOf: uniqueMeals)
            refreshAddStates()
            hasMorePages = loadedMeals.count == pageSize
            page += 1
        } catch {
            if reset { meals = [] }
            errorMessage = "Homey couldn't load community recipes."
        }
    }

    private func mergeGlobalRecipe(_ meal: GlobalMeal, normalizedSearch: String) {
        let matchesCurrentQuery = meal.matchesExploreFilters(filters)
            && meal.matchesSelectedMealType(selectedMealType)
            && meal.matchesExploreSearch(normalizedSearch)

        guard matchesCurrentQuery else {
            meals.removeAll { $0.id == meal.id }
            loadedMealIds.remove(meal.id)
            return
        }

        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }

        meals = sortedMeals(removingDuplicatesFrom: meals)
        loadedMealIds = Set(meals.map(\.id))
    }

    private func mergeMeals(_ incomingMeals: [GlobalMeal]) {
        guard !incomingMeals.isEmpty else { return }

        var mealsById = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
        for meal in incomingMeals {
            mealsById[meal.id] = meal
        }

        meals = sortedMeals(removingDuplicatesFrom: Array(mealsById.values))
        loadedMealIds = Set(meals.map(\.id))
    }

    private func sortedMeals(removingDuplicatesFrom meals: [GlobalMeal]) -> [GlobalMeal] {
        var seenMealIds: Set<UUID> = []
        return meals
            .filter { seenMealIds.insert($0.id).inserted }
            .sorted(by: sortMealsForCurrentFilter)
    }

    private func sortMealsForCurrentFilter(_ lhs: GlobalMeal, _ rhs: GlobalMeal) -> Bool {
        switch filters.sort {
        case .mostSaved:
            if lhs.saveCount != rhs.saveCount { return lhs.saveCount > rhs.saveCount }
            return lhs.updatedAt > rhs.updatedAt
        case .newest:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.updatedAt > rhs.updatedAt
        case .recentlyUpdated:
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.createdAt > rhs.createdAt
        case .fastest:
            switch (lhs.resolvedTotalTimeMinutes, rhs.resolvedTotalTimeMinutes) {
            case let (lhsTime?, rhsTime?) where lhsTime != rhsTime:
                return lhsTime < rhsTime
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private func refreshPaginationAfterImport(firstPageCount: Int, previousPage: Int) {
        if previousPage <= 1 {
            page = max(1, previousPage)
            hasMorePages = firstPageCount == pageSize
        } else {
            page = previousPage
        }
    }

    private func refreshAddStates() {
        let allVisibleMeals = trendingMeals + meals
        for meal in allVisibleMeals {
            if let homeMealId = homeMealIdsByGlobalMealId[meal.id] {
                addStates[meal.id] = .added(homeMealId: homeMealId)
            } else if addStates[meal.id] != .adding {
                addStates[meal.id] = .available
            }
        }
    }
}

private extension GlobalMealAddResult {
    var homeMealId: UUID {
        switch self {
        case .added(let homeMealId), .alreadyExists(let homeMealId), .addedPhotoCopyFailed(let homeMealId):
            return homeMealId
        }
    }

    var photoCopyFailed: Bool {
        if case .addedPhotoCopyFailed = self { return true }
        return false
    }
}
