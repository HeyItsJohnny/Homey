import SwiftUI

struct RecipeDetailView: View {
    let meal: HomeyMeal
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: HomeyRecipeDetail?
    @State private var showPlan = false
    @State private var showGrocery = false
    @State private var showEditor = false
    @State private var loadError: String?
    @State private var loading = true
    @State private var loadID = UUID()
    @State private var pendingFavorite: Bool?
    private let service = MealsService()
    private var currentMeal: HomeyMeal { model.homeRecipes.first { $0.id == meal.id } ?? meal }
    private var favorite: Bool { pendingFavorite ?? model.favoriteIDs.contains(meal.id) }
    private var presentation: RecipeDetailPresentation {
        let ingredients = (detail?.ingredients ?? []).map { ingredient in
            RecipeDetailIngredientItem(id: ingredient.id.uuidString, text: ingredientText(ingredient),
                preparation: ingredient.preparation, notes: ingredient.notes, isOptional: ingredient.isOptional)
        }
        let directions = (detail?.steps ?? []).map { step in
            RecipeDetailDirectionItem(id: step.id.uuidString, number: step.stepNumber,
                text: step.instruction, timerMinutes: step.timerMinutes)
        }
        let total = (currentMeal.prepTimeMinutes ?? 0) + (currentMeal.cookTimeMinutes ?? 0)
        return RecipeDetailPresentation(title: currentMeal.name, imageReference: currentMeal.primaryPhotoPath,
            description: currentMeal.description, mealTypes: currentMeal.mealTypes, totalMinutes: total > 0 ? total : nil,
            servings: currentMeal.servings, ingredients: ingredients, directions: directions,
            sourceName: currentMeal.sourceName, sourceURL: currentMeal.sourceURL, notes: currentMeal.notes,
            cuisine: currentMeal.cuisine, difficulty: currentMeal.difficulty?.rawValue.capitalized,
            prepMinutes: currentMeal.prepTimeMinutes, cookMinutes: currentMeal.cookTimeMinutes, tags: currentMeal.tags)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Label("Recipes", systemImage: "chevron.left").font(.headline)
                        .frame(minHeight: 44)
                }
                Spacer()
                Button { showEditor = true } label: {
                    Label("Edit", systemImage: "pencil").font(.headline)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(HomeyColors.recipeCardBackground, in: Capsule())
                }.disabled(detail == nil || loading)
            }.buttonStyle(.plain).foregroundStyle(HomeyColors.recipeGreenAccent)
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(currentMeal.name).font(HomeyTypography.hero)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                            RecipeFavoriteButton(favorite: favorite, pending: pendingFavorite != nil, action: toggleFavorite)
                        }
                        Text("View and manage your recipe details.").font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    }
                    RecipeDetailHero(imageReference: currentMeal.primaryPhotoPath)
                    RecipeDetailSummaryCard(presentation: presentation, favorite: favorite,
                        favoritePending: pendingFavorite != nil, favoriteAction: toggleFavorite,
                        showsTitleAndFavorite: false)
                    if loading {
                        HStack(spacing: 12) { ProgressView(); Text("Loading your recipe…").font(.subheadline) }
                            .frame(maxWidth: .infinity).padding(24).recipeDetailCard()
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 12) {
                            HomeyErrorView(message: loadError)
                            Button("Try Again") { Task { await loadDetail() } }.buttonStyle(.bordered)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).recipeDetailCard()
                    } else {
                        RecipeDetailIngredientsCard(ingredients: presentation.ingredients)
                        RecipeDetailDirectionsCard(directions: presentation.directions)
                    }
                    quickActions
                    RecipeDetailAdditionalCard(presentation: presentation)
                }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 28)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .background(HomeyColors.recipeBackground.ignoresSafeArea())
        .foregroundStyle(HomeyColors.text)
        .tint(HomeyColors.recipeGreenAccent)
        .navigationTitle("Recipe")
        .toolbar(.hidden, for: .navigationBar)
        .task(id: currentMeal) { await loadDetail() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await loadDetail() } }) {
            if let detail {
                RecipeEditorView(home: home, model: model, initialDraft: RecipeDraft(detail: detail), showsImportMetadata: true, existingMeal: currentMeal)
            }
        }
        .sheet(isPresented: $showPlan) { RecipePlanSheet(meal: currentMeal, home: home, model: model) }
        .alert("Groceries", isPresented: $showGrocery) { Button("OK") {} } message: {
            Text("Grocery-list integration is not available in the current backend contract yet.")
        }
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            RecipeDetailActionRow(title: "Add to Meal Plan", icon: "calendar", color: HomeyColors.recipeGreenAccent) { showPlan = true }
            Divider().padding(.leading, 66)
            RecipeDetailActionRow(title: "Add ingredients to Groceries", icon: "cart", color: HomeyColors.primary) { showGrocery = true }
        }.padding(.horizontal, 16).padding(.vertical, 6).recipeDetailCard()
    }

    private func loadDetail() async {
        let requestID = UUID()
        loadID = requestID
        loading = true
        loadError = nil
        let requestedMeal = currentMeal
        do {
            let loaded = try await service.detail(for: requestedMeal)
            guard !Task.isCancelled, loadID == requestID else { return }
            detail = loaded
            loading = false
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            detail = nil
            loading = false
            loadError = "Couldn’t load this recipe. Please try again."
        }
    }

    private func toggleFavorite() {
        guard pendingFavorite == nil else { return }
        pendingFavorite = !model.favoriteIDs.contains(meal.id)
        Task {
            await model.toggleFavorite(currentMeal)
            pendingFavorite = nil
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private func ingredientText(_ item: RecipeIngredient) -> String {
        [item.quantity.map { String($0) }, item.unit, item.ingredientName].compactMap { nonempty($0) }.joined(separator: " ")
    }
}
