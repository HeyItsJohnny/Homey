import Foundation

struct MealRecipe: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let mealId: UUID
    let instructionsNotes: String?
    let yieldText: String?
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case mealId = "meal_id"
        case instructionsNotes = "instructions_notes"
        case yieldText = "yield_text"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var notes: String? {
        instructionsNotes
    }
}
