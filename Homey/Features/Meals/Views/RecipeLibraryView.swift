import SwiftUI

struct RecipeLibraryView: View {
    let meals: [Meal]
    let canCreate: Bool
    let canDelete: Bool
    let canFavorite: Bool
    @Binding var searchText: String
    @Binding var selectedMealType: MealType?
    let isFavorite: (Meal) -> Bool
    let onToggleFavorite: (Meal) -> Void
    let onDeleteMeal: (Meal) -> Void
    let onSelectMeal: (Meal) -> Void
    let onAddRecipe: () -> Void

    @State private var selectedCategory: RecipeLibraryCategory
    @State private var mealPendingDeletion: Meal?
    @State private var browseLayout: RecipeLibraryBrowseLayout = .list

    init(
        meals: [Meal],
        canCreate: Bool,
        canDelete: Bool,
        canFavorite: Bool,
        searchText: Binding<String>,
        selectedMealType: Binding<MealType?>,
        isFavorite: @escaping (Meal) -> Bool,
        onToggleFavorite: @escaping (Meal) -> Void,
        onDeleteMeal: @escaping (Meal) -> Void,
        onSelectMeal: @escaping (Meal) -> Void,
        onAddRecipe: @escaping () -> Void
    ) {
        self.meals = meals
        self.canCreate = canCreate
        self.canDelete = canDelete
        self.canFavorite = canFavorite
        _searchText = searchText
        _selectedMealType = selectedMealType
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.onDeleteMeal = onDeleteMeal
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
        .confirmationDialog(
            "Delete Recipe?",
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible,
            presenting: mealPendingDeletion
        ) { meal in
            Button("Delete Recipe", role: .destructive) {
                onDeleteMeal(meal)
                mealPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                mealPendingDeletion = nil
            }
        } message: { meal in
            Text("Delete \(meal.name) from this Home? Future planned meal events for this recipe will be removed from the calendar. Past meal history will be preserved when needed.")
        }
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

            RecipeLibraryBrowseLayoutToggle(selection: $browseLayout)
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
            switch browseLayout {
            case .list:
                LazyVStack(spacing: 20) {
                    ForEach(filteredMeals) { meal in
                        RecipeLibraryRow(
                            meal: meal,
                            isFavorite: isFavorite(meal),
                            canFavorite: canFavorite,
                            canDelete: canDelete,
                            onToggleFavorite: { onToggleFavorite(meal) },
                            onDelete: { mealPendingDeletion = meal },
                            onSelect: { onSelectMeal(meal) }
                        )
                    }
                }
            case .grid:
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredMeals) { meal in
                        RecipeLibraryCard(
                            meal: meal,
                            isFavorite: isFavorite(meal),
                            canFavorite: canFavorite,
                            canDelete: canDelete,
                            onToggleFavorite: { onToggleFavorite(meal) },
                            onDelete: { mealPendingDeletion = meal },
                            onSelect: { onSelectMeal(meal) }
                        )
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 230), spacing: 16)]
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { mealPendingDeletion != nil },
            set: { if !$0 { mealPendingDeletion = nil } }
        )
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
    let canDelete: Bool
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
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
                    if canDelete {
                        Button("Delete Recipe", role: .destructive, action: onDelete)
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
        .shadow(color: HomeyDashboardTheme.shadow, radius: 18, x: 0, y: 10)
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

private struct RecipeLibraryCard: View {
    let meal: Meal
    let isFavorite: Bool
    let canFavorite: Bool
    let canDelete: Bool
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MealPhotoThumbnail(path: meal.primaryPhotoPath)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(meal.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if let totalTimeText {
                        Label(totalTimeText, systemImage: "clock")
                    }

                    if let servingsText {
                        Label(servingsText, systemImage: "fork.knife")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

                if let cuisine = meal.cuisine?.trimmingCharacters(in: .whitespacesAndNewlines), !cuisine.isEmpty {
                    Text(cuisine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    ForEach(Array(meal.mealTypes.prefix(2)), id: \.self) { type in
                        Text(type.displayName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }
                }
            }

            HStack(spacing: 8) {
                if canFavorite {
                    Button(action: onToggleFavorite) {
                        Label(isFavorite ? "Favorite" : "Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(isFavorite ? HomeyDashboardTheme.coralAccent : HomeyDashboardTheme.warmBrown)
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                }

                Menu {
                    Button("Open Recipe", action: onSelect)
                    if canFavorite {
                        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
                    }
                    if canDelete {
                        Button("Delete Recipe", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 38, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recipe actions")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .shadow(color: HomeyDashboardTheme.shadow, radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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

    private var accessibilityLabel: String {
        var parts = [meal.name]
        let mealTypes = meal.mealTypes.map(\.displayName).joined(separator: ", ")
        if !mealTypes.isEmpty { parts.append(mealTypes) }
        if let totalTimeText { parts.append(totalTimeText) }
        if isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }
}

private enum RecipeLibraryBrowseLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .grid:
            return "square.grid.2x2"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .list:
            return "List view"
        case .grid:
            return "Grid view"
        }
    }
}

private struct RecipeLibraryBrowseLayoutToggle: View {
    @Binding var selection: RecipeLibraryBrowseLayout

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RecipeLibraryBrowseLayout.allCases) { layout in
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

struct RecipeLibraryCategoryTab: View {
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
