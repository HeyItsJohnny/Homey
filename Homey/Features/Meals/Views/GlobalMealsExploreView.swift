import SwiftUI

struct GlobalMealsExploreView: View {
    @ObservedObject var viewModel: GlobalMealsExploreViewModel
    let selectedHomeID: UUID?
    let selectedMealType: MealType?
    @Binding var isFiltersPresented: Bool
    let onOpenHomeMeal: (UUID) -> Void
    let onHomeMealAdded: (UUID) -> Void
    let onContributeManualRecipe: () -> Void
    let onContributeRecipeURL: () -> Void

    @State private var browseLayout: GlobalMealsBrowseLayout = .grid
    @State private var selectedDetailMeal: GlobalMeal?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let successMessage = viewModel.successMessage {
                GlobalMealStatusBanner(message: successMessage, homeMealId: viewModel.addedHomeMealId, onOpenHomeMeal: onOpenHomeMeal)
            }

            if let errorMessage = viewModel.errorMessage, viewModel.meals.isEmpty, viewModel.trendingMeals.isEmpty {
                GlobalMealMessageCard(
                    title: "Community Recipes",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Retry"
                ) {
                    viewModel.reload()
                }
            } else {
                exploreContent
            }
        }
        .task(id: GlobalMealsExploreLoadKey(homeId: selectedHomeID, selectedMealType: selectedMealType)) {
            viewModel.configure(homeId: selectedHomeID, selectedMealType: selectedMealType)
        }
        .sheet(item: $selectedDetailMeal) { meal in
            GlobalMealDetailView(
                meal: meal,
                viewModel: viewModel,
                addState: viewModel.addStates[meal.id] ?? .available,
                onOpenHomeMeal: onOpenHomeMeal,
                onHomeMealAdded: onHomeMealAdded
            )
        }
        .sheet(isPresented: $isFiltersPresented) {
            GlobalMealsFiltersView(filters: $viewModel.filters)
        }
    }

    private var exploreContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroContainer
            browseContainer
        }
    }

    private var visibleRecipeCount: Int {
        max(viewModel.meals.count, viewModel.trendingMeals.count)
    }

    private var heroContainer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                CommunityRecipesIntroCard(
                    recipeCount: visibleRecipeCount,
                    onContributeManualRecipe: onContributeManualRecipe,
                    onContributeRecipeURL: onContributeRecipeURL
                )
                    .frame(width: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                trendingSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top, spacing: 16) {
                CommunityRecipesIntroCard(
                    recipeCount: visibleRecipeCount,
                    onContributeManualRecipe: onContributeManualRecipe,
                    onContributeRecipeURL: onContributeRecipeURL
                )
                    .frame(width: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                trendingSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Trending Now",
                subtitle: "Popular recipes this week in Homey homes.",
                actionTitle: viewModel.trendingMeals.isEmpty ? nil : "View All >"
            ) {
                viewModel.filters.sort = .mostSaved
            }

            if viewModel.isLoadingInitial && viewModel.trendingMeals.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            GlobalMealSkeletonCard(width: 232, imageHeight: 126)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            } else if viewModel.trendingMeals.isEmpty {
                GlobalMealMessageCard(title: "Community recipes are coming soon.", message: "Check back for shared recipes from Homey homes.", systemImage: "sparkles")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(viewModel.trendingMeals) { meal in
                            GlobalMealCard(
                                meal: meal,
                                style: .compact,
                                addState: viewModel.addStates[meal.id] ?? .available,
                                onSelect: { selectedDetailMeal = meal },
                                onAdd: { addToHome(meal) },
                                onOpenHomeMeal: onOpenHomeMeal
                            )
                            .frame(width: 232)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var browseContainer: some View {
        VStack(alignment: .leading, spacing: 18) {
            browseHeader

            if viewModel.isLoadingInitial && viewModel.meals.isEmpty {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(0..<6, id: \.self) { _ in
                        GlobalMealSkeletonCard(width: nil, imageHeight: 136)
                    }
                }
            } else if viewModel.meals.isEmpty {
                GlobalMealMessageCard(
                    title: viewModel.searchText.isEmpty && !viewModel.filters.hasActiveFilters ? "Community recipes are coming soon." : "No recipes matched your filters.",
                    message: viewModel.searchText.isEmpty && !viewModel.filters.hasActiveFilters ? "Shared recipes will appear here when they are available." : "Try a different search or filter combination.",
                    systemImage: "fork.knife"
                )
            } else {
                switch browseLayout {
                case .grid:
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(viewModel.meals) { meal in
                            GlobalMealCard(
                                meal: meal,
                                style: .standard,
                                addState: viewModel.addStates[meal.id] ?? .available,
                                onSelect: { selectedDetailMeal = meal },
                                onAdd: { addToHome(meal) },
                                onOpenHomeMeal: onOpenHomeMeal
                            )
                            .onAppear {
                                viewModel.loadNextPageIfNeeded(currentMeal: meal)
                            }
                        }
                    }
                case .list:
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.meals) { meal in
                            GlobalMealListRow(
                                meal: meal,
                                addState: viewModel.addStates[meal.id] ?? .available,
                                onSelect: { selectedDetailMeal = meal },
                                onAdd: { addToHome(meal) },
                                onOpenHomeMeal: onOpenHomeMeal
                            )
                            .onAppear {
                                viewModel.loadNextPageIfNeeded(currentMeal: meal)
                            }
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(HomeyDashboardTheme.warmBrown)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }

            featureStrip
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }

    private var browseHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 14) {
                browseTitle
                Spacer()
                browseControls
            }

            VStack(alignment: .leading, spacing: 12) {
                browseTitle
                browseControls
            }
        }
    }

    private var browseTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Browse All Recipes")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text("Community recipes you can save to this Home.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private var browseControls: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(GlobalMealsSort.allCases) { sort in
                    Button {
                        viewModel.filters.sort = sort
                    } label: {
                        if viewModel.filters.sort == sort {
                            Label(sort.title, systemImage: "checkmark")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Sort by: \(viewModel.filters.sort.title)")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)

            GlobalMealsBrowseLayoutToggle(selection: $browseLayout)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 230), spacing: 16)]
    }

    private var featureStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            GlobalMealInfoCard(title: "Add to Your Home", message: "Save any recipe to your Home with one tap.", systemImage: "plus.circle.fill")
            GlobalMealInfoCard(title: "Make It Your Own", message: "Customize ingredients, notes, photos, and cooking details.", systemImage: "slider.horizontal.3")
            GlobalMealInfoCard(title: "Plan & Cook", message: "Use saved recipes with your Meal Planner and Calendar.", systemImage: "calendar.badge.checkmark")
            GlobalMealInfoCard(title: "Share Your Favorites", message: "Sharing recipes with other Homey homes is coming later.", systemImage: "square.and.arrow.up")
        }
        .padding(.top, 4)
    }

    private func sectionHeader(title: String, subtitle: String, actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .buttonStyle(.plain)
            }
        }
    }

    private func addToHome(_ meal: GlobalMeal) {
        Task {
            guard let result = await viewModel.addToHome(meal) else { return }
            onHomeMealAdded(result.homeMealId)
        }
    }
}

