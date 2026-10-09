import Foundation

struct MealPlanEntry: Identifiable, Decodable, Hashable, Sendable {
    let id: UUID
    let homeID: UUID
    let mealID: UUID
    let plannedDate: String
    let mealType: MealType
    let plannedServings: Double?
    let mealNotes: String?
    let sortOrder: Int
    let shoppingGenerated: Bool
    let isLeftover: Bool
    let leftoverFromEntryID: UUID?
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "entry_id"
        case homeID = "home_id"
        case mealID = "meal_id"
        case plannedDate = "planned_date"
        case mealType = "meal_type"
        case plannedServings = "planned_servings"
        case mealNotes = "meal_notes"
        case sortOrder = "sort_order"
        case shoppingGenerated = "shopping_generated"
        case isLeftover = "is_leftover"
        case leftoverFromEntryID = "leftover_from_entry_id"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MealPlanItem: Identifiable, Hashable, Sendable {
    let entry: MealPlanEntry
    let meal: Meal

    var id: UUID { entry.id }
}
