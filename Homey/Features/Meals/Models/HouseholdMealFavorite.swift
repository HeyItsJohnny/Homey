import Foundation

struct HouseholdMealFavorite: Codable, Hashable, Sendable {
    let mealId: UUID
    let userId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

