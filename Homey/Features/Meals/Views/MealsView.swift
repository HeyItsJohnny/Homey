import SwiftUI

struct MealsView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.homePermissions) private var permissions
    @Environment(\.homePermissionResolution) private var permissionResolution
    @StateObject private var viewModel = MealsViewModel()
    @StateObject private var mealPlannerViewModel = MealPlannerViewModel()
    @StateObject private var globalExploreViewModel = GlobalMealsExploreViewModel()
    @State private var selectedTab: MealsLandingTab = .recipes
    @State private var isSearchVisible = false
    @State private var isAddRecipeOptionsPresented = false
    @State private var isExploreFiltersPresented = false
    @State private var comingSoonMessage: String?
    @State private var path = NavigationPath()
    var onOpenCalendar: (Date?) -> Void = { _ in }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        tabPicker
                        searchAndFilters
                        content
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 34)
                    .padding(.bottom, 38)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    if selectedTab == .explore {
                        globalExploreViewModel.reload()
                    } else {
                        viewModel.reload()
                    }
                }
            }
            .navigationDestination(for: MealsRoute.self) { route in
                switch route {
                case .library:
                    RecipeLibraryView(
                        meals: viewModel.unfilteredMeals,
                        canCreate: mealPermissions.canCreate,
                        canDelete: mealPermissions.canDelete,
                        canFavorite: mealPermissions.canFavorite,
                        searchText: $viewModel.searchText,
                        selectedMealType: $viewModel.selectedMealType,
                        isFavorite: viewModel.isFavorite,
                        onToggleFavorite: toggleFavorite,
                        onDeleteMeal: deleteMeal,
                        onSelectMeal: openMealEditor,
                        onAddRecipe: { isAddRecipeOptionsPresented = true }
                    )
                case .addMeal:
                    switch effectivePermissionResolution {
                    case .loading:
                        MealMessageCard(
                            title: "Loading Permissions",
                            message: "Loading your Home permissions…",
                            systemImage: "hourglass"
                        )
                    case .unavailable:
                        MealMessageCard(
                            title: "Meals Unavailable",
                            message: "We cannot find your membership for this Home.",
                            systemImage: "lock.fill"
                        )
                    case .resolved(let resolvedPermissions):
                        if resolvedPermissions.meals.canCreate {
                            AddMealView { savedID, meal, globalRecipeID in
                                handleCreatedRecipeSave(savedID: savedID, meal: meal, globalRecipeID: globalRecipeID)
                            }
                        } else {
                            MealMessageCard(
                                title: "Meals Unavailable",
                                message: "You do not have permission to create meals in this Home.",
                                systemImage: "lock.fill"
                            )
                        }
                    }
                case .importRecipeURL:
                    switch effectivePermissionResolution {
                    case .loading:
                        MealMessageCard(
                            title: "Loading Permissions",
                            message: "Loading your Home permissions…",
                            systemImage: "hourglass"
                        )
                    case .unavailable:
                        MealMessageCard(
                            title: "Meals Unavailable",
                            message: "We cannot find your membership for this Home.",
                            systemImage: "lock.fill"
                        )
                    case .resolved(let resolvedPermissions):
                        if resolvedPermissions.meals.canCreate {
                            ImportRecipeURLView(homeId: homeService.selectedHomeID) { response in
                                path.append(MealsRoute.importedRecipePreview(response))
                            }
                        } else {
                            MealMessageCard(
                                title: "Meals Unavailable",
                                message: "You do not have permission to create meals in this Home.",
                                systemImage: "lock.fill"
                            )
                        }
                    }
                case .importedRecipePreview(let response):
                    ImportedRecipePreviewView(response: response, homeId: homeService.selectedHomeID) { savedID, savedMeal, globalRecipeID in
                        let savedGlobalRecipeId = globalRecipeID ?? savedMeal?.originGlobalRecipeId ?? savedMeal?.globalRecipeId ?? response.globalRecipeId
                        let savedToHome = savedGlobalRecipeId == nil || savedGlobalRecipeId != savedID

                        #if DEBUG
                        print("URL import completed")
                        if let globalRecipeId = response.globalRecipeId {
                            print("parsed_global_recipe_id: \(globalRecipeId.uuidString)")
                        } else {
                            print("parsed_global_recipe_id: nil")
                        }
                        if let savedGlobalRecipeId {
                            print("saved_global_recipe_id: \(savedGlobalRecipeId.uuidString)")
                        } else {
                            print("saved_global_recipe_id: nil")
                        }
                        print("saved_id: \(savedID.uuidString)")
                        print("explore_refresh_requested: true")
                        #endif
                        if let globalRecipeId = savedGlobalRecipeId {
                            globalExploreViewModel.refreshAfterGlobalRecipeImport(
                                globalRecipeId: globalRecipeId,
                                homeMealId: savedToHome ? savedID : nil,
                                homeId: homeService.selectedHomeID,
                                selectedMealType: viewModel.selectedMealType
                            )
                        }
                        selectedTab = savedToHome ? .recipes : .explore
                        if savedToHome {
                            handleSavedMeal(mealID: savedID, meal: savedMeal)
                        }
                        path = NavigationPath()
                    }
                case .globalRecipesLibrary(let launchContext):
                    GlobalRecipesLibraryView(
                        launchContext: launchContext,
                        selectedHomeID: homeService.selectedHomeID,
                        onOpenHomeMeal: { mealId in
                            path.append(MealsRoute.editMeal(mealId))
                        },
                        onHomeMealAdded: { mealId in
                            Task {
                                _ = await viewModel.refreshMeal(id: mealId, homeId: homeService.selectedHomeID)
                            }
                        }
                    )
                case .editMeal(let mealID):
                    switch effectivePermissionResolution {
                    case .loading:
                        MealMessageCard(
                            title: "Loading Permissions",
                            message: "Loading your Home permissions…",
                            systemImage: "hourglass"
                        )
                    case .unavailable:
                        MealMessageCard(
                            title: "Meals Unavailable",
                            message: "We cannot find your membership for this Home.",
                            systemImage: "lock.fill"
                        )
                    case .resolved(let resolvedPermissions):
                        if resolvedPermissions.meals.canEdit {
                            MealEditorView(mode: .edit(mealID: mealID)) { savedMealID, meal, _ in
                                handleSavedMeal(mealID: savedMealID, meal: meal)
                            } onDelete: { deletedMealID in
                                deleteMeal(id: deletedMealID)
                            }
                        } else {
                            MealMessageCard(
                                title: "Meals Unavailable",
                                message: "You do not have permission to edit meals in this Home.",
                                systemImage: "lock.fill"
                            )
                        }
                    }
                }
            }
        }
        .task(id: homeService.selectedHomeID) {
            viewModel.load(homeId: homeService.selectedHomeID)
        }
        .alert("Meals", isPresented: errorBinding) {
            Button("Try Again") { viewModel.reload() }
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "We could not load meals.")
        }
        .alert("Coming Soon", isPresented: comingSoonBinding) {
            Button("OK", role: .cancel) { comingSoonMessage = nil }
        } message: {
            Text(comingSoonMessage ?? "")
        }
        .confirmationDialog("Add Recipe", isPresented: $isAddRecipeOptionsPresented, titleVisibility: .visible) {
            Button("Create Manually") {
                openAddRecipeRoute(.addMeal)
            }
            Button("Import from URL") {
                openAddRecipeRoute(.importRecipeURL)
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var effectivePermissionResolution: PermissionResolutionState {
        let sharedResolution = homeService.permissionResolutionState(currentUser: authenticationService.currentUser)

        switch sharedResolution {
        case .resolved, .loading:
            return sharedResolution
        case .unavailable:
            break
        }

        switch permissionResolution {
        case .unavailable where hasInjectedMealPermissions:
            return .resolved(permissions)
        default:
            return permissionResolution
        }
    }

    private var mealPermissions: MealPermissions {
        effectivePermissionResolution.permissions.meals
    }

    private var hasInjectedMealPermissions: Bool {
        permissions.meals.canView
            || permissions.meals.canCreate
            || permissions.meals.canEdit
            || permissions.meals.canArchive
            || permissions.meals.canDelete
            || permissions.meals.canFavorite
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Meals")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Your recipes and meal plans in one place.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchVisible.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 44, height: 44)
                        .background(HomeyDashboardTheme.cardBackground, in: Circle())
                        .overlay {
                            Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search meals")

                if mealPermissions.canCreate {
                    Button {
                        isAddRecipeOptionsPresented = true
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "plus")
                            Text("Add Recipe")
                        }
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .frame(width: 150)
                    .disabled(homeService.selectedHomeID == nil)
                    .accessibilityLabel("Add Recipe")
                }
            }
            .padding(.trailing, 70)
        }
    }

    @ViewBuilder
    private var searchAndFilters: some View {
        if isSearchVisible || !activeSearchText.wrappedValue.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .accessibilityHidden(true)

                TextField(selectedTab == .explore ? "Search community recipes" : "Search recipes", text: activeSearchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !activeSearchText.wrappedValue.isEmpty {
                    Button {
                        activeSearchText.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.body.weight(.medium))
            .foregroundStyle(HomeyDashboardTheme.primaryText)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if selectedTab != .mealPlan {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    ZStack(alignment: .trailing) {
                        HStack(spacing: 10) {
                        MealTypeFilterChip(title: "All", isSelected: viewModel.selectedMealType == nil) {
                            viewModel.selectedMealType = nil
                        }

                        ForEach(MealType.allCases) { mealType in
                            MealTypeFilterChip(title: mealType.displayName, systemImage: mealType.systemImageName, isSelected: viewModel.selectedMealType == mealType) {
                                viewModel.selectedMealType = mealType
                            }
                        }
                    }
                        .padding(.trailing, selectedTab == .explore ? 124 : 0)
                        .padding(.vertical, 2)
                        .frame(minWidth: proxy.size.width, alignment: .center)

                        if selectedTab == .explore {
                            Button {
                                isExploreFiltersPresented = true
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: globalExploreViewModel.filters.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .accessibilityHidden(true)
                                    Text("Filters")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(globalExploreViewModel.filters.hasActiveFilters ? .white : HomeyDashboardTheme.primaryText)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 42)
                                .background(globalExploreViewModel.filters.hasActiveFilters ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground, in: Capsule())
                                .overlay {
                                    Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: globalExploreViewModel.filters.hasActiveFilters ? 0 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Filters")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: 48)
        }
    }

    private var activeSearchText: Binding<String> {
        Binding(
            get: {
                selectedTab == .explore ? globalExploreViewModel.searchText : viewModel.searchText
            },
            set: { newValue in
                if selectedTab == .explore {
                    globalExploreViewModel.searchText = newValue
                } else {
                    viewModel.searchText = newValue
                }
            }
        )
    }

    private var tabPicker: some View {
        ModuleTabSelector(
            tabs: MealsLandingTab.allCases,
            selectedTab: $selectedTab,
            accessibilityLabel: "Meals section",
            title: { $0.title }
        )
    }

    @ViewBuilder
    private var content: some View {
        if homeService.selectedHomeID == nil {
            MealMessageCard(
                title: "Choose a Home",
                message: "Select a Home before viewing shared meals.",
                systemImage: "house.fill"
            )
        } else if !mealPermissions.canView {
            MealMessageCard(
                title: "Meals Unavailable",
                message: "You do not have permission to view meals in this Home.",
                systemImage: "lock.fill"
            )
        } else if selectedTab == .explore {
            exploreTab
        } else if viewModel.isLoading && viewModel.meals.isEmpty && viewModel.favoriteMeals.isEmpty {
            MealsLoadingGrid()
        } else if viewModel.meals.isEmpty && viewModel.favoriteMeals.isEmpty && selectedTab == .recipes {
            emptyMealsState
        } else {
            switch selectedTab {
            case .recipes:
                recipesTab
            case .mealPlan:
                mealPlanTab
            case .explore:
                exploreTab
            }
        }
    }

    private var recipesTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            FeaturedMealsSection(
                title: "House Recipes",
                meals: viewModel.featuredMeals,
                emptyMessage: "Favorite recipes and recently updated meals will appear here.",
                canFavorite: mealPermissions.canFavorite,
                isFavorite: viewModel.isFavorite,
                onToggleFavorite: toggleFavorite,
                onSelectMeal: openMealEditor,
                onSeeAll: { path.append(MealsRoute.library) }
            )

            upcomingMealPlanCard
            quickActionsGrid
        }
    }

    private var mealPlanTab: some View {
        MealPlannerView(
            viewModel: mealPlannerViewModel,
            meals: viewModel.unfilteredMeals,
            favoriteMeals: viewModel.favoriteMeals,
            collections: viewModel.collections,
            householdMembers: homeService.membersForSelectedHome(),
            permissions: permissions,
            selectedHomeID: homeService.selectedHomeID,
            weekStartsOn: homeService.selectedHome()?.weekStartsOn,
            timezone: homeService.selectedHome()?.timezone,
            onSelectMeal: openMealEditor,
            onOpenCalendar: onOpenCalendar,
            onComingSoon: { message in comingSoonMessage = message }
        )
    }

    private var exploreTab: some View {
        GlobalMealsExploreView(
            viewModel: globalExploreViewModel,
            selectedHomeID: homeService.selectedHomeID,
            selectedMealType: viewModel.selectedMealType,
            isFiltersPresented: $isExploreFiltersPresented,
            onOpenHomeMeal: { mealId in
                path.append(MealsRoute.editMeal(mealId))
            },
            onHomeMealAdded: { mealId in
                Task {
                    _ = await viewModel.refreshMeal(id: mealId, homeId: homeService.selectedHomeID)
                }
            },
            onViewAllTrending: {
                path.append(MealsRoute.globalRecipesLibrary(.trending))
            }
        )
    }

    private var upcomingMealPlanCard: some View {
        UpcomingMealsPreviewView(
            viewModel: mealPlannerViewModel,
            meals: viewModel.unfilteredMeals,
            favoriteMeals: viewModel.favoriteMeals,
            collections: viewModel.collections,
            permissions: permissions,
            selectedHomeID: homeService.selectedHomeID,
            weekStartsOn: homeService.selectedHome()?.weekStartsOn,
            timezone: homeService.selectedHome()?.timezone,
            onSelectMeal: openMealEditor,
            onShowPlanner: { selectedTab = .mealPlan }
        )
    }

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Actions")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                if mealPermissions.canCreate {
                    MealQuickActionCard(title: "Add Recipe", subtitle: "Create manually or import", systemImage: "plus.circle.fill", accentColor: HomeyDashboardTheme.warmBrown) {
                        isAddRecipeOptionsPresented = true
                    }
                }
                MealQuickActionCard(title: "Plan a Meal", subtitle: "Open planner", systemImage: "calendar", accentColor: HomeyDashboardTheme.lavenderAccent) {
                    selectedTab = .mealPlan
                }
                MealQuickActionCard(title: "Pantry Suggestions", subtitle: "Coming soon", systemImage: "refrigerator.fill", accentColor: HomeyDashboardTheme.sageAccent) {
                    comingSoonMessage = "Pantry suggestions are coming in a future Meals phase."
                }
                MealQuickActionCard(title: "Scan Recipe", subtitle: "Coming soon", systemImage: "doc.viewfinder.fill", accentColor: HomeyDashboardTheme.orangeAccent) {
                    comingSoonMessage = "Recipe scanning is coming in a future Meals phase."
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyMealsState: some View {
        VStack(alignment: .leading, spacing: 22) {
            MealMessageCard(
                title: "Build your family recipe library",
                message: "Save favorite meals, recipes, cooking notes, and family traditions in one shared place.",
                systemImage: "fork.knife.circle.fill",
                buttonTitle: "Explore Recipes",
                action: { selectedTab = .explore }
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                MealBenefitCard(title: "Plan meals faster", systemImage: "calendar.badge.checkmark")
                MealBenefitCard(title: "Build grocery lists", systemImage: "cart.fill.badge.plus")
                MealBenefitCard(title: "Use what is in your pantry", systemImage: "refrigerator.fill")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in }
        )
    }

    private var comingSoonBinding: Binding<Bool> {
        Binding(
            get: { comingSoonMessage != nil },
            set: { isPresented in
                if !isPresented { comingSoonMessage = nil }
            }
        )
    }

    private func toggleFavorite(_ meal: Meal) {
        Task { await viewModel.toggleFavorite(meal, permissions: permissions) }
    }

    private func deleteMeal(_ meal: Meal) {
        Task { await viewModel.deleteMeal(meal, permissions: permissions) }
    }

    private func deleteMeal(id mealID: UUID) {
        guard let meal = viewModel.unfilteredMeals.first(where: { $0.id == mealID }) else { return }
        deleteMeal(meal)
    }

    private func openMealEditor(_ meal: Meal) {
        guard mealPermissions.canEdit else {
            comingSoonMessage = "You do not have permission to edit meals in this Home."
            return
        }
        path.append(MealsRoute.editMeal(meal.id))
    }

    private func openAddRecipeRoute(_ route: MealsRoute) {
        isAddRecipeOptionsPresented = false
        Task { @MainActor in
            await Task.yield()
            path.append(route)
        }
    }

    private func handleSavedMeal(mealID: UUID, meal: Meal?) {
        if let meal {
            viewModel.replaceMeal(meal)
        } else {
            Task {
                _ = await viewModel.refreshMeal(id: mealID, homeId: homeService.selectedHomeID)
            }
        }
    }

    private func handleCreatedRecipeSave(savedID: UUID, meal: Meal?, globalRecipeID: UUID?) {
        let savedToHome = globalRecipeID == nil || globalRecipeID != savedID

        if let globalRecipeID {
            globalExploreViewModel.refreshAfterGlobalRecipeImport(
                globalRecipeId: globalRecipeID,
                homeMealId: savedToHome ? savedID : nil,
                homeId: homeService.selectedHomeID,
                selectedMealType: viewModel.selectedMealType
            )
        }

        if savedToHome {
            selectedTab = .recipes
            handleSavedMeal(mealID: savedID, meal: meal)
        } else {
            selectedTab = .explore
        }

        path = NavigationPath()
    }
}

private enum MealsLandingTab: String, CaseIterable, Identifiable {
    case recipes
    case mealPlan
    case explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipes:
            return "Recipes"
        case .mealPlan:
            return "Meal Plan"
        case .explore:
            return "Explore"
        }
    }
}

