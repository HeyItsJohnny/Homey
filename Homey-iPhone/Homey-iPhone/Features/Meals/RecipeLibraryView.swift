import SwiftUI

struct RecipeLibraryView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    let onAddRecipe: () -> Void
    let onExplore: () -> Void
    @State private var filter: RecipeLibraryFilter = .all
    @State private var search = ""
    @State private var viewedMeal: HomeyMeal?
    @State private var plannedMeal: HomeyMeal?
    @State private var recipeToRemove: HomeyMeal?
    @State private var removingIDs: Set<UUID> = []
    @State private var removalError: String?
    private var canRemove: Bool { home.role == .owner || home.role == .admin }
    @State private var pendingFavorites: [UUID: Bool] = [:]

    private var filteredRecipes: [HomeyMeal] {
        model.homeRecipes.filter { meal in
            (search.isEmpty || meal.name.localizedCaseInsensitiveContains(search)) &&
            (filter == .all || filter == .favorites && isFavorite(meal) || filter.mealType.map { meal.mealTypes.contains($0) } == true)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 14) {
                    RecipeLibrarySearchBar(search: $search, filter: $filter, placeholder: "Search your recipes...", filters: RecipeLibraryFilter.allCases)
                    RecipeLibraryFilterChips(selection: $filter, filters: RecipeLibraryFilter.allCases)
                    if model.isLoading && model.homeRecipes.isEmpty {
                        loadingState
                    } else if model.homeRecipes.isEmpty {
                        emptyState
                    } else if filteredRecipes.isEmpty {
                        RecipeLibraryNoMatches(title: "No matching recipes") { search = ""; filter = .all }
                    } else {
                        ForEach(filteredRecipes) { meal in
                            RecipeCard(content: cardContent(meal), width: geometry.size.width - 32, favorite: isFavorite(meal), favoritePending: pendingFavorites[meal.id] != nil,
                                open: { viewedMeal = meal }, favoriteAction: { toggleFavorite(meal) }) {
                                Button("View Recipe", systemImage: "book") { viewedMeal = meal }
                                Button("Add to Meal Plan", systemImage: "calendar.badge.plus") { plannedMeal = meal }
                                if canRemove {
                                    Divider()
                                    Button("Remove Recipe", systemImage: "trash", role: .destructive) { recipeToRemove = meal }
                                        .accessibilityLabel("Remove Recipe")
                                }
                            }
                                .disabled(removingIDs.contains(meal.id))
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
                .refreshable { await model.load(home: home) }
        }
        .navigationDestination(item: $viewedMeal) { RecipeDetailView(meal: $0, home: home, model: model) }
        .sheet(item: $plannedMeal) { RecipePlanSheet(meal: $0, home: home, model: model) }
        .confirmationDialog("Remove Recipe?", isPresented: .init(get: { recipeToRemove != nil }, set: { if !$0 { recipeToRemove = nil } }), titleVisibility: .visible, presenting: recipeToRemove) { meal in
            Button("Remove Recipe", role: .destructive) { Task { await removeRecipe(meal) } }
            Button("Cancel", role: .cancel) { recipeToRemove = nil }
        } message: { meal in
            Text("Are you sure you want to remove “\(meal.name)” from your Home Recipes?")
        }
        .alert("Couldn't Remove Recipe", isPresented: .init(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(removalError ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 38)).foregroundStyle(HomeyColors.recipeGreenAccent)
                .frame(width: 84, height: 84).background(HomeyColors.recipeGreenAccent.opacity(0.1), in: Circle())
            Text("No recipes yet").font(HomeyTypography.title)
            Text("Add your first recipe or explore community recipes.")
                .multilineTextAlignment(.center).foregroundStyle(HomeyColors.secondaryText)
            Button("Add Recipe", action: onAddRecipe).buttonStyle(.borderedProminent).tint(HomeyColors.recipeGreenAccent)
            Button("Explore Recipes", action: onExplore).tint(HomeyColors.recipeGreenAccent)
        }.padding(28).frame(maxWidth: .infinity)
            .background(HomeyColors.recipeCardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
    }

    private var loadingState: some View { RecipeLibraryLoadingState(message: "Gathering your recipes…") }

    private func cardContent(_ meal: HomeyMeal) -> RecipeCardContent {
        RecipeCardContent(title: meal.name, imageReference: meal.primaryPhotoPath, description: meal.description,
            mealTypes: meal.mealTypes, totalMinutes: (meal.prepTimeMinutes ?? 0) + (meal.cookTimeMinutes ?? 0),
            servings: meal.servings, badges: meal.tags + [meal.cuisine].compactMap { $0 })
    }

    private func removeRecipe(_ meal: HomeyMeal) async {
        guard canRemove, meal.homeId == home.id, !removingIDs.contains(meal.id) else { return }
        recipeToRemove = nil
        removingIDs.insert(meal.id)
        defer { removingIDs.remove(meal.id) }
        do {
            try await MealsService().removeHomeRecipe(meal, home: home)
            model.homeRecipes.removeAll { $0.id == meal.id }
            // Keep favorite records and planned meals intact; every library filter
            // derives from homeRecipes, so the archived card disappears everywhere.
        } catch {
            RecipeSaveDiagnostics.failure(error, stage: "removeHomeRecipe")
            removalError = "Homey couldn't remove this recipe. Please try again."
        }
    }

    private func isFavorite(_ meal: HomeyMeal) -> Bool { pendingFavorites[meal.id] ?? model.favoriteIDs.contains(meal.id) }
    private func toggleFavorite(_ meal: HomeyMeal) {
        guard pendingFavorites[meal.id] == nil else { return }
        pendingFavorites[meal.id] = !model.favoriteIDs.contains(meal.id)
        Task {
            await model.toggleFavorite(meal)
            pendingFavorites[meal.id] = nil // The model retains its original value if the request fails.
        }
    }
}

struct HomeRecipeThumbnail: View {
    let path: String?
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HomeyColors.recipeGreenAccent.opacity(0.08)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Image(systemName: "fork.knife").font(.title).foregroundStyle(HomeyColors.recipeGreenAccent.opacity(0.5))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
            .task(id: path) {
                image = nil
                guard let url = await MealsService().signedImageURL(path: path) else { return }
                let loaded = await ExploreImageCache.shared.image(url: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}

/// Wrap whole metadata labels/chips, never individual words within a metadata item.
struct RecipeBadgeFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 300, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
