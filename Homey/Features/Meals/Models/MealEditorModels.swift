import Foundation

enum RecipeSaveDestination: Hashable, Sendable {
    case home
    case community
}

enum MealEditorMode: Hashable, Sendable {
    case create
    case imported(response: RecipeImportResponse)
    case edit(mealID: UUID)

    var mealID: UUID? {
        switch self {
        case .create, .imported:
            return nil
        case .edit(let mealID):
            return mealID
        }
    }

    var importedResponse: RecipeImportResponse? {
        switch self {
        case .imported(let response):
            return response
        case .create, .edit:
            return nil
        }
    }
}

struct MealEditorDraft: Equatable, Sendable {
    var name = ""
    var description = ""
    var mealTypes: [MealType] = []
    var cuisine = ""
    var difficulty: MealDifficulty?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var servings: Decimal?
    var primaryPhotoPath: String?
    var sourceName = ""
    var sourceURL = ""
    var notes = ""
    var tags: [String] = []
    var ingredients: [MealEditorIngredient] = []
    var steps: [MealEditorStep] = []
    var importedMetadata: ImportedMealMetadata?
    var importedImageURL: URL?
}

struct ImportedMealMetadata: Equatable, Hashable, Sendable {
    let importId: UUID
    let globalRecipeId: UUID
    let originalURL: String
    let normalizedURL: String
    let sourceDomain: String
    let sourceName: String?

    var sourceDisplayName: String {
        let trimmedName = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? sourceDomain : trimmedName
    }
}

struct MealEditorIngredient: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var sectionName: String
    var name: String
    var quantityText: String
    var unit: String
    var preparation: String
    var notes: String
    var isOptional: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        sectionName: String = "Ingredients",
        name: String = "",
        quantityText: String = "",
        unit: String = "",
        preparation: String = "",
        notes: String = "",
        isOptional: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.sectionName = sectionName
        self.name = name
        self.quantityText = quantityText
        self.unit = unit
        self.preparation = preparation
        self.notes = notes
        self.isOptional = isOptional
        self.sortOrder = sortOrder
    }
}

struct MealEditorStep: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var instruction: String
    var timerMinutesText: String
    var photoPath: String?
    var stepNumber: Int

    init(
        id: UUID = UUID(),
        instruction: String = "",
        timerMinutesText: String = "",
        photoPath: String? = nil,
        stepNumber: Int = 1
    ) {
        self.id = id
        self.instruction = instruction
        self.timerMinutesText = timerMinutesText
        self.photoPath = photoPath
        self.stepNumber = stepNumber
    }
}

struct SaveMealRecipeParameters: Encodable, Sendable {
    let requestedHomeId: UUID
    let requestedMealId: UUID?
    let requestedName: String
    let requestedDescription: String?
    let requestedMealTypes: [String]
    let requestedCuisine: String?
    let requestedDifficulty: String?
    let requestedPrepTimeMinutes: Int?
    let requestedCookTimeMinutes: Int?
    let requestedServings: Decimal?
    let requestedPrimaryPhotoPath: String?
    let requestedSourceName: String?
    let requestedSourceURL: String?
    let requestedNotes: String?
    let requestedTags: [String]
    let requestedIsDraft: Bool
    let requestedIngredients: [SaveMealRecipeIngredient]
    let requestedSteps: [SaveMealRecipeStep]