private enum MealsRoute: Hashable {
    case library
    case addMeal
    case importRecipeURL
    case importedRecipePreview(RecipeImportResponse)
    case globalRecipesLibrary(GlobalRecipesLibraryLaunchContext)
    case editMeal(UUID)
}

enum GlobalRecipesLibraryLaunchContext: Hashable {
    case trending
}

private struct FeaturedMealsSection: View {
    let title: String
    let meals: [Meal]
    let emptyMessage: String
    let canFavorite: Bool
    let isFavorite: (Meal) -> Bool
    let onToggleFavorite: (Meal) -> Void
    let onSelectMeal: (Meal) -> Void
    let onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Spacer()

                if let onSeeAll, !meals.isEmpty {
                    Button("See All", action: onSeeAll)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .buttonStyle(.plain)
                }
            }

            if meals.isEmpty {
                MealMessageCard(title: "No Recipes", message: emptyMessage, systemImage: "fork.knife")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(meals.prefix(4)) { meal in
                        MealCard(
                            meal: meal,
                            isFavorite: isFavorite(meal),
                            canFavorite: canFavorite,
                            onToggleFavorite: { onToggleFavorite(meal) },
                            onSelect: { onSelectMeal(meal) }
                        )
                    }
                }
            }
        }
    }
}

