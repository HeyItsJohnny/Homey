import Foundation

struct RecipeStep: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let recipeId: UUID
    let instruction: String
    let stepNumber: Int
    let timerMinutes: Int?
    let photoPath: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recipeId = "recipe_id"
        case instruction
        case stepNumber = "step_number"
        case timerMinutes = "timer_minutes"
        case photoPath = "photo_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var sortOrder: Int {
        stepNumber
    }

    var durationMinutes: Int? {
        timerMinutes
    }
}