    enum CodingKeys: String, CodingKey {
        case requestedHomeId = "requested_home_id"
        case requestedMealId = "requested_meal_id"
        case requestedName = "requested_name"
        case requestedDescription = "requested_description"
        case requestedMealTypes = "requested_meal_types"
        case requestedCuisine = "requested_cuisine"
        case requestedDifficulty = "requested_difficulty"
        case requestedPrepTimeMinutes = "requested_prep_time_minutes"
        case requestedCookTimeMinutes = "requested_cook_time_minutes"
        case requestedServings = "requested_servings"
        case requestedPrimaryPhotoPath = "requested_primary_photo_path"
        case requestedSourceName = "requested_source_name"
        case requestedSourceURL = "requested_source_url"
        case requestedNotes = "requested_notes"
        case requestedTags = "requested_tags"
        case requestedIsDraft = "requested_is_draft"
        case requestedIngredients = "requested_ingredients"
        case requestedSteps = "requested_steps"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestedHomeId, forKey: .requestedHomeId)
        try encodeNullable(requestedMealId, into: &container, forKey: .requestedMealId)
        try container.encode(requestedName, forKey: .requestedName)
        try encodeNullable(requestedDescription, into: &container, forKey: .requestedDescription)
        try container.encode(requestedMealTypes, forKey: .requestedMealTypes)
        try encodeNullable(requestedCuisine, into: &container, forKey: .requestedCuisine)
        try encodeNullable(requestedDifficulty, into: &container, forKey: .requestedDifficulty)
        try encodeNullable(requestedPrepTimeMinutes, into: &container, forKey: .requestedPrepTimeMinutes)
        try encodeNullable(requestedCookTimeMinutes, into: &container, forKey: .requestedCookTimeMinutes)
        try encodeNullable(requestedServings, into: &container, forKey: .requestedServings)
        try encodeNullable(requestedPrimaryPhotoPath, into: &container, forKey: .requestedPrimaryPhotoPath)
        try encodeNullable(requestedSourceName, into: &container, forKey: .requestedSourceName)
        try encodeNullable(requestedSourceURL, into: &container, forKey: .requestedSourceURL)
        try encodeNullable(requestedNotes, into: &container, forKey: .requestedNotes)
        try container.encode(requestedTags, forKey: .requestedTags)
        try container.encode(requestedIsDraft, forKey: .requestedIsDraft)
        try container.encode(requestedIngredients, forKey: .requestedIngredients)
        try container.encode(requestedSteps, forKey: .requestedSteps)
    }

    private func encodeNullable<T: Encodable>(
        _ value: T?,
        into container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

struct SaveMealRecipeIngredient: Encodable, Equatable, Hashable, Sendable {
    let sectionName: String?
    let ingredientName: String
    let quantity: Decimal?
    let unit: String?
    let preparation: String?
    let notes: String?
    let sortOrder: Int
    let isOptional: Bool

    enum CodingKeys: String, CodingKey {
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

struct SaveMealRecipeStep: Encodable, Equatable, Hashable, Sendable {
    let stepNumber: Int
    let instruction: String
    let timerMinutes: Int?
    let photoPath: String?

    enum CodingKeys: String, CodingKey {
        case stepNumber = "step_number"
        case instruction
        case timerMinutes = "timer_minutes"
        case photoPath = "photo_path"
    }
}

struct SaveGlobalRecipeParameters: Encodable, Sendable {
    let requestedTitle: String
    let requestedDescription: String?
    let requestedImageURL: String?
    let requestedPrepTimeMinutes: Int?
    let requestedCookTimeMinutes: Int?
    let requestedTotalTimeMinutes: Int?
    let requestedServings: String?
    let requestedCuisine: String?
    let requestedMealTypes: [String]
    let requestedKeywords: [String]
    let requestedIngredients: [SaveGlobalRecipeIngredient]
    let requestedSteps: [SaveGlobalRecipeStep]
    let requestedSourceType: String
    let requestedSourceName: String?
    let requestedSourceURL: String?

    enum CodingKeys: String, CodingKey {
        case requestedTitle = "requested_title"
        case requestedDescription = "requested_description"
        case requestedImageURL = "requested_image_url"
        case requestedPrepTimeMinutes = "requested_prep_time_minutes"
        case requestedCookTimeMinutes = "requested_cook_time_minutes"
        case requestedTotalTimeMinutes = "requested_total_time_minutes"
        case requestedServings = "requested_servings"
        case requestedCuisine = "requested_cuisine"
        case requestedMealTypes = "requested_meal_types"
        case requestedKeywords = "requested_keywords"
        case requestedIngredients = "requested_ingredients"
        case requestedSteps = "requested_steps"
        case requestedSourceType = "requested_source_type"
        case requestedSourceName = "requested_source_name"
        case requestedSourceURL = "requested_source_url"
    }
}

struct SaveGlobalRecipeIngredient: Encodable, Equatable, Hashable, Sendable {
    let quantity: String?
    let sortOrder: Int
    let isOptional: Bool
    let sectionName: String?
    let ingredientName: String

    enum CodingKeys: String, CodingKey {
        case quantity
        case sortOrder = "sort_order"
        case isOptional = "is_optional"
        case sectionName = "section_name"
        case ingredientName = "ingredient_name"
    }
}

struct SaveGlobalRecipeStep: Encodable, Equatable, Hashable, Sendable {
    let stepText: String
    let sortOrder: Int
    let sectionName: String?

    enum CodingKeys: String, CodingKey {
        case stepText = "step_text"
        case sortOrder = "sort_order"
        case sectionName = "section_name"
    }
}

enum MealEditorValidationField: Hashable, Sendable {
    case name
    case mealTypes
    case prepTime
    case cookTime
    case servings
    case sourceURL
    case ingredients
    case steps
    case permission
    case photo
}

struct MealEditorValidationError: Identifiable, Equatable, Sendable {
    let field: MealEditorValidationField
    let message: String

    var id: MealEditorValidationField { field }
}

enum MealEditorSaveResult: Equatable, Sendable {
    case saved(mealID: UUID, meal: Meal?)
    case failed
}