private struct GlobalMealsExploreLoadKey: Hashable {
    let homeId: UUID?
    let selectedMealType: MealType?
}

private enum GlobalMealsBrowseLayout: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .grid:
            return "square.grid.2x2"
        case .list:
            return "list.bullet"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .grid:
            return "Grid view"
        case .list:
            return "List view"
        }
    }
}

private struct GlobalMealsBrowseLayoutToggle: View {
    @Binding var selection: GlobalMealsBrowseLayout

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GlobalMealsBrowseLayout.allCases) { layout in
                Button {
                    selection = layout
                } label: {
                    Image(systemName: layout.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selection == layout ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                        .frame(width: 36, height: 34)
                        .background(selection == layout ? HomeyDashboardTheme.selectedSidebarBackground : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layout.accessibilityLabel)
            }
        }
        .padding(3)
        .background(HomeyDashboardTheme.cardBackground, in: Capsule())
        .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
    }
}

private struct GlobalMealCard: View {
    enum Style {
        case compact
        case standard
    }

    let meal: GlobalMeal
    let style: Style
    let addState: GlobalMealAddState
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onOpenHomeMeal: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                GlobalMealPhotoView(path: meal.primaryPhotoPath)
                    .frame(height: style == .compact ? 126 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if meal.isRecentlyPublished {
                    Text("New")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(HomeyDashboardTheme.sageAccent, in: Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(meal.name)
                    .font(style == .compact ? .subheadline.weight(.bold) : .headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if style == .standard, meal.saveCount > 0 {
                        Label("\(meal.saveCount) saves", systemImage: "bookmark.fill")
                            .foregroundStyle(HomeyDashboardTheme.orangeAccent)
                    }

                    if let timeText = primaryTimeText {
                        Label(timeText, systemImage: "clock")
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                }
                .font(.caption.weight(.semibold))

                if let cuisine = meal.cuisine, !cuisine.isEmpty {
                    Text(cuisine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    ForEach(Array(meal.mealTypeValues.prefix(style == .compact ? 1 : 2)), id: \.self) { type in
                        Text(type.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }
                }
            }

            addButton
        }
        .padding(14)
        .dashboardCard(cornerRadius: 26)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens community recipe details")
    }

    @ViewBuilder
    private var addButton: some View {
        switch addState {
        case .available:
            Button(action: onAdd) {
                Label("Add to Home", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(HomeyDashboardTheme.warmBrown)
            .accessibilityLabel("Add \(meal.name) to Home")
        case .adding:
            Button {} label: {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Adding")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .controlSize(.small)
            .disabled(true)
        case .added(let homeMealId):
            Button {
                onOpenHomeMeal(homeMealId)
            } label: {
                Label("In Your Recipes", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(HomeyDashboardTheme.sageAccent)
            .accessibilityLabel("Open \(meal.name) in Your Recipes")
        }
    }

    private var accessibilityLabel: String {
        var parts = [meal.name]
        if let cuisine = meal.cuisine { parts.append(cuisine) }
        if let timeText = primaryTimeText { parts.append(timeText) }
        if meal.saveCount > 0 { parts.append("\(meal.saveCount) saves") }
        return parts.joined(separator: ", ")
    }

    private var primaryTimeText: String? {
        if style == .compact, let prepTime = meal.prepTimeMinutes {
            return "Prep \(prepTime) min"
        }
        if let totalTime = meal.resolvedTotalTimeMinutes {
            return "\(totalTime) min"
        }
        return nil
    }
}

private struct GlobalMealListRow: View {
    let meal: GlobalMeal
    let addState: GlobalMealAddState
    let onSelect: () -> Void
    let onAdd: () -> Void
    let onOpenHomeMeal: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            GlobalMealPhotoView(path: meal.primaryPhotoPath)
                .frame(width: 96, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(meal.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    ForEach(Array(meal.mealTypeValues.prefix(2)), id: \.self) { type in
                        Text(type.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }
                    if let cuisine = meal.cuisine, !cuisine.isEmpty {
                        Text(cuisine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                    if let totalTime = meal.resolvedTotalTimeMinutes {
                        Label("\(totalTime) min", systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                }

                HStack(spacing: 10) {
                    if meal.saveCount > 0 {
                        Label("\(meal.saveCount) saves", systemImage: "bookmark.fill")
                            .foregroundStyle(HomeyDashboardTheme.orangeAccent)
                    }
                    if let sourceName = meal.sourceName, !sourceName.isEmpty {
                        Text(sourceName)
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                }
                .font(.caption.weight(.semibold))
            }

            Spacer(minLength: 12)

            listAction
                .frame(width: 150)
        }
        .padding(12)
        .dashboardCard(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(meal.name)
        .accessibilityHint("Opens community recipe details")
    }

    @ViewBuilder
    private var listAction: some View {
        switch addState {
        case .available:
            Button(action: onAdd) {
                Label("Add to Home", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(HomeyDashboardTheme.warmBrown)
        case .adding:
            Button {} label: {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
        case .added(let homeMealId):
            Button {
                onOpenHomeMeal(homeMealId)
            } label: {
                Label("Open Recipe", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(HomeyDashboardTheme.sageAccent)
        }
    }
}

private struct GlobalMealDetailView: View {
    let meal: GlobalMeal
    @ObservedObject var viewModel: GlobalMealsExploreViewModel
    let addState: GlobalMealAddState
    let onOpenHomeMeal: (UUID) -> Void
    let onHomeMealAdded: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authenticationService: AuthenticationService
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hero

                        if viewModel.isLoadingDetail && viewModel.selectedDetail == nil {
                            GlobalMealSkeletonCard(width: nil)
                        } else if let detail = viewModel.selectedDetail {
                            detailContent(detail)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Community Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if canDeleteCommunityRecipe {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            if viewModel.isDeletingCommunityRecipe(displayedMeal.id) {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Delete Recipe", systemImage: "trash")
                            }
                        }
                        .disabled(viewModel.isDeletingCommunityRecipe(displayedMeal.id))
                    }
                }
            }
        }
        .task(id: meal.id) {
            await viewModel.loadDetail(for: meal)
        }
        .confirmationDialog(
            "Delete Community Recipe?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Recipe", role: .destructive) {
                deleteCommunityRecipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove this recipe from Community Recipes.")
        }
    }

    private var displayedMeal: GlobalMeal {
        viewModel.selectedDetail?.meal ?? meal
    }

    private var canDeleteCommunityRecipe: Bool {
        guard let currentUserId = authenticationService.currentUser?.id,
              let createdBy = displayedMeal.createdBy else {
            return false
        }
        return currentUserId == createdBy
    }

    private var hero: some View {
        let displayedMeal = displayedMeal
        return VStack(alignment: .leading, spacing: 14) {
            GlobalMealPhotoView(path: displayedMeal.primaryPhotoPath)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(displayedMeal.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let description = displayedMeal.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                metadataGrid(for: displayedMeal)
                primaryAction
            }
            .padding(20)
        }
        .dashboardCard(cornerRadius: 28)
    }

    private func detailContent(_ detail: GlobalMealDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !detail.ingredients.isEmpty {
                GlobalMealDetailSection(title: "Ingredients") {
                    ForEach(detail.ingredients) { ingredient in
                        Text(ingredient.displayText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }
                }
            }

            if !detail.steps.isEmpty {
                GlobalMealDetailSection(title: "Directions") {
                    ForEach(detail.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(step.sortOrder + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(HomeyDashboardTheme.warmBrown, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.stepText)
                                    .font(.subheadline)
                                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                            }
                        }
                    }
                }
            }

            GlobalMealDetailSection(title: "Source") {
                if let sourceURL = meal.sourceURL, let url = URL(string: sourceURL) {
                    Link(meal.sourceName ?? sourceURL, destination: url)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                } else if let sourceName = meal.sourceName {
                    Text(sourceName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                }

                detailRow("Saved", value: "\(meal.saveCount) \(meal.saveCount == 1 ? "Home" : "Homes")", systemImage: "house")
            }

            if let nutrition = meal.nutrition, !nutrition.rows.isEmpty {
                GlobalMealDetailSection(title: "Nutrition") {
                    ForEach(nutrition.rows, id: \.0) { row in
                        detailRow(row.0, value: row.1, systemImage: "leaf")
                    }
                }
            }
        }
    }

    private func deleteCommunityRecipe() {
        let mealToDelete = displayedMeal
        Task {
            let didDelete = await viewModel.deleteCommunityRecipe(mealToDelete)
            if didDelete {
                dismiss()
            }
        }
    }

    private var primaryAction: some View {
        Group {
            switch addState {
            case .available:
                Button {
                    Task {
                        guard let result = await viewModel.addToHome(meal) else { return }
                        onHomeMealAdded(result.homeMealId)
                    }
                } label: {
                    Label("Add to Home", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
            case .adding:
                Button {} label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Adding")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(true)
            case .added(let homeMealId):
                Button {
                    dismiss()
                    onOpenHomeMeal(homeMealId)
                } label: {
                    Label("Open Recipe", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
            }
        }
    }

    private func metadataGrid(for meal: GlobalMeal) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            if !meal.mealTypes.isEmpty {
                let mealTypeText = meal.mealTypeValues.isEmpty ? meal.mealTypes.joined(separator: ", ") : meal.mealTypeValues.map(\.displayName).joined(separator: ", ")
                detailPill(mealTypeText, systemImage: "fork.knife")
            }
            if let cuisine = meal.cuisine, !cuisine.isEmpty {
                detailPill(cuisine, systemImage: "globe.americas")
            }
            if let prep = meal.prepTimeMinutes {
                detailPill("Prep \(prep) min", systemImage: "clock")
            }
            if let cook = meal.cookTimeMinutes {
                detailPill("Cook \(cook) min", systemImage: "flame")
            }
            if let total = meal.resolvedTotalTimeMinutes {
                detailPill("Total \(total) min", systemImage: "timer")
            }
            if let servings = meal.servings {
                detailPill("Serves \(servings)", systemImage: "person.2")
            }
        }
    }

    private func detailPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailRow(_ title: String, value: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
    }
}

private struct GlobalMealPhotoView: View {
    let path: String?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let imageURL, !didFail {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        fallback.onAppear { didFail = true }
                    case .empty:
                        ProgressView().tint(HomeyDashboardTheme.warmBrown)
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
        .onChange(of: path) { _, _ in
            didFail = false
        }
    }

    private var imageURL: URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
              let url = URL(string: path),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url
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

}

private struct GlobalMealsFiltersView: View {
    @Binding var filters: GlobalMealsFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuisine") {
                    TextField("Any cuisine", text: $filters.cuisine)
                        .textInputAutocapitalization(.words)
                }

                Section("Total Time") {
                    Picker("Total Time", selection: $filters.maximumTotalTimeMinutes) {
                        Text("Any").tag(Int?.none)
                        Text("Under 15 min").tag(Int?.some(15))
                        Text("Under 30 min").tag(Int?.some(30))
                        Text("Under 60 min").tag(Int?.some(60))
                    }
                }

                Section("Sort") {
                    Picker("Sort", selection: $filters.sort) {
                        ForEach(GlobalMealsSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filters = GlobalMealsFilters()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CommunityRecipesIntroCard: View {
    let recipeCount: Int
    let onContributeManualRecipe: () -> Void
    let onContributeRecipeURL: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 48, height: 48)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Community Recipes")
                .font(.title2.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Discover recipes shared by Homey families around the world.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label(recipeCount == 0 ? "Total community recipes" : "\(recipeCount) community recipes loaded", systemImage: "book.closed")
                Label("Discover new meals", systemImage: "magnifyingglass")
                Label("One tap to add to your Home", systemImage: "plus.circle")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Menu {
                Button("Manual Recipe", action: onContributeManualRecipe)
                Button("Import from URL", action: onContributeRecipeURL)
            } label: {
                Label("Contribute Recipe", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(HomeyDashboardTheme.warmBrown, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(18)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct GlobalMealInfoCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 38, height: 38)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .dashboardCard(cornerRadius: 22)
    }
}

private struct GlobalMealMessageCard: View {
    let title: String
    let message: String
    let systemImage: String
    var buttonTitle: String?
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
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }
}

private struct GlobalMealStatusBanner: View {
    let message: String
    let homeMealId: UUID?
    let onOpenHomeMeal: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Spacer()
            if let homeMealId {
                Button("View Recipe") {
                    onOpenHomeMeal(homeMealId)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .dashboardCard(cornerRadius: 18)
    }
}

private struct GlobalMealDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct GlobalMealSkeletonCard: View {
    let width: CGFloat?
    var imageHeight: CGFloat = 138

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(0.35))
                .frame(height: imageHeight)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(0.35))
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(0.24))
                .frame(width: 120, height: 14)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(0.28))
                .frame(height: 36)
        }
        .padding(14)
        .frame(width: width)
        .dashboardCard(cornerRadius: 26)
        .redacted(reason: .placeholder)
    }
}

private extension GlobalRecipeIngredient {
    var displayText: String {
        var parts: [String] = []
        if let quantity {
            parts.append(quantity)
        }
        parts.append(ingredientName)
        if isOptional {
            parts.append("optional")
        }
        return parts.joined(separator: " ")
    }
}

private extension GlobalMealAddResult {
    var homeMealId: UUID {
        switch self {
        case .added(let homeMealId), .alreadyExists(let homeMealId), .addedPhotoCopyFailed(let homeMealId):
            return homeMealId
        }
    }
}
