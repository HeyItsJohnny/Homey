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
    @State private var confirmsRemoval = false
    @State private var removing = false
    @State private var removalError: String?
    private let service = MealsService()
    private var currentMeal: HomeyMeal { model.homeRecipes.first { $0.id == meal.id } ?? meal }
    private var favorite: Bool { pendingFavorite ?? model.favoriteIDs.contains(meal.id) }
    private var canRemove: Bool { home.role == .owner || home.role == .admin }
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
                Menu {
                    Button("Edit", systemImage: "pencil") { showEditor = true }
                    Button("Add to Plan", systemImage: "calendar.badge.plus") { showPlan = true }
                    Button("Add to Groceries", systemImage: "cart") { showGrocery = true }
                    if canRemove {
                        Divider()
                        Button("Remove Recipe", systemImage: "trash", role: .destructive) { confirmsRemoval = true }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
                        .background(HomeyColors.recipeCardBackground, in: Circle())
                }
                .disabled(detail == nil || loading || removing)
                .accessibilityLabel("Recipe actions")
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
            Text("Coming Soon")
        }
        .confirmationDialog("Remove Recipe?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove Recipe", role: .destructive) { Task { await removeRecipe() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove “\(currentMeal.name)” from your Home Recipes?")
        }
        .alert("Couldn't Remove Recipe", isPresented: .init(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(removalError ?? "") }
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

    private func removeRecipe() async {
        guard canRemove, currentMeal.homeId == home.id, !removing else { return }
        removing = true
        defer { removing = false }
        do {
            try await service.removeHomeRecipe(currentMeal, home: home)
            model.homeRecipes.removeAll { $0.id == currentMeal.id }
            dismiss()
        } catch {
            RecipeSaveDiagnostics.failure(error, stage: "removeHomeRecipe")
            removalError = "Homey couldn't remove this recipe. Please try again."
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
