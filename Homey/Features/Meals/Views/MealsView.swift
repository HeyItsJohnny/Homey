import SwiftUI

struct MealsView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.homePermissions) private var permissions
    @Environment(\.homePermissionResolution) private var permissionResolution
    @StateObject private var viewModel = MealsViewModel()
    @StateObject private var mealPlannerViewModel = MealPlannerViewModel()
    @State private var selectedTab: MealsLandingTab = .recipes
    @State private var isSearchVisible = false
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
                    viewModel.reload()
                }
            }
            .navigationDestination(for: MealsRoute.self) { route in
                switch route {
                case .library:
                    RecipeLibraryView(
                        meals: viewModel.meals,
                        canFavorite: mealPermissions.canFavorite,
                        isFavorite: viewModel.isFavorite,
                        onToggleFavorite: toggleFavorite,
                        onSelectMeal: { meal in path.append(MealsRoute.detail(meal.id)) }
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
                            AddMealView { mealID, meal in
                                handleSavedMeal(mealID: mealID, meal: meal)
                            }
                        } else {
                            MealMessageCard(
                                title: "Meals Unavailable",
                                message: "You do not have permission to create meals in this Home.",
                                systemImage: "lock.fill"
                            )
                        }
                    }
                case .detail(let mealID):
                    MealDetailDestination(
                        mealID: mealID,
                        selectedHomeID: homeService.selectedHomeID,
                        viewModel: viewModel,
                        canFavorite: mealPermissions.canFavorite,
                        canEdit: mealPermissions.canEdit,
                        onToggleFavorite: toggleFavorite,
                        onEdit: { path.append(MealsRoute.editMeal(mealID)) }
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
                            MealEditorView(mode: .edit(mealID: mealID)) { savedMealID, meal in
                                handleSavedMeal(mealID: savedMealID, meal: meal)
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
                        path.append(MealsRoute.addMeal)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "plus")
                            Text("Add Meal")
                        }
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .frame(width: 140)
                    .disabled(homeService.selectedHomeID == nil)
                    .accessibilityLabel("Add Meal")
                }
            }
            .padding(.trailing, 70)
        }
    }

    @ViewBuilder
    private var searchAndFilters: some View {
        if isSearchVisible || !viewModel.searchText.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .accessibilityHidden(true)

                TextField("Search recipes", text: $viewModel.searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
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
                    .padding(.vertical, 2)
                    .frame(minWidth: proxy.size.width, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: 48)
        }
    }

    private var tabPicker: some View {
        Picker("Meals section", selection: $selectedTab) {
            ForEach(MealsLandingTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("Meals section")
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
        } else if viewModel.isLoading && viewModel.meals.isEmpty && viewModel.favoriteMeals.isEmpty {
            MealsLoadingGrid()
        } else if viewModel.meals.isEmpty && viewModel.favoriteMeals.isEmpty && selectedTab != .mealPlan {
            emptyMealsState
        } else {
            switch selectedTab {
            case .recipes:
                recipesTab
            case .mealPlan:
                mealPlanTab
            case .favorites:
                favoritesTab
            }
        }
    }

    private var recipesTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            FeaturedMealsSection(
                title: "Featured Recipes",
                meals: viewModel.featuredMeals,
                emptyMessage: "Favorite recipes and recently updated meals will appear here.",
                canFavorite: mealPermissions.canFavorite,
                isFavorite: viewModel.isFavorite,
                onToggleFavorite: toggleFavorite,
                onSelectMeal: { meal in path.append(MealsRoute.detail(meal.id)) },
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
            onSelectMeal: { meal in path.append(MealsRoute.detail(meal.id)) },
            onOpenCalendar: onOpenCalendar,
            onComingSoon: { message in comingSoonMessage = message }
        )
    }

    private var favoritesTab: some View {
        FeaturedMealsSection(
            title: "Favorite Meals",
            meals: filteredFavoriteMeals,
            emptyMessage: "Tap the heart on a meal to save it here.",
            canFavorite: mealPermissions.canFavorite,
            isFavorite: viewModel.isFavorite,
            onToggleFavorite: toggleFavorite,
            onSelectMeal: { meal in path.append(MealsRoute.detail(meal.id)) },
            onSeeAll: nil
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
            onSelectMeal: { meal in path.append(MealsRoute.detail(meal.id)) },
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
                    MealQuickActionCard(title: "Create Meal", subtitle: "Save a recipe", systemImage: "plus.circle.fill", accentColor: HomeyDashboardTheme.warmBrown) {
                        path.append(MealsRoute.addMeal)
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
                buttonTitle: mealPermissions.canCreate ? "Create Your First Meal" : nil,
                action: mealPermissions.canCreate ? { path.append(MealsRoute.addMeal) } : nil
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                MealBenefitCard(title: "Plan meals faster", systemImage: "calendar.badge.checkmark")
                MealBenefitCard(title: "Build grocery lists", systemImage: "cart.fill.badge.plus")
                MealBenefitCard(title: "Use what is in your pantry", systemImage: "refrigerator.fill")
            }
        }
    }

    private var filteredFavoriteMeals: [Meal] {
        let normalizedSearch = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.favoriteMeals.filter { meal in
            if let selectedMealType = viewModel.selectedMealType, !meal.mealTypes.contains(selectedMealType) {
                return false
            }
            guard !normalizedSearch.isEmpty else { return true }
            return meal.matchesMealsSearch(normalizedSearch)
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

    private func handleSavedMeal(mealID: UUID, meal: Meal?) {
        if let meal {
            viewModel.replaceMeal(meal)
        } else {
            Task {
                _ = await viewModel.refreshMeal(id: mealID, homeId: homeService.selectedHomeID)
            }
        }
    }
}

private struct MealDetailDestination: View {
    let mealID: UUID
    let selectedHomeID: UUID?
    @ObservedObject var viewModel: MealsViewModel
    let canFavorite: Bool
    let canEdit: Bool
    let onToggleFavorite: (Meal) -> Void
    let onEdit: () -> Void

    @State private var loadState: MealDetailLoadState = .idle

    private var resolvedMeal: Meal? {
        viewModel.meal(id: mealID) ?? loadState.loadedMeal
    }

    var body: some View {
        Group {
            if let meal = resolvedMeal {
                MealDetailView(
                    meal: meal,
                    isFavorite: viewModel.isFavorite(meal),
                    canFavorite: canFavorite,
                    canEdit: canEdit,
                    onToggleFavorite: { onToggleFavorite(meal) },
                    onEdit: onEdit
                )
            } else {
                switch loadState {
                case .idle, .loading:
                    MealMessageCard(
                        title: "Loading Meal",
                        message: "Loading this meal…",
                        systemImage: "hourglass"
                    )
                case .loaded:
                    EmptyView()
                case .unavailable:
                    MealMessageCard(
                        title: "Meal Unavailable",
                        message: "We could not find this meal. It may have been moved, archived, or deleted.",
                        systemImage: "fork.knife"
                    )
                case .failed(let message):
                    MealMessageCard(
                        title: "Meal Unavailable",
                        message: message,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }
            }
        }
        .task(id: detailLoadTaskID) {
            await loadMealIfNeeded()
        }
    }

    private var detailLoadTaskID: String {
        "\(mealID.uuidString)-\(selectedHomeID?.uuidString ?? "no-home")"
    }

    private func loadMealIfNeeded() async {
        let containsMeal = viewModel.meal(id: mealID) != nil
        logDetailLoad("open detail", containsMeal: containsMeal)

        guard !containsMeal else {
            loadState = .idle
            return
        }

        guard let selectedHomeID else {
            logDetailLoad("unavailable: no selected Home", containsMeal: false)
            loadState = .unavailable
            return
        }

        loadState = .loading
        logDetailLoad("targeted fetch started", containsMeal: false)
        guard let fetchedMeal = await viewModel.refreshMeal(id: mealID, homeId: selectedHomeID) else {
            logDetailLoad("unavailable: targeted fetch returned nil", containsMeal: viewModel.meal(id: mealID) != nil)
            loadState = .unavailable
            return
        }

        guard fetchedMeal.homeId == selectedHomeID else {
            logDetailLoad("unavailable: fetched meal Home mismatch", containsMeal: false, fetchedMeal: fetchedMeal)
            loadState = .unavailable
            return
        }

        logDetailLoad("targeted fetch succeeded", containsMeal: viewModel.meal(id: mealID) != nil, fetchedMeal: fetchedMeal)
        loadState = .loaded(fetchedMeal)
    }

    private func logDetailLoad(_ reason: String, containsMeal: Bool, fetchedMeal: Meal? = nil) {
        #if DEBUG
        print("========== MEAL DETAIL LOAD ==========")
        print("reason: \(reason)")
        print("route_meal_id: \(mealID.uuidString)")
        print("selected_home_id: \(selectedHomeID?.uuidString ?? "nil")")
        print("shared_view_model: \(ObjectIdentifier(viewModel))")
        print("shared_view_model_contains_meal: \(containsMeal)")
        if let fetchedMeal {
            print("fetched_meal_id: \(fetchedMeal.id.uuidString)")
            print("fetched_home_id: \(fetchedMeal.homeId.uuidString)")
            print("fetched_is_archived: \(fetchedMeal.isArchived)")
        }
        print("======================================")
        #endif
    }
}

private enum MealDetailLoadState: Equatable {
    case idle
    case loading
    case loaded(Meal)
    case unavailable
    case failed(String)

    var loadedMeal: Meal? {
        if case .loaded(let meal) = self {
            return meal
        }
        return nil
    }
}

private enum MealsLandingTab: String, CaseIterable, Identifiable {
    case recipes
    case mealPlan
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipes:
            return "Recipes"
        case .mealPlan:
            return "Meal Plan"
        case .favorites:
            return "Favorites"
        }
    }
}

private enum MealsRoute: Hashable {
    case library
    case addMeal
    case detail(UUID)
    case editMeal(UUID)
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

private struct MealPhotoThumbnail: View {
    let path: String?
    @State private var signedURL: URL?
    @State private var didFail = false
    private let mealService = MealService()

    var body: some View {
        ZStack {
            if let signedURL, !didFail {
                AsyncImage(url: signedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                            .onAppear { didFail = true }
                    case .empty:
                        ProgressView()
                            .tint(HomeyDashboardTheme.warmBrown)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: path) {
            await loadSignedURL()
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [HomeyDashboardTheme.warmBeige.opacity(0.82), HomeyDashboardTheme.selectedSidebarBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
        .accessibilityHidden(true)
    }

    private func loadSignedURL() async {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            signedURL = nil
            return
        }

        do {
            signedURL = try await mealService.createSignedMealPhotoURL(path: path)
            didFail = false
        } catch {
            signedURL = nil
            didFail = true
        }
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
