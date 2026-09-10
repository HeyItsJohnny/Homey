import SwiftUI

struct ExploreRecipesView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @EnvironmentObject private var session: AppSession
    @StateObject private var feed = ExploreRecipesViewModel()
    @State private var query = ExploreQuery()
    @State private var viewedRecipe: ExploreRecipe?
    @State private var plannedMeal: HomeyMeal?
    @State private var recipeToDelete: ExploreRecipe?
    @State private var busyIDs: Set<UUID> = []
    @State private var feedback: String?
    private let filters = RecipeLibraryFilter.allCases.filter { $0 != .favorites }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 14) {
                    RecipeLibrarySearchBar(search: $query.search, filter: $query.filter,
                        placeholder: "Search community recipes...", filters: filters)
                    RecipeLibraryFilterChips(selection: $query.filter, filters: filters)

                    if feed.isLoading && feed.recipes.isEmpty {
                        RecipeLibraryLoadingState(message: "Gathering community recipes…")
                    } else if let error = feed.errorMessage, feed.recipes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(HomeyColors.recipeGreenAccent)
                            Text(error).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                            Button("Retry") { Task { await feed.reset(query: query) } }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity).padding(.vertical, 36)
                    } else if feed.recipes.isEmpty && query.search.isEmpty && query.filter == .all {
                        emptyState
                    } else if feed.recipes.isEmpty {
                        RecipeLibraryNoMatches(title: "No recipes match your search") { query = ExploreQuery() }
                    } else {
                        ForEach(feed.recipes) { recipe in
                            RecipeCard(content: cardContent(recipe), width: geometry.size.width - 32,
                                favorite: nil, favoritePending: false, open: { viewedRecipe = recipe }, favoriteAction: nil) {
                                Button("View Recipe", systemImage: "book") { viewedRecipe = recipe }
                                Button("Add to Home Recipes", systemImage: "books.vertical") { Task { await addToHome(recipe) } }
                                Button("Add to Meal Plan", systemImage: "calendar.badge.plus") { Task { await addToMealPlan(recipe) } }
                                if recipe.createdBy == session.currentUser?.id {
                                    Divider()
                                    Button("Delete Community Recipe", systemImage: "trash", role: .destructive) { recipeToDelete = recipe }
                                }
                            }
                            .disabled(busyIDs.contains(recipe.id))
                            .onAppear { Task { await feed.loadMoreIfNeeded(near: recipe) } }
                        }
                        if feed.isLoading { ProgressView().tint(HomeyColors.recipeGreenAccent).padding() }
                        if let error = feed.errorMessage {
                            VStack(spacing: 8) {
                                Text(error).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                                Button("Retry") { Task { await feed.loadNextPage() } }.buttonStyle(.bordered)
                            }.padding()
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await feed.reset(query: query) }
        }
        .task(id: query) { await feed.update(query: query) }
        .navigationDestination(item: $viewedRecipe) { recipe in
            ExploreRecipeDestination(id: recipe.id, home: home, model: model)
        }
        .sheet(item: $plannedMeal) { RecipePlanSheet(meal: $0, home: home, model: model) }
        .confirmationDialog("Delete Community Recipe?", isPresented: .init(get: { recipeToDelete != nil }, set: { if !$0 { recipeToDelete = nil } }),
            titleVisibility: .visible, presenting: recipeToDelete) { recipe in
                Button("Delete Recipe", role: .destructive) { Task { await delete(recipe) } }
                Button("Cancel", role: .cancel) { recipeToDelete = nil }
            } message: { recipe in
                Text("Are you sure you want to permanently delete “\(recipe.title)” from the Homey community?")
            }
        .alert("Community Recipe", isPresented: .init(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(feedback ?? "") }
        .onChange(of: model.recipesRevision) { Task { await feed.reset(query: query) } }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 38)).foregroundStyle(HomeyColors.recipeGreenAccent)
                .frame(width: 84, height: 84).background(HomeyColors.recipeGreenAccent.opacity(0.1), in: Circle())
            Text("No community recipes found").font(HomeyTypography.title)
            Text("Community recipes will appear here.").foregroundStyle(HomeyColors.secondaryText)
        }.padding(28).frame(maxWidth: .infinity)
            .background(HomeyColors.recipeCardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
    }

    private func cardContent(_ recipe: ExploreRecipe) -> RecipeCardContent {
        RecipeCardContent(title: recipe.title, imageReference: recipe.imageURL, description: recipe.description,
            mealTypes: recipe.mealTypes, totalMinutes: recipe.displayedTotalMinutes,
            servings: recipe.displayedServings, badges: recipe.keywords + [recipe.cuisine].compactMap { $0 })
    }

    private func addToHome(_ summary: ExploreRecipe) async {
        guard !busyIDs.contains(summary.id) else { return }
        busyIDs.insert(summary.id); defer { busyIDs.remove(summary.id) }
        do {
            let recipe = try await ExploreRecipeService().recipe(id: summary.id)
            _ = try await MealsService().addToHome(recipe, homeId: home.id)
            await model.load(home: home)
            feedback = "Added to \(home.name)."
        } catch {
            await model.load(home: home)
            feedback = error.localizedDescription
        }
    }

    private func addToMealPlan(_ summary: ExploreRecipe) async {
        guard !busyIDs.contains(summary.id) else { return }
        busyIDs.insert(summary.id); defer { busyIDs.remove(summary.id) }
        do {
            let recipe = try await ExploreRecipeService().recipe(id: summary.id)
            let homeMealID = try await MealsService().addToHome(recipe, homeId: home.id)
            await model.load(home: home)
            guard let meal = model.homeRecipes.first(where: { $0.id == homeMealID }) else {
                throw MealsError.message("The recipe was added, but Homey couldn't open Meal Plan.")
            }
            plannedMeal = meal
        } catch {
            await model.load(home: home)
            feedback = error.localizedDescription
        }
    }

    private func delete(_ recipe: ExploreRecipe) async {
        recipeToDelete = nil
        guard recipe.createdBy == session.currentUser?.id, !busyIDs.contains(recipe.id) else { return }
        busyIDs.insert(recipe.id); defer { busyIDs.remove(recipe.id) }
        do {
            try await MealsService().deleteCommunityRecipe(recipe.id)
            feed.remove(id: recipe.id)
        } catch { feedback = "Homey couldn't delete this community recipe." }
    }
}

/// Loads full data, then presents the existing read-only Community detail.
struct ExploreRecipeDestination: View {
    let id: UUID
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @State private var recipe: CommunityRecipe?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let recipe {
                CommunityDetailView(recipe: recipe, home: home, model: model)
            } else if failed {
                ContentUnavailableView {
                    Label("Recipe unavailable", systemImage: "fork.knife")
                } description: {
                    Text("It may have been removed, or the connection was interrupted.")
                } actions: {
                    Button("Retry") { attempt += 1 }
                }
            } else { ProgressView().tint(HomeyColors.primary) }
        }
        .task(id: attempt) {
            failed = false
            do { recipe = try await ExploreRecipeService().recipe(id: id) }
            catch {
                guard !Task.isCancelled else { return }
                failed = true
                #if DEBUG
                print("Explore detail failed: \(String(reflecting: error))")
                #endif
            }
        }
    }
}
