import Foundation

struct CalendarEvent: Codable, Identifiable, Hashable {
    let eventId: UUID
    let homeId: UUID
    let categoryId: UUID?
    let categoryName: String?
    let categoryColorHex: String?
    let categoryIconName: String?
    let title: String
    let notes: String?
    let location: String?
    let startsAt: Date
    let endsAt: Date
    let isAllDay: Bool
    let timezone: String
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date
    let assignedUserIds: [UUID]

    var id: UUID { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case homeId = "home_id"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case categoryColorHex = "category_color_hex"
        case categoryIconName = "category_icon_name"
        case title
        case notes
        case location
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case isAllDay = "is_all_day"
        case timezone
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case assignedUserIds = "assigned_user_ids"
    }
}

struct CalendarCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let homeId: UUID
    let name: String
    let colorHex: String
    let iconName: String?
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
