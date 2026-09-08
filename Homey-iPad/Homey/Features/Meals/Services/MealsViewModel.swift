import Combine
import Foundation

@MainActor
final class MealsViewModel: ObservableObject {
    @Published private(set) var meals: [Meal] = []
    @Published private(set) var featuredMeals: [Meal] = []
    @Published private(set) var favoriteMeals: [Meal] = []
    @Published private(set) var collections: [MealCollection] = []
    @Published var selectedMealType: MealType? {
        didSet { applyFilters() }
    }
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let mealService: MealServicing
    private var activeHomeId: UUID?
    private var allMeals: [Meal] = []
    private var favoriteMealIds: Set<UUID> = []
    private var loadTask: Task<Void, Never>?
    private var realtimeReloadTask: Task<Void, Never>?
    private var realtimeSubscription: MealRealtimeSubscription?

    init(mealService: MealServicing? = nil) {
        self.mealService = mealService ?? MealService()
    }

    deinit {
        loadTask?.cancel()
        realtimeReloadTask?.cancel()
        let subscription = realtimeSubscription
        Task { @MainActor in
            await subscription?.cancel()
        }
    }

    func load(homeId: UUID?) {
        guard let homeId else {
            Task { await clear() }
            return
        }

        if activeHomeId != homeId {
            Task {
                await stopRealtimeUpdates()
                clearMealData()
                activeHomeId = homeId
                await startRealtimeUpdates(homeId: homeId)
                scheduleLoad(homeId: homeId)
            }
        } else {
            scheduleLoad(homeId: homeId)
        }
    }

    func reload() {
        guard let activeHomeId else {
            Task { await clear() }
            return
        }
        scheduleLoad(homeId: activeHomeId)
    }

    func meal(id: UUID) -> Meal? {
        allMeals.first { $0.id == id }
    }

    var unfilteredMeals: [Meal] {
        allMeals
    }

    func replaceMeal(_ meal: Meal) {
        guard activeHomeId == nil || activeHomeId == meal.homeId else {
            return
        }
        replaceMealLocally(meal)
    }

    func refreshMeal(id: UUID, homeId: UUID? = nil) async -> Meal? {
        do {
            let refreshedMeal = try await mealService.fetchMeal(id: id)
            let expectedHomeId = homeId ?? activeHomeId
            guard expectedHomeId == nil || expectedHomeId == refreshedMeal.homeId else {
                #if DEBUG
                print("Ignoring refreshed meal \(id.uuidString) for non-selected Home \(refreshedMeal.homeId.uuidString); expected \(expectedHomeId?.uuidString ?? "nil")")
                #endif
                return nil
            }
            replaceMealLocally(refreshedMeal)
            return refreshedMeal
        } catch {
            #if DEBUG
            print("Unable to refresh saved meal \(id.uuidString): \(String(reflecting: error))")
            #endif
            return nil
        }
    }

    func clear() async {
        loadTask?.cancel()
        await stopRealtimeUpdates()
        activeHomeId = nil
        clearMealData()
    }

    func stopRealtimeUpdates() async {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
        await realtimeSubscription?.cancel()
        realtimeSubscription = nil
    }

