import Foundation

enum MealType: String, Codable, CaseIterable, Identifiable, Hashable {
    case breakfast, lunch, dinner, snack, dessert, drink
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { switch self { case .breakfast: "sunrise.fill"; case .lunch: "sun.max.fill"; case .dinner: "moon.stars.fill"; case .snack: "takeoutbag.and.cup.and.straw.fill"; case .dessert: "birthday.cake.fill"; case .drink: "cup.and.saucer.fill" } }
    var hour: Int { switch self { case .breakfast: 8; case .lunch: 12; case .dinner: 18; case .snack: 15; case .dessert: 19; case .drink: 10 } }
}

enum MealDifficulty: String, Codable, CaseIterable { case easy, medium, hard }

struct HomeyMeal: Identifiable, Codable, Hashable {
    let id, homeId: UUID
    let name: String
    let description: String?
    let mealTypes: [MealType]
    let cuisine: String?
    let difficulty: MealDifficulty?
    let prepTimeMinutes, cookTimeMinutes: Int?
    let servings: Double?
    let primaryPhotoPath, sourceName, sourceURL, sourceType: String?
    let originGlobalRecipeId, globalRecipeId: UUID?
    let notes: String?
    let tags: [String]
    let isArchived: Bool
    let createdBy: UUID
    let createdAt, updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, name, description, cuisine, difficulty, servings, notes, tags; case homeId = "home_id", mealTypes = "meal_types", prepTimeMinutes = "prep_time_minutes", cookTimeMinutes = "cook_time_minutes", primaryPhotoPath = "primary_photo_path", sourceName = "source_name", sourceURL = "source_url", sourceType = "source_type", originGlobalRecipeId = "origin_global_recipe_id", globalRecipeId = "global_recipe_id", isArchived = "is_archived", createdBy = "created_by", createdAt = "created_at", updatedAt = "updated_at" }
}

struct HomeyRecipeDetail: Hashable { let meal: HomeyMeal; let ingredients: [RecipeIngredient]; let steps: [RecipeStep] }
struct RecipeIngredient: Identifiable, Codable, Hashable { let id, recipeId: UUID; let sectionName, ingredientName, unit, preparation, notes: String?; let quantity: Double?; let sortOrder: Int; let isOptional: Bool; enum CodingKeys: String, CodingKey { case id, quantity, unit, preparation, notes; case recipeId = "recipe_id", sectionName = "section_name", ingredientName = "ingredient_name", sortOrder = "sort_order", isOptional = "is_optional" } }
struct RecipeStep: Identifiable, Codable, Hashable { let id, recipeId: UUID; let instruction: String; let stepNumber: Int; let timerMinutes: Int?; enum CodingKeys: String, CodingKey { case id, instruction; case recipeId = "recipe_id", stepNumber = "step_number", timerMinutes = "timer_minutes" } }

struct CommunityRecipe: Identifiable, Codable, Hashable {
    let id: UUID; let title: String; let description, imageURL: String?; let prepTimeMinutes, cookTimeMinutes, totalTimeMinutes: Int?; let servings, cuisine: String?; let mealTypes, keywords: [String]; let ingredients: [CommunityIngredient]; let steps: [CommunityStep]; let sourceType, status: String; let saveCount: Int64; let createdBy: UUID?; let createdAt, updatedAt: Date
    enum CodingKeys: String, CodingKey { case id, title, description, servings, cuisine, ingredients, steps, status; case imageURL = "image_url", prepTimeMinutes = "prep_time_minutes", cookTimeMinutes = "cook_time_minutes", totalTimeMinutes = "total_time_minutes", mealTypes = "meal_types", keywords, sourceType = "source_type", saveCount = "save_count", createdBy = "created_by", createdAt = "created_at", updatedAt = "updated_at" }
}
struct CommunityIngredient: Codable, Hashable { let quantity: String?; let sortOrder: Int; let isOptional: Bool; let sectionName: String?; let ingredientName: String; enum CodingKeys: String, CodingKey { case quantity; case sortOrder = "sort_order", isOptional = "is_optional", sectionName = "section_name", ingredientName = "ingredient_name" } }
struct CommunityStep: Codable, Hashable { let stepText: String; let sortOrder: Int; let sectionName: String?; enum CodingKeys: String, CodingKey { case stepText = "step_text", sortOrder = "sort_order", sectionName = "section_name" } }

