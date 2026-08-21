import SwiftUI

struct ImportedRecipePreviewView: View {
    let response: RecipeImportResponse
    let saveDestination: RecipeSaveDestination
    var onOpenSavedRecipe: (UUID, Meal?) -> Void

    init(
        response: RecipeImportResponse,
        homeId: UUID? = nil,
        saveDestination: RecipeSaveDestination = .home,
        onOpenSavedRecipe: @escaping (UUID, Meal?) -> Void = { _, _ in }
    ) {
        self.response = response
        self.saveDestination = saveDestination
        self.onOpenSavedRecipe = onOpenSavedRecipe
    }

    var body: some View {
        MealEditorView(mode: .imported(response: response), saveDestination: saveDestination) { mealID, meal in
            onOpenSavedRecipe(mealID, meal)
        }
    }
}

struct ImportedRecipeDraft: Equatable, Hashable, Sendable {
    let importId: UUID
    let globalRecipeId: UUID?
    let imageUrl: String?
    let originalUrl: String
    let normalizedUrl: String
    let sourceDomain: String
    let sourceName: String?
    var title: String
    var description: String
    var prepTimeMinutesText: String
    var cookTimeMinutesText: String
    var totalTimeMinutesText: String
    var servings: String
    var cuisine: String
    var mealTypes: [MealType]
    var ingredients: [ImportedRecipeDraftIngredient]
    var steps: [ImportedRecipeDraftStep]

