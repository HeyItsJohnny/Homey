import Foundation

extension RecipeDraft {
    mutating func apply(_ response: RecipeImportResponse) {
        imported = response
        importedImageRemoved = false
        difficulty = nil
        let recipe = response.recipe
        name = recipe.title
        description = recipe.description ?? ""
        cuisine = recipe.cuisine ?? ""
        let importedSourceName = recipe.source.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sourceName = importedSourceName.isEmpty ? recipe.source.domain : importedSourceName
        sourceURL = recipe.source.originalUrl
        prepMinutes = recipe.prepTimeMinutes
        cookMinutes = recipe.cookTimeMinutes
        servings = recipe.servings.flatMap(Double.init)
        mealTypes = Set(recipe.mealTypes.compactMap(MealType.init(rawValue:)))
        tagsText = recipe.keywords.joined(separator: ", ")
        ingredients = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }.map { ingredient in
            let quantity = ingredient.quantity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Match iPad import normalization: preserve descriptive amounts without sending text as numeric JSON.
            let numeric = quantity.isEmpty || (try? RecipeQuantity.decimal(quantity)) != nil
            return IngredientDraft(name: numeric ? ingredient.ingredientName : "\(quantity) \(ingredient.ingredientName)", quantity: numeric ? quantity : "", unit: "", section: ingredient.sectionName ?? "Ingredients", optional: ingredient.isOptional)
        }
        steps = recipe.steps.sorted { $0.sortOrder < $1.sortOrder }.map { item in
            var step = StepDraft()
            let section = item.sectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = item.stepText.trimmingCharacters(in: .whitespacesAndNewlines)
            step.text = section.isEmpty ? text : "\(section): \(text)"
            return step
        }
    }
}

enum RecipeImportInput {
    static func validURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }), components.url != nil else { return nil }
        return trimmed
    }
    static func safeLogURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return "<invalid>" }
        components.user = nil; components.password = nil
        components.query = nil; components.fragment = nil
        return components.string ?? "<invalid>"
    }
    static func errorCode(data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (body["error"] as? [String: Any])?["code"] as? String ?? body["code"] as? String
    }
    static func message(for code: String) -> String {
        switch code {
        case "SOURCE_BLOCKED": "This website doesn't currently allow Homey to import this recipe."
        case "INVALID_URL": "Enter a valid recipe URL."
        case "AUTH_REQUIRED", "HTTP_401": "Please sign in again before importing a recipe."
        case "HOME_ACCESS_DENIED", "HTTP_403": "You don't have access to import recipes for this Home."
        case "RECIPE_NOT_FOUND", "NO_RECIPE_FOUND", "UNSUPPORTED_PAGE": "We couldn't find a recipe on that page. Try a direct recipe link."
        case "INVALID_RECIPE_DATA", "PARSE_FAILED", "SOURCE_PARSE_FAILED": "We couldn't read this recipe. Try another link or add it manually."
        case "RESPONSE_DECODING_ERROR": "Homey couldn't read the recipe returned by this website. Please try another recipe or try again later."
        case "NETWORK_ERROR", "TIMEOUT": "Homey couldn't reach the importer. Check your connection and try again."
        case "SOURCE_UNSUPPORTED", "NOT_HTML": "This page isn't supported. Try a direct recipe link."
        default: "Homey couldn't import this recipe. Please try another link or try again later."
        }
    }
}

/// The sheet payload and its editor identity are created together. Imported
/// content never travels through an independently changing optional State value.
struct RecipeCreationPresentation: Identifiable {
    enum Content {
        case website
        case scan
        case editor(RecipeDraft)
    }
    let id = UUID()
    let content: Content

    static func manual() -> Self { .init(content: .editor(RecipeDraft())) }
    static func website() -> Self { .init(content: .website) }
    static func scan() -> Self { .init(content: .scan) }
    static func imported(_ draft: RecipeDraft) -> Self { .init(content: .editor(draft)) }
}
