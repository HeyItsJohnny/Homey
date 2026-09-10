import SwiftUI

struct CommunityDetailView: View {
    let recipe: CommunityRecipe
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var confirmsDelete = false
    @State private var adding = false
    @State private var plannedMeal: HomeyMeal?
    private let service = MealsService()

    private var presentation: RecipeDetailPresentation {
        let ingredients = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, ingredient in
            let text = [ingredient.quantity, ingredient.ingredientName]
                .compactMap(nonemptyRecipeDetailText).joined(separator: " ")
            return RecipeDetailIngredientItem(id: "ingredient-\(index)", text: text,
                preparation: nil, notes: nil, isOptional: ingredient.isOptional)
        }
        let directions = recipe.steps.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, step in
            RecipeDetailDirectionItem(id: "step-\(index)", number: index + 1,
                text: step.stepText, timerMinutes: nil)
        }
        let calculatedTotal = (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
        let total = recipe.totalTimeMinutes ?? (calculatedTotal > 0 ? calculatedTotal : nil)
        return RecipeDetailPresentation(title: recipe.title, imageReference: recipe.imageURL,
            description: recipe.description, mealTypes: recipe.mealTypes.compactMap(MealType.init(rawValue:)), totalMinutes: total,
            servings: recipe.servings.flatMap(Double.init), ingredients: ingredients, directions: directions,
            sourceName: nil, sourceURL: nil, notes: nil, cuisine: recipe.cuisine, difficulty: nil,
            prepMinutes: recipe.prepTimeMinutes, cookMinutes: recipe.cookTimeMinutes, tags: recipe.keywords)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Label("Explore", systemImage: "chevron.left").font(.headline).frame(minHeight: 44)
                }
                Spacer()
                if recipe.createdBy == session.currentUser?.id {
                    Menu {
                        Button("Delete Community Recipe", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
                            .background(HomeyColors.recipeCardBackground, in: Circle())
                    }.accessibilityLabel("Community recipe actions")
                }
            }
            .buttonStyle(.plain).foregroundStyle(HomeyColors.recipeGreenAccent)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recipe.title).font(HomeyTypography.hero).accessibilityAddTraits(.isHeader)
                        Text("A recipe shared by the Homey community.").font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    }
                    RecipeDetailHero(imageReference: recipe.imageURL)
                    RecipeDetailSummaryCard(presentation: presentation, favorite: nil,
                        favoritePending: false, favoriteAction: nil, showsTitleAndFavorite: false)
                    RecipeDetailIngredientsCard(ingredients: presentation.ingredients)
                    RecipeDetailDirectionsCard(directions: presentation.directions)
                    actionCard
                    RecipeDetailAdditionalCard(presentation: presentation)
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 28)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
        }
        .background(HomeyColors.recipeBackground.ignoresSafeArea())
        .foregroundStyle(HomeyColors.text).tint(HomeyColors.recipeGreenAccent)
        .navigationTitle("Community Recipe").toolbar(.hidden, for: .navigationBar)
        .disabled(adding)
        .sheet(item: $plannedMeal) { RecipePlanSheet(meal: $0, home: home, model: model) }
        .alert("Community Recipe", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
        .confirmationDialog("Delete Community Recipe?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive) { Task { await deleteRecipe() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to permanently delete “\(recipe.title)” from the Homey community?")
        }
    }

    private var actionCard: some View {
        VStack(spacing: 0) {
            RecipeDetailActionRow(title: "Add to Home Recipes", icon: "books.vertical", color: HomeyColors.recipeGreenAccent) {
                Task { await addToHome(openPlanner: false) }
            }
            Divider().padding(.leading, 66)
            RecipeDetailActionRow(title: "Add to Meal Plan", icon: "calendar", color: HomeyColors.primary) {
                Task { await addToHome(openPlanner: true) }
            }
        }.padding(.horizontal, 16).padding(.vertical, 6).recipeDetailCard()
    }

    private func addToHome(openPlanner: Bool) async {
        guard !adding else { return }
        adding = true; defer { adding = false }
        do {
            let homeMealID = try await service.addToHome(recipe, homeId: home.id)
            await model.load(home: home)
            if openPlanner {
                guard let meal = model.homeRecipes.first(where: { $0.id == homeMealID }) else {
                    throw MealsError.message("The recipe was added, but Homey couldn't open Meal Plan.")
                }
                plannedMeal = meal
            } else { message = "Added to \(home.name)." }
        } catch {
            await model.load(home: home)
            message = error.localizedDescription
        }
    }

    private func deleteRecipe() async {
        guard recipe.createdBy == session.currentUser?.id else { return }
        do {
            try await service.deleteCommunityRecipe(recipe.id)
            await model.load(home: home)
            dismiss()
        } catch { message = error.localizedDescription }
    }
}
