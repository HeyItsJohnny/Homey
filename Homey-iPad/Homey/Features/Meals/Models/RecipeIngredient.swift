import Foundation

struct RecipeIngredient: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let recipeId: UUID
    let sectionName: String?
    let ingredientName: String
    let quantity: Decimal?
    let unit: String?
    let preparation: String?
    let notes: String?
    let sortOrder: Int
    let isOptional: Bool
    let pantryItemId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recipeId = "recipe_id"
        case sectionName = "section_name"
        case ingredientName = "ingredient_name"
        case quantity
        case unit
        case preparation
        case notes
        case sortOrder = "sort_order"
        case isOptional = "is_optional"
        case pantryItemId = "pantry_item_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var name: String {
        ingredientName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recipeId = try container.decode(UUID.self, forKey: .recipeId)
        sectionName = try container.decodeIfPresent(String.self, forKey: .sectionName)
        ingredientName = try container.decode(String.self, forKey: .ingredientName)
        quantity = try MealModelDecoding.decodeDecimalIfPresent(from: container, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        preparation = try container.decodeIfPresent(String.self, forKey: .preparation)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        pantryItemId = try container.decodeIfPresent(UUID.self, forKey: .pantryItemId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