private struct MealCard: View {
    let meal: Meal
    let isFavorite: Bool
    let canFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                MealPhotoThumbnail(path: meal.primaryPhotoPath)
                    .frame(height: 138)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if canFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(isFavorite ? HomeyDashboardTheme.coralAccent : HomeyDashboardTheme.warmBrown)
                            .frame(width: 44, height: 44)
                            .background(HomeyDashboardTheme.cardBackground.opacity(0.94), in: Circle())
                            .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(meal.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                Label(totalTimeText, systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                HStack(spacing: 6) {
                    ForEach(meal.mealTypes.prefix(2)) { type in
                        Text(type.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .dashboardCard(cornerRadius: 26)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens meal details")
    }

    private var totalTimeText: String {
        let total = (meal.prepTimeMinutes ?? 0) + (meal.cookTimeMinutes ?? 0)
        guard total > 0 else { return "Time not set" }
        return "\(total) min"
    }

    private var accessibilityLabel: String {
        "\(meal.name), \(totalTimeText), \(meal.mealTypes.map(\.displayName).joined(separator: ", "))"
    }
}

private struct MealTypeFilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : HomeyDashboardTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground, in: Capsule())
            .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: isSelected ? 0 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct MealQuickActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .dashboardCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private struct MealMessageCard: View {
    let title: String
    let message: String
    let systemImage: String
    var buttonTitle: String?
    var isButtonDisabled = false
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HomeyDashboardTheme.selectedSidebarBackground)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle {
                Button(buttonTitle) {
                    action?()
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 190)
                .disabled(isButtonDisabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }
}

private struct MealBenefitCard: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
                .frame(width: 36, height: 36)
                .background(HomeyDashboardTheme.sageAccent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(16)
        .dashboardCard(cornerRadius: 22)
    }
}

private struct MealsLoadingGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(HomeyDashboardTheme.warmBeige.opacity(0.35))
                        .frame(height: 138)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HomeyDashboardTheme.warmBeige.opacity(0.35))
                        .frame(height: 18)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(HomeyDashboardTheme.warmBeige.opacity(0.24))
                        .frame(width: 110, height: 14)
                }
                .padding(14)
                .dashboardCard(cornerRadius: 26)
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("Loading meals")
    }
}

private extension Meal {
    func matchesMealsSearch(_ normalizedSearch: String) -> Bool {
        [name, description, cuisine, notes, sourceName]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedSearch) }
            || tags.contains { $0.lowercased().contains(normalizedSearch) }
            || mealTypes.contains { $0.displayName.lowercased().contains(normalizedSearch) }
    }
}

#Preview("Meals") {
    MealsView()
        .environmentObject(HomeService())
}
