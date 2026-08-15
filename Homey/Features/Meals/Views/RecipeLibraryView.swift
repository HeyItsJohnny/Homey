import SwiftUI

struct RecipeLibraryView: View {
    let meals: [Meal]
    let canCreate: Bool
    let canFavorite: Bool
    @Binding var searchText: String
    @Binding var selectedMealType: MealType?
    let isFavorite: (Meal) -> Bool
    let onToggleFavorite: (Meal) -> Void
    let onSelectMeal: (Meal) -> Void
    let onAddRecipe: () -> Void

    @State private var selectedCategory: RecipeLibraryCategory

    init(
        meals: [Meal],
        canCreate: Bool,
        canFavorite: Bool,
        searchText: Binding<String>,
        selectedMealType: Binding<MealType?>,
        isFavorite: @escaping (Meal) -> Bool,
        onToggleFavorite: @escaping (Meal) -> Void,
        onSelectMeal: @escaping (Meal) -> Void,
        onAddRecipe: @escaping () -> Void
    ) {
        self.meals = meals
        self.canCreate = canCreate
        self.canFavorite = canFavorite
        _searchText = searchText
        _selectedMealType = selectedMealType
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.onSelectMeal = onSelectMeal
        self.onAddRecipe = onAddRecipe
        _selectedCategory = State(initialValue: selectedMealType.wrappedValue.map(RecipeLibraryCategory.mealType) ?? .all)
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    searchAndFilterBar
                    categoryTabs
                    recipeContent
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Recipe Library")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedMealType) { _, newValue in
            guard selectedCategory.isMealTypeFilter || selectedCategory == .all else { return }
            selectedCategory = newValue.map(RecipeLibraryCategory.mealType) ?? .all
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe Library")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Browse every saved recipe for this Home.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer(minLength: 20)

            if canCreate {
                Button(action: onAddRecipe) {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                        Text("Add Recipe")
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 150)
                .accessibilityLabel("Add Recipe")
            }
        }
    }

    private var searchAndFilterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .accessibilityHidden(true)

                TextField("Search recipes...", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }

            Menu {
                ForEach(RecipeLibraryCategory.allCases) { category in
                    Button {
                        selectCategory(category)
                    } label: {
                        Label(category.title, systemImage: selectedCategory == category ? "checkmark" : category.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filter")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter recipes")
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(RecipeLibraryCategory.allCases) { category in
                    RecipeLibraryCategoryTab(
                        title: category.title,
                        isSelected: selectedCategory == category
                    ) {
                        selectCategory(category)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var recipeContent: some View {
        if meals.isEmpty {
            MealLibraryEmptyCard(canCreate: canCreate, onAddRecipe: onAddRecipe)
        } else if filteredMeals.isEmpty {
            MealLibraryEmptyCard(
                title: "No Matching Recipes",
                message: "Try a different search or filter.",
                canCreate: false,
                onAddRecipe: onAddRecipe
            )
        } else {
            LazyVStack(spacing: 20) {
                ForEach(filteredMeals) { meal in
                    RecipeLibraryRow(
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

    private var filteredMeals: [Meal] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return meals.filter { meal in
            switch selectedCategory {
            case .all:
                break
            case .favorites:
                guard isFavorite(meal) else { return false }
            case .mealType(let mealType):
                guard meal.mealTypes.contains(mealType) else { return false }
            }

            guard !normalizedSearch.isEmpty else { return true }
            return meal.matchesRecipeLibrarySearch(normalizedSearch)
        }
    }

    private func selectCategory(_ category: RecipeLibraryCategory) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedCategory = category
            switch category {
            case .all, .favorites:
                selectedMealType = nil
            case .mealType(let mealType):
                selectedMealType = mealType
            }
        }
    }
}

private struct RecipeLibraryRow: View {
    let meal: Meal
    let isFavorite: Bool
    let canFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            MealPhotoThumbnail(path: meal.primaryPhotoPath)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                Text(meal.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                if !meal.mealTypes.isEmpty {
                    Text(meal.mealTypes.map(\.displayName).joined(separator: " • "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .lineLimit(1)
                }

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                if let totalTimeText {
                    RecipeLibraryQuickInfo(systemImage: "clock", text: totalTimeText)
                }

                if let servingsText {
                    RecipeLibraryQuickInfo(systemImage: "fork.knife", text: servingsText)
                }

                if canFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(isFavorite ? HomeyDashboardTheme.coralAccent : HomeyDashboardTheme.warmBrown)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                }

                Menu {
                    Button("Open Recipe", action: onSelect)
                    if canFavorite {
                        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recipe actions")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .shadow(color: HomeyDashboardTheme.cardShadow, radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens recipe details")
    }

    private var totalTimeText: String? {
        let total = (meal.prepTimeMinutes ?? 0) + (meal.cookTimeMinutes ?? 0)
        return total > 0 ? "\(total) min" : nil
    }

    private var servingsText: String? {
        guard let servings = meal.servings else { return nil }
        return "\(servings) servings"
    }

    private var metadataText: String {
        var values: [String] = []
        if let cookTimeMinutes = meal.cookTimeMinutes, cookTimeMinutes > 0 {
            values.append("Cook \(cookTimeMinutes) min")
        }
        if let cuisine = meal.cuisine?.trimmingCharacters(in: .whitespacesAndNewlines), !cuisine.isEmpty {
            values.append(cuisine)
        }
        return values.joined(separator: " • ")
    }

    private var accessibilityLabel: String {
        [meal.name, meal.mealTypes.map(\.displayName).joined(separator: ", "), metadataText]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private struct RecipeLibraryQuickInfo: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(HomeyDashboardTheme.selectedSidebarBackground.opacity(0.72), in: Capsule())
    }
}

private struct RecipeLibraryCategoryTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? HomeyDashboardTheme.primaryText : HomeyDashboardTheme.secondaryText)
                Capsule()
                    .fill(isSelected ? HomeyDashboardTheme.warmBrown : .clear)
                    .frame(height: 3)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct MealLibraryEmptyCard: View {
    var title = "No Recipes Yet"
    var message = "Import a recipe or create one manually."
    let canCreate: Bool
    let onAddRecipe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            if canCreate {
                Button(action: onAddRecipe) {
                    Label("Add Recipe", systemImage: "plus")
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 150)
                .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .dashboardCard(cornerRadius: 28)
    }
}

private enum RecipeLibraryCategory: Identifiable, Hashable {
    case all
    case favorites
    case mealType(MealType)

    static var allCases: [RecipeLibraryCategory] {
        [.all, .favorites] + MealType.allCases.map(RecipeLibraryCategory.mealType)
    }

    var id: String {
        switch self {
        case .all:
            return "all"
        case .favorites:
            return "favorites"
        case .mealType(let mealType):
            return mealType.rawValue
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All Recipes"
        case .favorites:
            return "Favorites"
        case .mealType(.snack):
            return "Snacks"
        case .mealType(.dessert):
            return "Desserts"
        case .mealType(let mealType):
            return mealType.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "list.bullet"
        case .favorites:
            return "heart"
        case .mealType(let mealType):
            return mealType.systemImageName
        }
    }

    var isMealTypeFilter: Bool {
        if case .mealType = self {
            return true
        }
        return false
    }
}

private extension Meal {
    func matchesRecipeLibrarySearch(_ normalizedSearch: String) -> Bool {
        [name, description, cuisine, notes, sourceName]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedSearch) }
            || tags.contains { $0.lowercased().contains(normalizedSearch) }
            || mealTypes.contains { $0.displayName.lowercased().contains(normalizedSearch) }
    }
}
