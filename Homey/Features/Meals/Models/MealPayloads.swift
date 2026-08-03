import Foundation

struct CreateMealPayload: Encodable, Hashable, Sendable {
    let homeId: UUID
    let name: String
    let description: String?
    let mealTypes: [MealType]
    let cuisine: String?
    let difficulty: MealDifficulty?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let servings: Decimal?
    let primaryPhotoPath: String?
    let sourceName: String?
    let sourceURL: String?
    let notes: String?
    let tags: [String]
    let isArchived: Bool
    let createdBy: UUID
    let updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case description
        case mealTypes = "meal_types"
        case cuisine
        case difficulty
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case servings
        case primaryPhotoPath = "primary_photo_path"
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case notes
        case tags
        case isArchived = "is_archived"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
    }
}

struct UpdateMealPayload: Encodable, Hashable, Sendable {
    var name: String?
    var description: String?
    var mealTypes: [MealType]?
    var cuisine: String?
    var difficulty: MealDifficulty?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var servings: Decimal?
    var primaryPhotoPath: String?
    var sourceName: String?
    var sourceURL: String?
    var notes: String?
    var tags: [String]?
    var isArchived: Bool?
    var updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case mealTypes = "meal_types"
        case cuisine
        case difficulty
        case prepTimeMinutes = "prep_time_minutes"
        case cookTimeMinutes = "cook_time_minutes"
        case servings
        case primaryPhotoPath = "primary_photo_path"
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case notes
        case tags
        case isArchived = "is_archived"
        case updatedBy = "updated_by"
    }
}

struct CreateMealRecipePayload: Encodable, Hashable, Sendable {
    let mealId: UUID
    let instructionsNotes: String?
    let yieldText: String?

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case instructionsNotes = "instructions_notes"
        case yieldText = "yield_text"
    }
}

struct CreateRecipeIngredientPayload: Encodable, Hashable, Sendable {
    let recipeId: UUID
    let sectionName: String?
    let ingredientName: String
    let quantity: Decimal?
    let unit: String?
    let preparation: String?
    let notes: String?
    let sortOrder: Int
    let isOptional: Bool

    enum CodingKeys: String, CodingKey {
        case recipeId = "recipe_id"
        case sectionName = "section_name"
        case ingredientName = "ingredient_name"
        case quantity
        case unit
        case preparation
        case notes
        case sortOrder = "sort_order"
        case isOptional = "is_optional"
    }
}

struct CreateRecipeStepPayload: Encodable, Hashable, Sendable {
    let recipeId: UUID
    let instruction: String
    let stepNumber: Int
    let timerMinutes: Int?
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case recipeId = "recipe_id"
        case instruction
        case stepNumber = "step_number"
        case timerMinutes = "timer_minutes"
        case photoPath = "photo_path"
    }
}

struct CreateMealCollectionPayload: Encodable, Hashable, Sendable {
    let homeId: UUID
    let name: String
    let description: String?
    let iconName: String?
    let createdBy: UUID
    let updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case description
        case iconName = "icon_name"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
    }
}

struct UpdateMealCollectionPayload: Encodable, Hashable, Sendable {
    let name: String?
    let description: String?
    let iconName: String?
    let updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case iconName = "icon_name"
        case updatedBy = "updated_by"
    }
}

struct CreateMealPhotoPayload: Encodable, Hashable, Sendable {
    let mealId: UUID
    let homeId: UUID
    let path: String
    let fileExtension: String?
    let contentType: String?
    let uploadedBy: UUID

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case homeId = "home_id"
        case path
        case fileExtension = "file_extension"
        case contentType = "content_type"
        case uploadedBy = "uploaded_by"
    }
}

struct CreateMealFavoritePayload: Encodable, Hashable, Sendable {
    let mealId: UUID
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case userId = "user_id"
    }
}

struct CreateMealCollectionItemPayload: Encodable, Hashable, Sendable {
    let collectionId: UUID
    let mealId: UUID

    enum CodingKeys: String, CodingKey {
        case collectionId = "collection_id"
        case mealId = "meal_id"
    }
}

struct MealRecipeDraft: Hashable, Sendable {
    var summary: String?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var servings: Decimal?
    var sourceName: String?
    var sourceURL: String?
    var notes: String?

    init(
        summary: String? = nil,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        servings: Decimal? = nil,
        sourceName: String? = nil,
        sourceURL: String? = nil,
        notes: String? = nil
    ) {
        self.summary = summary
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.servings = servings
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.notes = notes
    }
}

struct RecipeIngredientDraft: Hashable, Sendable {
    var name: String
    var quantity: Decimal?
    var unit: String?
    var notes: String?
    var sortOrder: Int
    var isOptional: Bool

    init(name: String, quantity: Decimal? = nil, unit: String? = nil, notes: String? = nil, sortOrder: Int, isOptional: Bool = false) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
        self.sortOrder = sortOrder
        self.isOptional = isOptional
    }
}

struct RecipeStepDraft: Hashable, Sendable {
    var instruction: String
    var sortOrder: Int
    var durationMinutes: Int?

    init(instruction: String, sortOrder: Int, durationMinutes: Int? = nil) {
        self.instruction = instruction
        self.sortOrder = sortOrder
        self.durationMinutes = durationMinutes
    }
}

struct MealRecipeDetails: Hashable, Sendable {
    let recipe: MealRecipe?
    let ingredients: [RecipeIngredient]
    let steps: [RecipeStep]
}
