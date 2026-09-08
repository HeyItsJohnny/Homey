import Foundation

struct MealPhoto: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let mealId: UUID
    let homeId: UUID
    let path: String
    let fileExtension: String?
    let contentType: String?
    let caption: String?
    let sortOrder: Int
    let uploadedBy: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case mealId = "meal_id"
        case homeId = "home_id"
        case path
        case fileExtension = "file_extension"
        case contentType = "content_type"
        case caption
        case sortOrder = "sort_order"
        case uploadedBy = "uploaded_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MealFavorite: Codable, Hashable, Sendable {
    let mealId: UUID
    let userId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}
