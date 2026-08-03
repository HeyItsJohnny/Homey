import Foundation

struct Meal: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
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
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeId = try container.decode(UUID.self, forKey: .homeId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        mealTypes = try container.decodeIfPresent([MealType].self, forKey: .mealTypes) ?? []
        cuisine = try container.decodeIfPresent(String.self, forKey: .cuisine)
        difficulty = try container.decodeIfPresent(MealDifficulty.self, forKey: .difficulty)
        prepTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .prepTimeMinutes)
        cookTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .cookTimeMinutes)
        servings = try MealModelDecoding.decodeDecimalIfPresent(from: container, forKey: .servings)
        primaryPhotoPath = try container.decodeIfPresent(String.self, forKey: .primaryPhotoPath)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        updatedBy = try container.decodeIfPresent(UUID.self, forKey: .updatedBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
