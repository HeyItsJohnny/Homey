import PhotosUI
import SwiftUI
import Combine

@MainActor final class MealsViewModel: ObservableObject {
    @Published var homeRecipes: [HomeyMeal] = []
    @Published private(set) var recipesRevision = 0
    @Published var favoriteIDs: Set<UUID> = []
    @Published var mealPlanItems: [MealPlanItem] = []
    @Published var isLoading = false
    @Published private(set) var isAutoPlanning = false
    @Published private(set) var isAddingMealPlanToGroceries = false
    @Published var autoPlanNotice: String?
    @Published var errorMessage: String?
    private let service = MealsService()
    private let groceryRepository = GroceryRepository()
    private var activeHomeID: UUID?
    private var activeLoadID = UUID()
    private var activePlanLoadID = UUID()
    private var pendingAutoPlanAttempt: AutoPlanAttempt?
    func load(home: HomeSummary) async {
        let loadID = UUID()
        activeLoadID = loadID
        activePlanLoadID = loadID
        if activeHomeID != home.id {
            homeRecipes = []
            mealPlanItems = []
            pendingAutoPlanAttempt = nil
            autoPlanNotice = nil
            errorMessage = nil
        }
        activeHomeID = home.id
        isLoading = true
        defer {
            if activeLoadID == loadID { isLoading = false }
        }
        do {
            async let h = service.homeRecipes(homeId: home.id)
            async let f = service.favoriteIDs()
            let week = Self.week(containing: Date(), home: home)
            async let p = service.mealPlanEntries(
                homeID: home.id,
                startDate: Self.localDate(week.start, home: home),
                endDate: Self.localDate(Self.inclusiveEnd(of: week, home: home), home: home)
            )
            let result = try await (h, f, p)
            guard activeLoadID == loadID, activeHomeID == home.id else { return }
            homeRecipes = result.0
            favoriteIDs = result.1
            if activePlanLoadID == loadID {
                mealPlanItems = Self.resolve(entries: result.2, recipes: result.0)
            }
            recipesRevision += 1
        } catch {
            guard activeLoadID == loadID, activeHomeID == home.id else { return }
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }
    func refreshRecipesAfterSave(home: HomeSummary) async throws {
        let loadedRecipes = try await service.homeRecipes(homeId: home.id)
        guard activeHomeID == home.id else { return }
        recipesRevision += 1
        homeRecipes = loadedRecipes
        mealPlanItems = Self.resolve(entries: mealPlanItems.map(\.entry), recipes: loadedRecipes)
    }
    func refreshPlan(home: HomeSummary, containing date: Date = Date()) async {
        let loadID = UUID()
        activePlanLoadID = loadID
        do {
            let week = Self.week(containing: date, home: home)
            async let entriesRequest = service.mealPlanEntries(
                homeID: home.id,
                startDate: Self.localDate(week.start, home: home),
                endDate: Self.localDate(Self.inclusiveEnd(of: week, home: home), home: home)
            )
            let recipes = homeRecipes.isEmpty ? try await service.homeRecipes(homeId: home.id) : homeRecipes
            let entries = try await entriesRequest
            guard activePlanLoadID == loadID, activeHomeID == home.id else { return }
            if homeRecipes.isEmpty {
                homeRecipes = recipes
                recipesRevision += 1
            }
            mealPlanItems = Self.resolve(entries: entries, recipes: recipes)
        } catch {
            guard activePlanLoadID == loadID, activeHomeID == home.id else { return }
            guard !Self.isCancellation(error) else { return }
            errorMessage = error.localizedDescription
        }
    }
    func toggleFavorite(_ meal: HomeyMeal) async { let next = !favoriteIDs.contains(meal.id); do { try await service.setFavorite(mealId:meal.id,isFavorite:next); if next { favoriteIDs.insert(meal.id) } else { favoriteIDs.remove(meal.id) } } catch { errorMessage=error.localizedDescription } }
    @discardableResult func schedule(_ meal: HomeyMeal,type:MealType,day:Date,home:HomeSummary) async -> Bool {
        do {
            let date = Self.localDate(day, home: home)
            let existing = try await service.mealPlanEntries(homeID: home.id, startDate: date, endDate: date)
            let nextSortOrder = (existing.filter { $0.mealType == type }.map(\.sortOrder).max() ?? -1) + 1
            try await service.saveMealPlanEntry(
                homeID: home.id,
                entryID: nil,
                mealID: meal.id,
                plannedDate: date,
                mealType: type,
                plannedServings: meal.servings,
                mealNotes: nil,
                sortOrder: nextSortOrder
            )
            await refreshPlan(home:home, containing:day)
            return true
        } catch {
            #if DEBUG
            print("Meal plan scheduling failed: \(String(reflecting: error))")
            #endif
            errorMessage = "Homey couldn't add this recipe to your meal plan. Please try again."
            return false
        }
    }
    @discardableResult func replace(_ item: MealPlanItem, with meal: HomeyMeal, type: MealType, day: Date, home: HomeSummary) async -> Bool {
        do {
            try await service.saveMealPlanEntry(
                homeID: home.id,
                entryID: item.entry.id,
                mealID: meal.id,
                plannedDate: Self.localDate(day, home: home),
                mealType: type,
                plannedServings: item.entry.plannedServings,
                mealNotes: item.entry.mealNotes,
                sortOrder: item.entry.sortOrder
            )
            await refreshPlan(home: home, containing: day)
            return true
        } catch {
            await refreshPlan(home: home, containing: day)
            errorMessage = "Homey couldn't change this planned recipe. Please try again."
            return false
        }
    }
    func move(_ item: MealPlanItem, to date: Date, home: HomeSummary) async -> Bool {
        do {
            let plannedDate = Self.localDate(date, home: home)
            let existing = try await service.mealPlanEntries(homeID: home.id, startDate: plannedDate, endDate: plannedDate)
            let nextSortOrder = (existing.filter { $0.mealType == item.entry.mealType }.map(\.sortOrder).max() ?? -1) + 1
            try await service.saveMealPlanEntry(
                homeID: home.id,
                entryID: item.entry.id,
                mealID: item.entry.mealID,
                plannedDate: plannedDate,
                mealType: item.entry.mealType,
                plannedServings: item.entry.plannedServings,
                mealNotes: item.entry.mealNotes,
                sortOrder: nextSortOrder
            )
            await refreshPlan(home: home, containing: date)
            return true
        } catch {
            errorMessage = "Homey couldn't move this planned recipe. Please try again."
            return false
        }
    }
    func remove(_ item: MealPlanItem,home:HomeSummary, containing date:Date = Date()) async { do { try await service.deleteMealPlanEntry(homeID: home.id, entryID: item.entry.id); await refreshPlan(home:home, containing:date) } catch { errorMessage=error.localizedDescription } }
    func mealPlanItemsForDay(home: HomeSummary, date: Date) async throws -> [MealPlanItem] {
        guard activeHomeID == home.id else {
            throw MealsError.message("The active Home changed. Reopen Leftovers and try again.")
        }
        let localDate = Self.localDate(date, home: home)
        async let entriesRequest = service.mealPlanEntries(homeID: home.id, startDate: localDate, endDate: localDate)
        let recipes = homeRecipes.isEmpty ? try await service.homeRecipes(homeId: home.id) : homeRecipes
        let entries = try await entriesRequest
        guard activeHomeID == home.id else {
            throw MealsError.message("The active Home changed. Reopen Leftovers and try again.")
        }
        return Self.resolve(entries: entries, recipes: recipes)
    }

    func addMealPlanDayToGroceries(home: HomeSummary, date: Date) async -> String {
        guard !isAddingMealPlanToGroceries else { return "Groceries are already being added." }
        isAddingMealPlanToGroceries = true
        defer { isAddingMealPlanToGroceries = false }
        let calendar = Self.calendar(home)
        let selectedDay = calendar.startOfDay(for: date)

        do {
            let dayMeals = try await mealPlanItemsForDay(home: home, date: selectedDay)
                .filter { [.breakfast, .lunch, .dinner].contains($0.entry.mealType) }
            guard !dayMeals.isEmpty else { return "No meals are planned for this day." }
            let inputs = dayMeals.map {
                GroceryMealPlanEntryInput(
                    entryID: $0.entry.id,
                    mealID: $0.entry.mealID,
                    plannedDate: $0.entry.plannedDate,
                    label: $0.meal.name,
                    isLeftover: $0.entry.isLeftover
                )
            }
            let result = try await groceryRepository.addMealPlanEntryDay(
                inputs,
                homeID: home.id
            )
            if result.leftoverCount == dayMeals.count {
                return "No new groceries are needed for this day."
            }
            if result.addedCount == 0, result.failureCount == 0 {
                return result.alreadyProcessedCount > 0
                    ? "Groceries are already up to date."
                    : "No new groceries to add."
            }

            var messages: [String] = []
            if result.addedCount > 0 {
                messages.append("Added groceries for \(result.addedCount) meal\(result.addedCount == 1 ? "" : "s").")
            }
            if result.alreadyProcessedCount > 0 {
                messages.append("\(result.alreadyProcessedCount) \(result.alreadyProcessedCount == 1 ? "was" : "were") already added.")
            }
            if result.leftoverCount > 0 {
                messages.append("\(result.leftoverCount) leftover\(result.leftoverCount == 1 ? " was" : "s were") skipped.")
            }
            if result.noIngredientsCount > 0 {
                messages.append("\(result.noIngredientsCount) meal\(result.noIngredientsCount == 1 ? " has" : "s have") no ingredients.")
            }
            if result.failureCount > 0 {
                messages.append("Some groceries couldn't be added. Please try again.")
            }
            return messages.joined(separator: " ")
        } catch {
            #if DEBUG
            print("[Groceries] FAILED Add Meal Plan Day")
            print("[Groceries] error=\(String(reflecting: error))")
            #endif
            return "Groceries couldn't be added for this day. Please try again."
        }
    }

    func assignMealPlanLeftovers(
        home: HomeSummary,
        sourceEntryIDs: [UUID],
        destinationDate: Date,
        conflictMode: LeftoverConflictMode,
        idempotencyKey: UUID
    ) async throws -> AssignMealPlanLeftoversResponse {
        guard activeHomeID == home.id else {
            throw MealsError.message("The active Home changed. Reopen Leftovers and try again.")
        }
        guard !sourceEntryIDs.isEmpty else {
            throw MealsError.message("Choose at least one meal.")
        }
        return try await service.assignMealPlanLeftovers(
            homeID: home.id,
            sourceEntryIDs: sourceEntryIDs,
            destinationDate: Self.localDate(destinationDate, home: home),
            conflictMode: conflictMode,
            idempotencyKey: idempotencyKey
        )
    }
    @discardableResult
    func autoPlan(home: HomeSummary, anchorDate: Date, types: Set<MealType>, favoritesOnly: Bool) async -> Bool {
        guard !isAutoPlanning, activeHomeID == home.id else { return false }
        let supportedTypes = [MealType.breakfast, .lunch, .dinner].filter(types.contains)
        guard !supportedTypes.isEmpty else {
            errorMessage = "Choose at least one meal type."
            return false
        }

        let calendar = Self.calendar(home)
        let week = Self.week(containing: anchorDate, home: home)
        let today = calendar.startOfDay(for: Date())
        let rangeEnd = Self.inclusiveEnd(of: week, home: home)
        let rangeStart = max(calendar.startOfDay(for: week.start), today)
        guard rangeStart <= rangeEnd else {
            errorMessage = "Auto Plan can't add meals to past days."
            return false
        }

        let signature = AutoPlanSignature(
            homeID: home.id,
            startDate: Self.localDate(rangeStart, home: home),
            endDate: Self.localDate(rangeEnd, home: home),
            mealTypes: supportedTypes,
            favoritesOnly: favoritesOnly
        )

        isAutoPlanning = true
        autoPlanNotice = nil
        errorMessage = nil
        defer { isAutoPlanning = false }

        do {
            let attempt: AutoPlanAttempt
            if let pendingAutoPlanAttempt, pendingAutoPlanAttempt.signature == signature {
                attempt = pendingAutoPlanAttempt
            } else {
                pendingAutoPlanAttempt = nil
                let existing = try await service.mealPlanEntries(
                    homeID: home.id,
                    startDate: signature.startDate,
                    endDate: signature.endDate
                )
                let candidates = favoritesOnly
                    ? homeRecipes.filter { favoriteIDs.contains($0.id) }
                    : homeRecipes
                guard !candidates.isEmpty else {
                    errorMessage = favoritesOnly
                        ? "Add some favorite Home Recipes before using Auto Plan."
                        : "Add some Home Recipes before using Auto Plan."
                    return false
                }

                let occupied = Set(existing.map { AutoPlanSlot(date: $0.plannedDate, mealType: $0.mealType) })
                var openSlots: [AutoPlanSlot] = []
                var day = rangeStart
                while day <= rangeEnd {
                    let localDate = Self.localDate(day, home: home)
                    for mealType in supportedTypes {
                        let slot = AutoPlanSlot(date: localDate, mealType: mealType)
                        if !occupied.contains(slot) { openSlots.append(slot) }
                    }
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = nextDay
                }

                guard !openSlots.isEmpty else {
                    errorMessage = "All selected meal slots are already planned."
                    return false
                }

                let favoriteTarget = favoritesOnly
                    ? openSlots.count
                    : Int((Double(openSlots.count) * 0.35).rounded())
                let favoriteSlotIndexes = Set(openSlots.indices.shuffled().prefix(favoriteTarget))
                var usedMealIDs = Set(existing.map(\.mealID))
                var proposedEntries: [MealAutoPlanEntry] = []

                for (index, slot) in openSlots.enumerated() {
                    var eligible = candidates.filter {
                        $0.mealTypes.isEmpty || $0.mealTypes.contains(slot.mealType)
                    }
                    if eligible.isEmpty { eligible = candidates }

                    let unused = eligible.filter { !usedMealIDs.contains($0.id) }
                    let available = unused.isEmpty ? eligible : unused
                    let wantsFavorite = favoriteSlotIndexes.contains(index)
                    let weighted = available.filter {
                        favoriteIDs.contains($0.id) == wantsFavorite
                    }
                    guard let selected = (weighted.isEmpty ? available : weighted).randomElement() else { continue }
                    usedMealIDs.insert(selected.id)
                    proposedEntries.append(MealAutoPlanEntry(
                        mealID: selected.id,
                        plannedDate: slot.date,
                        mealType: slot.mealType,
                        plannedServings: selected.servings
                    ))
                }

                guard !proposedEntries.isEmpty else {
                    errorMessage = "No eligible recipes are available for the selected meal types."
                    return false
                }
                attempt = AutoPlanAttempt(signature: signature, entries: proposedEntries, idempotencyKey: UUID())
                pendingAutoPlanAttempt = attempt
            }

            let response = try await service.applyMealAutoPlan(
                homeID: home.id,
                entries: attempt.entries,
                idempotencyKey: attempt.idempotencyKey
            )
            guard response.homeID == home.id,
                  response.idempotencyKey == attempt.idempotencyKey,
                  response.requestedCount == attempt.entries.count
            else {
                throw MealsError.message("Homey received an unexpected Auto Plan response. Retry to confirm the same request safely.")
            }
            guard activeHomeID == home.id else { return false }
            pendingAutoPlanAttempt = nil
            await refreshPlan(home: home, containing: anchorDate)
            if response.skippedCount > 0 {
                autoPlanNotice = "Meal plan updated. \(response.skippedCount) slot\(response.skippedCount == 1 ? " was" : "s were") already planned."
            }
            return true
        } catch {
            guard activeHomeID == home.id else { return false }
            #if DEBUG
            print("[AutoPlan] FAILED: \(String(reflecting: error))")
            #endif
            errorMessage = "Homey couldn't apply Auto Plan. Check your connection and try again; the same safe request will be reused."
            return false
        }
    }
    private struct AutoPlanSlot: Hashable {
        let date: String
        let mealType: MealType
    }
    private struct AutoPlanSignature: Hashable {
        let homeID: UUID
        let startDate: String
        let endDate: String
        let mealTypes: [MealType]
        let favoritesOnly: Bool
    }
    private struct AutoPlanAttempt {
        let signature: AutoPlanSignature
        let entries: [MealAutoPlanEntry]
        let idempotencyKey: UUID
    }
    private static func resolve(entries: [MealPlanEntry], recipes: [HomeyMeal]) -> [MealPlanItem] {
        let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        return entries.compactMap { entry in
            recipesByID[entry.mealID].map { MealPlanItem(entry: entry, meal: $0) }
        }
    }
    static func localDate(_ date: Date, home: HomeSummary) -> String {
        let components = calendar(home).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    private static func inclusiveEnd(of interval: DateInterval, home: HomeSummary) -> Date {
        calendar(home).date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
    }
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlyingError)
        }
        return false
    }
    static func calendar(_ home:HomeSummary)->Calendar { var c=Calendar(identifier:.gregorian); c.timeZone=home.timezone.flatMap(TimeZone.init(identifier:)) ?? .current; c.firstWeekday=home.weekStartsOn == 2 ? 2:1; return c }
    static func week(containing date:Date,home:HomeSummary)->DateInterval { let c=calendar(home); return c.dateInterval(of:.weekOfYear,for:date) ?? .init(start:c.startOfDay(for:date),duration:604800) }
}