    init(response: RecipeImportResponse) {
        importId = response.importId
        globalRecipeId = response.globalRecipeId
        imageUrl = response.recipe.imageUrl
        originalUrl = response.recipe.source.originalUrl
        normalizedUrl = response.recipe.source.normalizedUrl
        sourceDomain = response.recipe.source.domain
        sourceName = response.recipe.source.name
        title = response.recipe.title
        description = response.recipe.description ?? ""
        prepTimeMinutesText = response.recipe.prepTimeMinutes.map(String.init) ?? ""
        cookTimeMinutesText = response.recipe.cookTimeMinutes.map(String.init) ?? ""
        totalTimeMinutesText = response.recipe.totalTimeMinutes.map(String.init) ?? ""
        servings = response.recipe.servings ?? ""
        cuisine = response.recipe.cuisine ?? ""
        mealTypes = response.recipe.mealTypes.filter { HomeyImportMealTypes.allCases.contains($0) }
        ingredients = response.recipe.ingredients
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ingredient in
                ImportedRecipeDraftIngredient(
                    sectionName: ingredient.sectionName ?? "Ingredients",
                    ingredientName: ingredient.ingredientName,
                    quantity: ingredient.quantity ?? "",
                    isOptional: ingredient.isOptional,
                    sortOrder: ingredient.sortOrder
                )
            }
        steps = response.recipe.steps
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { step in
                ImportedRecipeDraftStep(
                    sectionName: step.sectionName ?? "",
                    stepText: step.stepText,
                    sortOrder: step.sortOrder
                )
            }
    }

    var sourceDisplayName: String {
        let trimmedName = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? sourceDomain : trimmedName
    }

    var ingredientsWithText: [ImportedRecipeDraftIngredient] {
        ingredients.filter { !$0.ingredientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var stepsWithText: [ImportedRecipeDraftStep] {
        steps.filter { !$0.stepText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var prepTimeMinutes: Int? { Int(prepTimeMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var cookTimeMinutes: Int? { Int(cookTimeMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var totalTimeMinutes: Int? { Int(totalTimeMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) }

    func makeMealEditorDraft() throws -> MealEditorDraft {
        MealEditorDraft(
            name: title,
            description: description,
            mealTypes: mealTypes,
            cuisine: cuisine,
            difficulty: nil,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            servings: Decimal(string: servings.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX")),
            primaryPhotoPath: nil,
            sourceName: sourceDisplayName,
            sourceURL: originalUrl,
            notes: "",
            tags: [],
            ingredients: ingredients.enumerated().map { index, ingredient in
                ingredient.makeMealEditorIngredient(sortOrder: index + 1)
            },
            steps: steps.enumerated().map { index, step in
                step.makeMealEditorStep(stepNumber: index + 1)
            }
        )
    }

    mutating func trimWhitespace() {
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        prepTimeMinutesText = prepTimeMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        cookTimeMinutesText = cookTimeMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        totalTimeMinutesText = totalTimeMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        servings = servings.trimmingCharacters(in: .whitespacesAndNewlines)
        cuisine = cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in ingredients.indices {
            ingredients[index].trimWhitespace()
        }
        for index in steps.indices {
            steps[index].trimWhitespace()
        }
    }
}

struct ImportedRecipeDraftIngredient: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var sectionName: String
    var ingredientName: String
    var quantity: String
    var isOptional: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        sectionName: String,
        ingredientName: String,
        quantity: String,
        isOptional: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.sectionName = sectionName
        self.ingredientName = ingredientName
        self.quantity = quantity
        self.isOptional = isOptional
        self.sortOrder = sortOrder
    }

    func makeMealEditorIngredient(sortOrder: Int) -> MealEditorIngredient {
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = ingredientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantityIsDecimal = trimmedQuantity.isEmpty || (try? MealService.decimalFromQuantityText(trimmedQuantity)) != nil
        let name = quantityIsDecimal || trimmedQuantity.isEmpty ? trimmedName : "\(trimmedQuantity) \(trimmedName)".trimmingCharacters(in: .whitespacesAndNewlines)

        return MealEditorIngredient(
            sectionName: sectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ingredients" : sectionName,
            name: name,
            quantityText: quantityIsDecimal ? trimmedQuantity : "",
            unit: "",
            preparation: "",
            notes: "",
            isOptional: isOptional,
            sortOrder: sortOrder
        )
    }

    mutating func trimWhitespace() {
        sectionName = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        ingredientName = ingredientName.trimmingCharacters(in: .whitespacesAndNewlines)
        quantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ImportedRecipeDraftStep: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var sectionName: String
    var stepText: String
    var sortOrder: Int

    init(id: UUID = UUID(), sectionName: String, stepText: String, sortOrder: Int) {
        self.id = id
        self.sectionName = sectionName
        self.stepText = stepText
        self.sortOrder = sortOrder
    }

    func makeMealEditorStep(stepNumber: Int) -> MealEditorStep {
        let trimmedSection = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = stepText.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = trimmedSection.isEmpty ? trimmedText : "\(trimmedSection): \(trimmedText)"
        return MealEditorStep(instruction: instruction, timerMinutesText: "", stepNumber: stepNumber)
    }

    mutating func trimWhitespace() {
        sectionName = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        stepText = stepText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum HomeyImportMealTypes {
    static let allCases: [MealType] = [.breakfast, .lunch, .dinner, .snack]
}

private struct ImportedRecipeEditorCard<Content: View>: View {
    let title: String
    var spacing: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct ImportedRecipeImageView: View {
    let imageUrl: String?

    var body: some View {
        ZStack {
            if let imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .tint(HomeyDashboardTheme.warmBrown)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityLabel(imageUrl == nil ? "Recipe image placeholder" : "Imported recipe image")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [HomeyDashboardTheme.warmBeige.opacity(0.82), HomeyDashboardTheme.selectedSidebarBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
    }
}

private struct ImportedRecipeIngredientRow: View {
    @Binding var ingredient: ImportedRecipeDraftIngredient
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                TextField("Section", text: $ingredient.sectionName)
                    .textFieldStyle(.roundedBorder)
                Toggle("Optional", isOn: $ingredient.isOptional)
                    .font(.caption.weight(.semibold))
                    .toggleStyle(.switch)
                    .fixedSize()
            }

            HStack(alignment: .top, spacing: 10) {
                TextField("Quantity", text: $ingredient.quantity)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
                    .keyboardType(.decimalPad)
                TextField("Ingredient", text: $ingredient.ingredientName, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
            }

            rowActions(moveUpLabel: "Move ingredient up", moveDownLabel: "Move ingredient down", deleteLabel: "Remove Ingredient")
        }
        .padding(14)
        .background(HomeyDashboardTheme.warmBeige.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private func rowActions(moveUpLabel: String, moveDownLabel: String, deleteLabel: String) -> some View {
        HStack(spacing: 8) {
            Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                .accessibilityLabel(moveUpLabel)
            Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                .accessibilityLabel(moveDownLabel)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Label(deleteLabel, systemImage: "trash")
            }
        }
        .buttonStyle(.bordered)
        .tint(HomeyDashboardTheme.warmBrown)
    }
}

private struct ImportedRecipeStepRow: View {
    @Binding var step: ImportedRecipeDraftStep
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Section", text: $step.sectionName)
                .textFieldStyle(.roundedBorder)

            TextField("Instruction", text: $step.stepText, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Move step up")
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Move step down")
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Remove Step", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
            .tint(HomeyDashboardTheme.warmBrown)
        }
        .padding(14)
        .background(HomeyDashboardTheme.warmBeige.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
}

private struct ImportedRecipeExistingMealCard: View {
    let meal: Meal
    let onViewRecipe: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("This recipe is already in your Home.")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(meal.name)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Button("View Recipe", action: onViewRecipe)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
        }
        .padding(16)
        .dashboardCard(cornerRadius: 20)
    }
}

private struct ImportedRecipeNoticeCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.softRed)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyDashboardTheme.softRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softRed.opacity(0.24), lineWidth: 1) }
    }
}

#Preview("Imported Recipe Preview") {
    NavigationStack {
        ImportedRecipePreviewView(response: RecipeImportResponse.previewSample)
    }
}

private extension RecipeImportResponse {
    static let previewSample = RecipeImportResponse(
        importId: UUID(),
        globalRecipeId: UUID(),
        alreadyExists: false,
        normalizedUrl: "https://example.com/recipe",
        recipe: ImportedRecipePreview(
            title: "Creamy Tuscan Chicken",
            description: "A skillet dinner with garlic, spinach, and a creamy sauce.",
            imageUrl: nil,
            prepTimeMinutes: 10,
            cookTimeMinutes: 25,
            totalTimeMinutes: 35,
            servings: "4 servings",
            cuisine: "Italian",
            mealTypes: [.dinner],
            keywords: ["chicken", "skillet"],
            ingredients: [
                ImportedRecipeIngredient(sectionName: nil, ingredientName: "2 cloves garlic, minced", quantity: nil, isOptional: false, sortOrder: 0),
                ImportedRecipeIngredient(sectionName: nil, ingredientName: "1 cup heavy cream", quantity: nil, isOptional: false, sortOrder: 1)
            ],
            steps: [
                ImportedRecipeStep(sectionName: nil, stepText: "Heat the skillet over medium heat.", sortOrder: 0),
                ImportedRecipeStep(sectionName: nil, stepText: "Simmer until the sauce thickens.", sortOrder: 1)
            ],
            nutrition: nil,
            source: ImportedRecipeSource(
                originalUrl: "https://example.com/recipe",
                normalizedUrl: "https://example.com/recipe",
                domain: "example.com",
                name: "Example"
            )
        )
    )
}
