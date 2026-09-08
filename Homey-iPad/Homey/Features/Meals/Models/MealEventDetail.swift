import Foundation

struct MealEventDetail: Identifiable, Codable, Hashable, Sendable {
    let calendarEventId: UUID
    let mealId: UUID
    let mealType: MealType
    let plannedServings: Decimal?
    let mealNotes: String?
    let shoppingGenerated: Bool
    let createdBy: UUID
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    var id: UUID { calendarEventId }

    enum CodingKeys: String, CodingKey {
        case calendarEventId = "calendar_event_id"
        case mealId = "meal_id"
        case mealType = "meal_type"
        case plannedServings = "planned_servings"
        case mealNotes = "meal_notes"
        case shoppingGenerated = "shopping_generated"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        calendarEventId: UUID,
        mealId: UUID,
        mealType: MealType,
        plannedServings: Decimal? = nil,
        mealNotes: String? = nil,
        shoppingGenerated: Bool = false,
        createdBy: UUID,
        updatedBy: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.calendarEventId = calendarEventId
        self.mealId = mealId
        self.mealType = mealType
        self.plannedServings = plannedServings
        self.mealNotes = mealNotes
        self.shoppingGenerated = shoppingGenerated
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        calendarEventId = try container.decode(UUID.self, forKey: .calendarEventId)
        mealId = try container.decode(UUID.self, forKey: .mealId)
        mealType = try container.decode(MealType.self, forKey: .mealType)
        plannedServings = try MealModelDecoding.decodeDecimalIfPresent(from: container, forKey: .plannedServings)
        mealNotes = try container.decodeIfPresent(String.self, forKey: .mealNotes)
        shoppingGenerated = try container.decodeIfPresent(Bool.self, forKey: .shoppingGenerated) ?? false
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        updatedBy = try container.decodeIfPresent(UUID.self, forKey: .updatedBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct PlannedMeal: Identifiable, Hashable, Sendable {
    let calendarEvent: CalendarEvent
    let mealEventDetail: MealEventDetail
    let meal: Meal
    let signedPhotoURL: URL?

    var id: String { calendarEvent.occurrenceId }
    var calendarEventId: UUID { calendarEvent.eventId }
    var mealType: MealType { mealEventDetail.mealType }
    var startsAt: Date { calendarEvent.occurrenceStartsAt }
    var endsAt: Date { calendarEvent.occurrenceEndsAt }
}

struct CreateMealEventDetailPayload: Encodable, Hashable, Sendable {
    let calendarEventId: UUID
    let mealId: UUID
    let mealType: MealType
    let plannedServings: Decimal?
    let mealNotes: String?
    let shoppingGenerated: Bool
    let createdBy: UUID
    let updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case calendarEventId = "calendar_event_id"
        case mealId = "meal_id"
        case mealType = "meal_type"
        case plannedServings = "planned_servings"
        case mealNotes = "meal_notes"
        case shoppingGenerated = "shopping_generated"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
    }
}

struct UpdateMealEventDetailPayload: Encodable, Hashable, Sendable {
    var mealId: UUID?
    var mealType: MealType?
    var plannedServings: Decimal?
    var mealNotes: String?
    var shoppingGenerated: Bool?
    var updatedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case mealType = "meal_type"
        case plannedServings = "planned_servings"
        case mealNotes = "meal_notes"
        case shoppingGenerated = "shopping_generated"
        case updatedBy = "updated_by"
    }
}