struct MealsRootView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = MealsViewModel()
    @State private var section = 0
    @State private var showAdd = false
    @State private var creationPresentation: RecipeCreationPresentation?
    @State private var pendingEditorPresentation: RecipeCreationPresentation?
    @State private var selectedMealPlanDate = Date()
    @State private var showAutoPlan = false
    @State private var showLeftovers = false
    @State private var dayGroceryMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                VStack(spacing: 12) {
                    HStack {
                        Text("Meals")
                            .font(.title.bold())
                            .foregroundStyle(HomeyColors.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if section == 0, session.activeHome != nil {
                            Menu {
                                Button("Auto Plan", systemImage: "wand.and.sparkles") {
                                    showAutoPlan = true
                                }
                                .disabled(model.isAutoPlanning)
                                Button("Leftovers", systemImage: "takeoutbag.and.cup.and.straw") { showLeftovers = true }
                                    .disabled(!hasMealsForSelectedDay)
                                Button("Add to Groceries", systemImage: "cart.badge.plus") {
                                    guard let home = session.activeHome else { return }
                                    Task {
                                        dayGroceryMessage = await model.addMealPlanDayToGroceries(home: home, date: selectedMealPlanDate)
                                    }
                                }
                                .disabled(model.isAddingMealPlanToGroceries)
                            } label: {
                                Group {
                                    if model.isAutoPlanning || model.isAddingMealPlanToGroceries { ProgressView().tint(HomeyColors.primary) }
                                    else { Image(systemName: "ellipsis").font(.title3.weight(.semibold)) }
                                }
                                .foregroundStyle(HomeyColors.primary)
                                .frame(width: 44, height: 44)
                                .background(HomeyColors.field, in: Circle())
                            }
                            .accessibilityLabel("Meal plan actions")
                        } else if section == 1 {
                            Button { showAdd = true } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(HomeyColors.primary)
                                    .frame(width: 44, height: 44)
                                    .background(HomeyColors.field, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add Recipe")
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    Picker("Meals", selection: $section) {
                        Text("Meal Plan").tag(0)
                        Text("Recipes").tag(1)
                        Text("Explore").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if let home = session.activeHome {
                        if section == 0 {
                            MealPlanView(home: home, model: model, selectedDate: $selectedMealPlanDate)
                        } else if section == 1 {
                            RecipeLibraryView(home: home, model: model, onAddRecipe: { showAdd = true }, onExplore: { section = 2 })
                        } else {
                            ExploreRecipesView(home: home, model: model).id(home.id)
                        }
                    } else {
                        ContentUnavailableView("Choose a Home", systemImage: "house")
                    }
                }
            }
            .navigationTitle("Meals")
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Add Recipe", isPresented: $showAdd, titleVisibility: .visible) {
                Button("New Recipe") { creationPresentation = .manual() }
                Button("From Website") { creationPresentation = .website() }
                Button("Scan") { creationPresentation = .scan() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $creationPresentation, onDismiss: {
                if let editor = pendingEditorPresentation {
                    pendingEditorPresentation = nil
                    creationPresentation = editor
                }
            }) { presentation in
                if let home = session.activeHome {
                    switch presentation.content {
                    case .website:
                        RecipeImportView(home: home) { draft in
                            pendingEditorPresentation = .imported(draft)
                            creationPresentation = nil
                        }
                    case .editor(let initialDraft):
                        RecipeEditorView(home: home, model: model, initialDraft: initialDraft)
                            .id(presentation.id)
                    case .scan:
                        RecipeScanComingSoonView()
                    }
                }
            }
            .sheet(isPresented: $showLeftovers) {
                if let home = session.activeHome {
                    AssignLeftoversView(home: home, sourceDate: selectedMealPlanDate, model: model) { destinationDate in
                        selectedMealPlanDate = destinationDate
                    }
                }
            }
            .sheet(isPresented: $showAutoPlan) {
                if let home = session.activeHome {
                    AutoPlanSheet(
                        home: home,
                        anchorDate: selectedMealPlanDate,
                        model: model
                    )
                }
            }
            .task(id: session.activeHome?.id) {
                if let home = session.activeHome {
                    selectedMealPlanDate = Self.startOfToday(home: home)
                    await model.load(home: home)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyMealsDidChange"))) { _ in
                guard let home = session.activeHome else { return }
                Task { await model.load(home: home) }
            }
            .refreshable {
                guard let home = session.activeHome else { return }
                if section == 0 {
                    await model.refreshPlan(home: home, containing: selectedMealPlanDate)
                } else {
                    await model.load(home: home)
                }
            }
            .alert("Meals", isPresented: .init(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.errorMessage ?? "") }
            .alert("Groceries", isPresented: .init(get: { dayGroceryMessage != nil }, set: { if !$0 { dayGroceryMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dayGroceryMessage ?? "")
            }
            .alert("Auto Plan", isPresented: .init(get: { model.autoPlanNotice != nil }, set: { if !$0 { model.autoPlanNotice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.autoPlanNotice ?? "")
            }
        }
    }

    private static func startOfToday(home: HomeSummary) -> Date {
        MealsViewModel.calendar(home).startOfDay(for: Date())
    }

    private var hasMealsForSelectedDay: Bool {
        guard let home = session.activeHome else { return false }
        let selectedDate = MealsViewModel.localDate(selectedMealPlanDate, home: home)
        return model.mealPlanItems.contains {
            $0.entry.plannedDate == selectedDate
                && [.breakfast, .lunch, .dinner].contains($0.entry.mealType)
        }
    }

}

struct RecipePickerView: View {
    let recipes: [HomeyMeal]
    let favorites: Set<UUID>
    var mealTypeFilter: MealType? = nil
    var isLoading = false
    let select: (HomeyMeal) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var selectingID: UUID?
    @State private var errorMessage: String?

    private var filteredRecipes: [HomeyMeal] {
        recipes.filter { meal in
            (mealTypeFilter.map { meal.mealTypes.contains($0) } ?? true) &&
            (!favoritesOnly || favorites.contains(meal.id)) &&
            (search.isEmpty || meal.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HomeyColors.secondaryText)
                    TextField("Search recipes...", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(HomeyColors.secondaryText).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(HomeyColors.field.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)

                if isLoading && recipes.isEmpty {
                    Spacer()
                    ProgressView("Loading recipes…").tint(HomeyColors.recipeGreenAccent)
                    Spacer()
                } else if filteredRecipes.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label(favoritesOnly ? "No favorite recipes found" : "No recipes found", systemImage: "fork.knife")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if !search.isEmpty || favoritesOnly {
                            Button("Clear search and filters") { search = ""; favoritesOnly = false }
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRecipes) { meal in
                                RecipePickerRow(meal: meal, loading: selectingID == meal.id) {
                                    Task { await choose(meal) }
                                }
                                .disabled(selectingID != nil)
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 24)
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
            .background(HomeyColors.recipeBackground.ignoresSafeArea())
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { favoritesOnly.toggle() } label: {
                        Label("Favorites", systemImage: favoritesOnly ? "heart.fill" : "heart")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 36)
                            .foregroundStyle(favoritesOnly ? .white : HomeyColors.recipeGreenAccent)
                            .background(favoritesOnly ? HomeyColors.recipeGreenAccent : HomeyColors.recipeGreenAccent.opacity(0.1), in: Capsule())
                    }.buttonStyle(.plain).accessibilityValue(favoritesOnly ? "On" : "Off")
                }
            }
            .interactiveDismissDisabled(selectingID != nil)
            .alert("Couldn't Add Recipe", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var emptyDescription: String {
        if favoritesOnly { return "Try turning off Favorites or clearing your search." }
        if mealTypeFilter != nil { return "Add or retag a recipe to use it in this meal slot." }
        return "Try clearing your search."
    }

    private func choose(_ meal: HomeyMeal) async {
        guard selectingID == nil else { return }
        selectingID = meal.id
        let succeeded = await select(meal)
        selectingID = nil
        if succeeded { dismiss() }
        else { errorMessage = "Homey couldn't add this recipe to your meal plan. Please try again." }
    }
}

private struct RecipePickerRow: View {
    let meal: HomeyMeal
    let loading: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                HomeRecipeThumbnail(path: meal.primaryPhotoPath).frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(meal.name).font(.headline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if loading { ProgressView().tint(HomeyColors.recipeGreenAccent) }
                else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText) }
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: HomeyColors.text.opacity(0.035), radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(meal.name).accessibilityHint("Selects this recipe")
    }
}

struct RecipePlanSheet:View{let meal:HomeyMeal,home:HomeSummary;@ObservedObject var model:MealsViewModel;@Environment(\.dismiss)var dismiss;@State var day=Date();@State var type=MealType.dinner;var body:some View{NavigationStack{Form{DatePicker("Day",selection:$day,displayedComponents:.date);Picker("Meal",selection:$type){ForEach([MealType.breakfast,.lunch,.dinner]){Text($0.title).tag($0)}}}.navigationTitle("Add to Meal Plan").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Add"){Task{await model.schedule(meal,type:type,day:day,home:home);dismiss()}}}}}}}
struct AutoPlanSheet: View {
    let home: HomeSummary
    let anchorDate: Date
    @ObservedObject var model: MealsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var types: Set<MealType> = []
    @State private var favoritesOnly = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Fill empty slots") {
                    ForEach([MealType.breakfast, .lunch, .dinner]) { type in
                        Toggle(type.title, isOn: .init(
                            get: { types.contains(type) },
                            set: { types.set(type, included: $0) }
                        ))
                    }
                }
                Section("Recipe pool") {
                    Toggle("Favorites only", isOn: $favoritesOnly)
                    Text("Past days and existing planned meals are preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Auto Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isAutoPlanning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await model.autoPlan(
                                home: home,
                                anchorDate: anchorDate,
                                types: types,
                                favoritesOnly: favoritesOnly
                            ) {
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isAutoPlanning { ProgressView() }
                        else { Text("Plan") }
                    }
                    .disabled(types.isEmpty || model.isAutoPlanning)
                }
            }
            .interactiveDismissDisabled(model.isAutoPlanning)
            .alert("Auto Plan", isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

private struct RecipeScanComingSoonView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ContentUnavailableView("Coming Soon", systemImage: "doc.viewfinder")
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension StepDraft { init(text: String) { self.init(); self.text = text } }
private extension Set { mutating func set(_ member: Element, included: Bool) { if included { insert(member) } else { remove(member) } } }
