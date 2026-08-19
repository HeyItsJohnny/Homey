import Foundation

struct GlobalRecipe: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let description: String?
    let imageURL: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let totalTimeMinutes: Int?
    let servings: String?
    let cuisine: String?
    let mealTypes: [String]
    let keywords: [String]
    let ingredients: [GlobalRecipeIngredient]
    let steps: [GlobalRecipeStep]
    let nutrition: GlobalRecipeNutrition?
    let recipeFingerprint: String?
    let sourceType: String
    let status: String
    let saveCount: Int64
    let createdAt: Date
    let updatedAt: Date
    let lastVerifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case imageURL = "image_url"
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case totalTimeMinutes = "total_time_minutes"
        case servings
        case cuisine
        case mealTypes = "meal_types"
        case keywords
        case ingredients
        case steps
        case nutrition
        case recipeFingerprint = "recipe_fingerprint"
        case sourceType = "source_type"
        case status
        case saveCount = "save_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastVerifiedAt = "last_verified_at"
    }

    var name: String { title }
    var primaryPhotoPath: String? { imageURL }
    var sourceName: String? { sourceType.displaySourceName }
    var sourceURL: String? { nil }
    var notes: String? { nil }
    var tags: [String] { keywords }
    var publishedAt: Date? { createdAt }
    var isRecentlyPublished: Bool {
        createdAt >= Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    }

    var resolvedTotalTimeMinutes: Int? {
        if let totalTimeMinutes, totalTimeMinutes > 0 { return totalTimeMinutes }
        let total = (prepTimeMinutes ?? 0) + (cookTimeMinutes ?? 0)
        return total > 0 ? total : nil
    }

    var mealTypeValues: [MealType] {
        mealTypes.compactMap { MealType(rawValue: $0.lowercased()) }
    }

    func matchesExploreSearch(_ normalizedSearch: String) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }
        return [title, description, cuisine, sourceType]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedSearch) }
            || keywords.contains { $0.lowercased().contains(normalizedSearch) }
            || mealTypes.contains { $0.lowercased().contains(normalizedSearch) }
    }

    func matchesSelectedMealType(_ selectedMealType: MealType?) -> Bool {
        guard let selectedMealType else { return true }
        return mealTypes.contains { mealType in
            mealType.caseInsensitiveCompare(selectedMealType.rawValue) == .orderedSame
                || mealType.caseInsensitiveCompare(selectedMealType.displayName) == .orderedSame
        }
    }

    func matchesExploreFilters(_ filters: GlobalMealsFilters) -> Bool {
        let requestedCuisine = filters.cuisine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !requestedCuisine.isEmpty, cuisine?.lowercased().contains(requestedCuisine) != true {
            return false
        }

        if let maximumTotalTimeMinutes = filters.maximumTotalTimeMinutes,
           let resolvedTotalTimeMinutes,
           resolvedTotalTimeMinutes > maximumTotalTimeMinutes {
            return false
        }

        if let maximumTotalTimeMinutes = filters.maximumTotalTimeMinutes,
           resolvedTotalTimeMinutes == nil,
           maximumTotalTimeMinutes > 0 {
            return false
        }

        return true
    }
}

typealias GlobalMeal = GlobalRecipe

struct GlobalRecipeIngredient: Codable, Hashable, Identifiable, Sendable {
    let quantity: String?
    let sortOrder: Int
    let isOptional: Bool
    let sectionName: String?
    let ingredientName: String

    var id: String {
        "\(sortOrder)-\(sectionName ?? "")-\(ingredientName)"
    }

    enum CodingKeys: String, CodingKey {
        case quantity
        case sortOrder = "sort_order"
        case isOptional = "is_optional"
        case sectionName = "section_name"
        case ingredientName = "ingredient_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quantity = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .quantity)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        sectionName = try container.decodeIfPresent(String.self, forKey: .sectionName)
        ingredientName = try container.decodeIfPresent(String.self, forKey: .ingredientName) ?? ""
    }
}

struct GlobalRecipeStep: Codable, Hashable, Identifiable, Sendable {
    let stepText: String
    let sortOrder: Int
    let sectionName: String?

    var id: String {
        "\(sortOrder)-\(sectionName ?? "")-\(stepText)"
    }

    enum CodingKeys: String, CodingKey {
        case stepText = "step_text"
        case sortOrder = "sort_order"
        case sectionName = "section_name"
    }
}

struct GlobalRecipeNutrition: Codable, Hashable, Sendable {
    let calories: String?
    let protein: String?
    let carbohydrates: String?
    let fat: String?
    let fiber: String?
    let sugar: String?
    let sodium: String?

    enum CodingKeys: String, CodingKey {
        case calories
        case protein
        case carbohydrates
        case carbs
        case fat
        case fiber
        case sugar
        case sodium
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calories = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .calories)
        protein = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .protein)
        carbohydrates = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .carbohydrates)
            ?? GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .carbs)
        fat = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .fat)
        fiber = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .fiber)
        sugar = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .sugar)
        sodium = try GlobalRecipeJSON.decodeFlexibleStringIfPresent(from: container, forKey: .sodium)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(carbohydrates, forKey: .carbohydrates)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encodeIfPresent(fiber, forKey: .fiber)
        try container.encodeIfPresent(sugar, forKey: .sugar)
        try container.encodeIfPresent(sodium, forKey: .sodium)
    }

    var rows: [(String, String)] {
        [
            ("Calories", calories),
            ("Protein", protein),
            ("Carbs", carbohydrates),
            ("Fat", fat),
            ("Fiber", fiber),
            ("Sugar", sugar),
            ("Sodium", sodium)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }
}

struct GlobalMealDetail: Hashable, Sendable {
    let meal: GlobalRecipe
    let recipe: GlobalRecipe?
    let ingredients: [GlobalRecipeIngredient]
    let steps: [GlobalRecipeStep]
}

enum GlobalMealsSort: String, CaseIterable, Identifiable, Sendable {
    case mostSaved
    case newest
    case recentlyUpdated
    case fastest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostSaved:
            return "Most Saved"
        case .newest:
            return "Newest"
        case .recentlyUpdated:
            return "Recently Updated"
        case .fastest:
            return "Fastest"
        }
    }

    var orderColumn: String {
        switch self {
        case .mostSaved:
            return "save_count"
        case .newest:
            return "created_at"
        case .recentlyUpdated:
            return "updated_at"
        case .fastest:
            return "total_time_minutes"
        }
    }

    var isAscending: Bool {
        self == .fastest
    }
}

struct GlobalMealsFilters: Equatable, Sendable {
    var cuisine: String = ""
    var maximumTotalTimeMinutes: Int?
    var sort: GlobalMealsSort = .mostSaved

    var hasActiveFilters: Bool {
        !cuisine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || maximumTotalTimeMinutes != nil
            || sort != .mostSaved
    }
}

enum GlobalMealAddState: Equatable, Sendable {
    case available
    case adding
    case added(homeMealId: UUID)
}

enum GlobalMealAddResult: Equatable, Sendable {
    case added(homeMealId: UUID)
    case alreadyExists(homeMealId: UUID)
    case addedPhotoCopyFailed(homeMealId: UUID)
}

private enum GlobalRecipeJSON {
    static func decodeFlexibleStringIfPresent<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) throws -> String? {
        if let value = try container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }
        return nil
    }
}

private extension String {
    var displaySourceName: String? {
        switch lowercased() {
        case "url":
            return "Recipe URL"
        default:
            return isEmpty ? nil : capitalized
        }
    }
}