    func toggleFavorite(_ meal: Meal, permissions: HomePermissions) async {
        guard permissions.meals.canFavorite else {
            errorMessage = MealServiceError.permissionDenied.localizedDescription
            return
        }

        guard !isSaving else {
            return
        }

        let wasFavorite = favoriteMealIds.contains(meal.id)
        setFavoriteLocally(meal, isFavorite: !wasFavorite)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await mealService.setFavorite(mealId: meal.id, isFavorite: !wasFavorite)
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
        } catch {
            setFavoriteLocally(meal, isFavorite: wasFavorite)
            errorMessage = error.localizedDescription
        }
    }

    func archiveMeal(_ meal: Meal, permissions: HomePermissions) async -> Bool {
        guard permissions.meals.canArchive else {
            errorMessage = MealServiceError.permissionDenied.localizedDescription
            return false
        }

        guard !isSaving else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await mealService.archiveMeal(id: meal.id)
            removeMealLocally(meal)
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteMeal(_ meal: Meal, permissions: HomePermissions) async -> Bool {
        guard permissions.meals.canDelete else {
            errorMessage = MealServiceError.permissionDenied.localizedDescription
            return false
        }

        guard !isSaving else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await mealService.deleteMeal(id: meal.id)
            removeMealLocally(meal)
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteCollection(_ collection: MealCollection, permissions: HomePermissions) async -> Bool {
        guard permissions.meals.canDeleteCollections else {
            errorMessage = MealServiceError.permissionDenied.localizedDescription
            return false
        }

        guard !isSaving else {
            return false
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await mealService.deleteCollection(id: collection.id)
            collections.removeAll { $0.id == collection.id }
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func isFavorite(_ meal: Meal) -> Bool {
        favoriteMealIds.contains(meal.id)
    }

    private func scheduleLoad(homeId: UUID) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadMealData(homeId: homeId)
        }
    }

    private func loadMealData(homeId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedMeals = mealService.fetchMeals(homeId: homeId)
            async let loadedCollections = mealService.fetchCollections(homeId: homeId)

            let resolvedMeals = try await loadedMeals.filter { !$0.isArchived }
            let resolvedCollections = try await loadedCollections
            let resolvedFavorites = await loadFavoriteMealsIfAvailable(homeId: homeId)

            guard !Task.isCancelled,
                  activeHomeId == homeId else {
                return
            }

            allMeals = mergedWithNewerLocalMeals(resolvedMeals).sortedForMeals()
            favoriteMealIds = Set(resolvedFavorites.map(\.id))
            favoriteMeals = allMeals.filter { favoriteMealIds.contains($0.id) }.sortedForMeals()
            collections = resolvedCollections
            applyFilters()
        } catch {
            guard !Task.isCancelled,
                  activeHomeId == homeId else {
                return
            }

            errorMessage = error.localizedDescription
            meals = []
            featuredMeals = []
            favoriteMeals = []
            collections = []
            allMeals = []
            favoriteMealIds = []
        }
    }

    private func loadFavoriteMealsIfAvailable(homeId: UUID) async -> [Meal] {
        do {
            return try await mealService.fetchFavoriteMeals(homeId: homeId).filter { !$0.isArchived }
        } catch {
            #if DEBUG
            print("Unable to load favorite meals for Home \(homeId.uuidString): \(String(reflecting: error))")
            #endif
            return []
        }
    }

    private func applyFilters() {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredMeals = allMeals.filter { meal in
            if let selectedMealType, !meal.mealTypes.contains(selectedMealType) {
                return false
            }

            guard !normalizedSearch.isEmpty else {
                return true
            }

            return meal.matchesMealsViewSearch(normalizedSearch)
        }
        meals = filteredMeals
        featuredMeals = featuredMeals(from: filteredMeals)
    }

    private func setFavoriteLocally(_ meal: Meal, isFavorite: Bool) {
        if isFavorite {
            favoriteMealIds.insert(meal.id)
            if !favoriteMeals.contains(where: { $0.id == meal.id }) {
                favoriteMeals.append(meal)
            }
        } else {
            favoriteMealIds.remove(meal.id)
            favoriteMeals.removeAll { $0.id == meal.id }
        }
        favoriteMeals = favoriteMeals.sortedForMeals()
        applyFilters()
    }

    private func removeMealLocally(_ meal: Meal) {
        allMeals.removeAll { $0.id == meal.id }
        meals.removeAll { $0.id == meal.id }
        favoriteMeals.removeAll { $0.id == meal.id }
        favoriteMealIds.remove(meal.id)
        applyFilters()
    }

    private func replaceMealLocally(_ meal: Meal) {
        if meal.isArchived {
            removeMealLocally(meal)
            return
        }

        if let index = allMeals.firstIndex(where: { $0.id == meal.id }) {
            allMeals[index] = meal
        } else {
            allMeals.append(meal)
        }

        if favoriteMealIds.contains(meal.id) {
            if let favoriteIndex = favoriteMeals.firstIndex(where: { $0.id == meal.id }) {
                favoriteMeals[favoriteIndex] = meal
            } else {
                favoriteMeals.append(meal)
            }
            favoriteMeals = favoriteMeals.sortedForMeals()
        }

        allMeals = allMeals.sortedForMeals()
        applyFilters()
    }

    private func mergedWithNewerLocalMeals(_ incomingMeals: [Meal]) -> [Meal] {
        let currentMealsByID = Dictionary(uniqueKeysWithValues: allMeals.map { ($0.id, $0) })
        return incomingMeals.map { incomingMeal in
            guard let currentMeal = currentMealsByID[incomingMeal.id],
                  currentMeal.updatedAt > incomingMeal.updatedAt else {
                return incomingMeal
            }
            return currentMeal
        }
    }

    private func featuredMeals(from sourceMeals: [Meal]) -> [Meal] {
        let favoriteMealsByRecency = sourceMeals
            .filter { favoriteMealIds.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let remainingMealsByRecency = sourceMeals
            .filter { !favoriteMealIds.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return Array((favoriteMealsByRecency + remainingMealsByRecency).prefix(4))
    }

    private func startRealtimeUpdates(homeId: UUID) async {
        do {
            realtimeSubscription = try await mealService.subscribeToMealChanges(homeId: homeId) { [weak self] in
                self?.scheduleRealtimeReload()
            }
        } catch {
            #if DEBUG
            print("Meals Realtime unavailable: \(String(reflecting: error))")
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

            await self?.loadMealDataForActiveHome()
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
        }
    }

    private func loadMealDataForActiveHome() async {
        guard let activeHomeId else {
            return
        }
        await loadMealData(homeId: activeHomeId)
    }

    private func clearMealData() {
        allMeals = []
        meals = []
        featuredMeals = []
        favoriteMeals = []
        collections = []
        favoriteMealIds = []
        errorMessage = nil
        isLoading = false
        isSaving = false
    }
}

extension Notification.Name {
    static let homeyMealsDidChange = Notification.Name("homeyMealsDidChange")
}

private extension Meal {
    func matchesMealsViewSearch(_ normalizedSearch: String) -> Bool {
        [name, description, cuisine, notes, sourceName]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedSearch) }
            || tags.contains { $0.lowercased().contains(normalizedSearch) }
            || mealTypes.contains { $0.displayName.lowercased().contains(normalizedSearch) }
    }
}