struct RecipeDraft: Equatable {
    var name = "", description = "", cuisine = "", sourceName = "", sourceURL = "", notes = "", tagsText = ""
    var mealTypes: Set<MealType> = []
    var difficulty: MealDifficulty? = .easy
    var prepMinutes: Int?, cookMinutes: Int?, servings: Double?
    var ingredients: [IngredientDraft] = [.init()]
    var steps: [StepDraft] = [.init()]
    var shareWithCommunity = true
    var imported: RecipeImportResponse?
}
struct IngredientDraft: Identifiable, Equatable { let id = UUID(); var name = "", quantity = "", unit = "", section = "Ingredients"; var optional = false; var preparation: String?; var notes: String? }
struct StepDraft: Identifiable, Equatable { let id = UUID(); var text = ""; var timerMinutes: Int? }

struct RecipeImportRequest: Encodable { let homeId: UUID; let url: String; enum CodingKeys: String, CodingKey { case homeId = "home_id", url } }
struct RecipeImportResponse: Decodable, Hashable { let importId: UUID; let globalRecipeId: UUID?; let alreadyExists: Bool; let normalizedUrl: String; let recipe: ImportedRecipePreview }
struct ImportedRecipePreview: Decodable, Hashable { let title: String; let description, imageUrl: String?; let prepTimeMinutes, cookTimeMinutes, totalTimeMinutes: Int?; let servings, cuisine: String?; let mealTypes, keywords: [String]; let ingredients: [CommunityIngredient]; let steps: [CommunityStep]; let source: ImportedRecipeSource }
struct ImportedRecipeSource: Decodable, Hashable { let originalUrl, normalizedUrl, domain: String; let name: String? }

struct PlannedMeal: Identifiable, Hashable { let eventId: UUID; let occurrenceId: String; let startsAt: Date; let mealType: MealType; let meal: HomeyMeal; var id: String { occurrenceId } }
struct CalendarMealEvent: Decodable { let eventId: UUID; let occurrenceId: String; let occurrenceStartsAt: Date; enum CodingKeys: String, CodingKey { case eventId = "event_id", occurrenceId = "occurrence_id", occurrenceStartsAt = "occurrence_starts_at" } }
struct MealEventDetailRow: Decodable { let calendarEventId, mealId: UUID; let mealType: MealType; enum CodingKeys: String, CodingKey { case calendarEventId = "calendar_event_id", mealId = "meal_id", mealType = "meal_type" } }

enum RecipeScope: String, CaseIterable, Identifiable { case home = "Home", community = "Community"; var id: String { rawValue } }
enum RecipeFilter: String, CaseIterable, Identifiable { case all = "All", favorites = "Favorites", breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snack = "Snack"; var id: String { rawValue } }

// Build edits from the complete stored recipe so untouched metadata survives saving.
extension RecipeDraft {
    init(detail: HomeyRecipeDetail) {
        self.init()
        let meal = detail.meal
        name = meal.name
        description = meal.description ?? ""
        cuisine = meal.cuisine ?? ""
        sourceName = meal.sourceName ?? ""
        sourceURL = meal.sourceURL ?? ""
        notes = meal.notes ?? ""
        tagsText = meal.tags.joined(separator: ", ")
        mealTypes = Set(meal.mealTypes)
        difficulty = meal.difficulty
        prepMinutes = meal.prepTimeMinutes
        cookMinutes = meal.cookTimeMinutes
        servings = meal.servings
        shareWithCommunity = false
        ingredients = detail.ingredients.map { item in
            var draft = IngredientDraft()
            draft.name = item.ingredientName ?? ""
            draft.quantity = item.quantity.map { String($0) } ?? ""
            draft.unit = item.unit ?? ""
            draft.section = item.sectionName ?? ""
            draft.optional = item.isOptional
            draft.preparation = item.preparation
            draft.notes = item.notes
            return draft
        }
        steps = detail.steps.map { item in
            var draft = StepDraft()
            draft.text = item.instruction
            draft.timerMinutes = item.timerMinutes
            return draft
        }
    }
}
