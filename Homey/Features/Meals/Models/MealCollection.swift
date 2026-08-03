import Foundation

struct MealCollection: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let name: String
    let description: String?
    let iconName: String?
    let sortOrder: Int
    let createdBy: UUID
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case description
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MealCollectionItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let collectionId: UUID
    let mealId: UUID
    let sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case collectionId = "collection_id"
        case mealId = "meal_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}
