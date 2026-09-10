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
                        Text("Recipe").font(HomeyTypography.hero).accessibilityAddTraits(.isHeader)
                        Text("View and manage your recipe details.").font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    }
                    HomeRecipeThumbnail(path: currentMeal.primaryPhotoPath)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    summaryCard
                    if loading {
                        HStack(spacing: 12) { ProgressView(); Text("Loading your recipe…").font(.subheadline) }
                            .frame(maxWidth: .infinity).padding(24).detailCard()
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 12) {
                            HomeyErrorView(message: loadError)
                            Button("Try Again") { Task { await loadDetail() } }.buttonStyle(.bordered)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).detailCard()
                    } else {
                        ingredientsCard
                        directionsCard
                    }
                    quickActions
                    if hasAdditionalDetails { additionalDetails }
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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(currentMeal.name).font(HomeyTypography.title).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button { toggleFavorite() } label: {
                    Image(systemName: favorite ? "heart.fill" : "heart").font(.title2)
                        .foregroundStyle(favorite ? HomeyColors.danger : HomeyColors.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(HomeyColors.danger.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).disabled(pendingFavorite != nil)
                    .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
            }
            RecipeBadgeFlow(spacing: 8) {
                ForEach(currentMeal.mealTypes) { type in
                    metadataBadge(type.title, icon: "fork.knife", color: HomeyColors.recipeOrangeAccent)
                }
                let total = (currentMeal.prepTimeMinutes ?? 0) + (currentMeal.cookTimeMinutes ?? 0)
                if total > 0 { metadataBadge("\(total) min", icon: "clock", color: HomeyColors.secondaryText) }
                if let servings = currentMeal.servings, servings > 0 {
                    metadataBadge("\(servings.formatted()) servings", icon: "person.2", color: HomeyColors.secondaryText)
                }
            }
        }.padding(20).detailCard()
    }

    private var ingredientsCard: some View {
        RecipeDetailSection(title: "Ingredients", icon: "cart", color: HomeyColors.recipeGreenAccent) {
            if let ingredients = detail?.ingredients, !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ingredientText(ingredient)).frame(maxWidth: .infinity, alignment: .leading)
                            if let preparation = nonempty(ingredient.preparation) { Text(preparation).font(.caption).foregroundStyle(HomeyColors.secondaryText) }
                            if let notes = nonempty(ingredient.notes) { Text(notes).font(.caption).foregroundStyle(HomeyColors.secondaryText) }
                            if ingredient.isOptional { Text("Optional").font(.caption).foregroundStyle(HomeyColors.secondaryText) }
                        }.padding(.vertical, 13)
                        if index < ingredients.count - 1 { Divider().overlay(HomeyColors.border.opacity(0.2)) }
                    }
                }.padding(.horizontal, 14).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("No ingredients added yet.").foregroundStyle(HomeyColors.secondaryText)
            }
        }
    }

    private var directionsCard: some View {
        RecipeDetailSection(title: "Directions", icon: "list.bullet", color: HomeyColors.recipeOrangeAccent) {
            if let steps = detail?.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(step.stepNumber)").font(.headline)
                                .frame(minWidth: 36, minHeight: 36)
                                .background(HomeyColors.field, in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.instruction).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let timer = step.timerMinutes, timer > 0 {
                                    Label("\(timer) min", systemImage: "timer").font(.caption).foregroundStyle(HomeyColors.secondaryText)
                                }
                            }
                        }
                    }
                }
            } else { Text("No directions added yet.").foregroundStyle(HomeyColors.secondaryText) }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            actionRow("Add to Meal Plan", icon: "calendar", color: HomeyColors.recipeGreenAccent) { showPlan = true }
            Divider().padding(.leading, 66)
            actionRow("Add ingredients to Groceries", icon: "cart", color: HomeyColors.primary) { showGrocery = true }
        }.padding(.horizontal, 16).padding(.vertical, 6).detailCard()
    }

    private var hasAdditionalDetails: Bool {
        [currentMeal.description, currentMeal.sourceName, currentMeal.sourceURL, currentMeal.notes, currentMeal.cuisine].contains { nonempty($0) != nil }
            || !currentMeal.tags.isEmpty || currentMeal.difficulty != nil || currentMeal.prepTimeMinutes != nil || currentMeal.cookTimeMinutes != nil
    }

    private var additionalDetails: some View {
        RecipeDetailSection(title: "About this recipe", icon: "book.closed", color: HomeyColors.recipeGreenAccent) {
            if let description = nonempty(currentMeal.description) { Text(description) }
            if let source = nonempty(currentMeal.sourceName) { detailField("Source", text: source) }
            if let sourceURL = nonempty(currentMeal.sourceURL) {
                if let url = URL(string: sourceURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) { Label("View original recipe", systemImage: "arrow.up.right.square") }
                } else { detailField("Source URL", text: sourceURL) }
            }
            if let notes = nonempty(currentMeal.notes) { detailField("Notes", text: notes) }
            if let cuisine = nonempty(currentMeal.cuisine) { detailField("Cuisine", text: cuisine) }
            if let difficulty = currentMeal.difficulty { detailField("Difficulty", text: difficulty.rawValue.capitalized) }
            if let prep = currentMeal.prepTimeMinutes { detailField("Prep time", text: "\(prep) min") }
            if let cook = currentMeal.cookTimeMinutes { detailField("Cook time", text: "\(cook) min") }
            if !currentMeal.tags.isEmpty {
                RecipeBadgeFlow(spacing: 8) {
                    ForEach(Array(currentMeal.tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag).font(.caption).padding(.horizontal, 12).padding(.vertical, 7)
                            .background(HomeyColors.recipeGreenAccent.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    private func metadataBadge(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon).font(.subheadline)
            .foregroundStyle(color).padding(.horizontal, 12).padding(.vertical, 9)
            .background(color.opacity(0.08), in: Capsule())
    }

    private func detailField(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionRow(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RecipeDetailIcon(symbol: icon, color: color)
                Text(title).foregroundStyle(HomeyColors.primary).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            }.padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
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

private struct RecipeDetailIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(color)
            .frame(width: 44, height: 44).background(color.opacity(0.1), in: Circle()).accessibilityHidden(true)
    }
}

private struct RecipeDetailSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RecipeDetailIcon(symbol: icon, color: color)
                Text(title).font(HomeyTypography.headline).accessibilityAddTraits(.isHeader)
            }
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).detailCard()
    }
}

private extension View {
    func detailCard() -> some View {
        background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: HomeyColors.text.opacity(0.035), radius: 12, y: 4)
    }
}
