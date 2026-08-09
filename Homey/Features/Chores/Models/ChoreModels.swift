import Foundation

protocol ChoreDateOnlyDecoding {}

struct ClearHomeChoresResult: Codable, Hashable, Sendable {
    let choreDefinitionsDeleted: Int
    let recurrenceRulesDeleted: Int
    let occurrencesDeleted: Int
    let calendarEventsDeleted: Int
    let submissionsDeleted: Int
    let approvalsDeleted: Int
    let pointTransactionsDeleted: Int
    let categoriesDeleted: Int
    let roomsDeleted: Int

    enum CodingKeys: String, CodingKey {
        case choreDefinitionsDeleted = "chore_definitions_deleted"
        case recurrenceRulesDeleted = "recurrence_rules_deleted"
        case occurrencesDeleted = "occurrences_deleted"
        case calendarEventsDeleted = "calendar_events_deleted"
        case submissionsDeleted = "submissions_deleted"
        case approvalsDeleted = "approvals_deleted"
        case pointTransactionsDeleted = "point_transactions_deleted"
        case categoriesDeleted = "categories_deleted"
        case roomsDeleted = "rooms_deleted"
    }

}

struct ChoreHistoryActivity: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let activityType: ChoreHistoryActivityType
    let title: String
    let subtitle: String?
    let occurredAt: Date
    let pointsDelta: Int?
    let occurrenceId: UUID?
    let relatedId: UUID?

    enum CodingKeys: String, CodingKey {
        case id = "activity_id"
        case activityType = "activity_type"
        case title
        case subtitle
        case occurredAt = "occurred_at"
        case pointsDelta = "points_delta"
        case occurrenceId = "occurrence_id"
        case relatedId = "related_id"
    }
}

extension KeyedDecodingContainer {
    func decodeDateOnlyIfPresent(forKey key: Key) throws -> Date? {
        if let date = try? decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        guard let value = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        guard let date = ChoreDateOnlyFormatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid Postgres date value: \(value)"
            )
        }

        return date
    }

    func decodeDateOnly(forKey key: Key) throws -> Date {
        if let date = try decodeDateOnlyIfPresent(forKey: key) {
            return date
        }

        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing required date value for \(key.stringValue)")
        )
    }
}

struct ChoreCategory: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let name: String
    let colorHex: String?
    let iconName: String?
    let sortOrder: Int
    let archivedAt: Date?
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case archivedAt = "archived_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreRoom: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let name: String
    let sortOrder: Int
    let archivedAt: Date?
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case sortOrder = "sort_order"
        case archivedAt = "archived_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreReward: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let name: String
    let description: String?
    let pointCost: Int
    let isActive: Bool
    let isArchived: Bool
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case description
        case pointCost = "point_cost"
        case isActive = "is_active"
        case isArchived = "is_archived"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreRewardRedemption: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let rewardId: UUID
    let userId: UUID
    let rewardNameSnapshot: String
    let pointCostSnapshot: Int
    let status: ChoreRewardRedemptionStatus
    let pointTransactionId: UUID?
    let refundTransactionId: UUID?
    let requestedAt: Date
    let redeemedAt: Date?
    let redeemedBy: UUID?
    let cancelledAt: Date?
    let cancelledBy: UUID?
    let cancellationReason: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case rewardId = "reward_id"
        case userId = "user_id"
        case rewardNameSnapshot = "reward_name_snapshot"
        case pointCostSnapshot = "point_cost_snapshot"
        case status
        case pointTransactionId = "point_transaction_id"
        case refundTransactionId = "refund_transaction_id"
        case requestedAt = "requested_at"
        case redeemedAt = "redeemed_at"
        case redeemedBy = "redeemed_by"
        case cancelledAt = "cancelled_at"
        case cancelledBy = "cancelled_by"
        case cancellationReason = "cancellation_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreTemplate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let title: String
    let description: String?
    let instructions: String?
    let categoryId: UUID?
    let roomId: UUID?
    let assignmentMode: ChoreAssignmentMode
    let completionMode: ChoreCompletionMode
    let pointsValue: Int
    let requiresApproval: Bool
    let requiresPhoto: Bool
    let isActive: Bool
    let archivedAt: Date?
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case title
        case description
        case instructions
        case categoryId = "category_id"
        case roomId = "room_id"
        case assignmentMode = "assignment_mode"
        case completionMode = "completion_mode"
        case pointsValue = "points_value"
        case requiresApproval = "requires_approval"
        case requiresPhoto = "requires_photo"
        case isActive = "is_active"
        case archivedAt = "archived_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreTemplateAssignee: Codable, Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let templateId: UUID
        let userId: UUID
    }

    let templateId: UUID
    let userId: UUID
    let createdAt: Date

    var id: ID {
        ID(templateId: templateId, userId: userId)
    }

    enum CodingKeys: String, CodingKey {
        case templateId = "template_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct ChoreRecurrenceRule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let templateId: UUID
    let frequency: ChoreFrequency
    let intervalValue: Int
    let startDate: Date
    let dueTime: ChoreLocalTime?
    let durationMinutes: Int
    let isAllDay: Bool
    let weekdays: [Int]
    let dayOfMonth: Int?
    let monthOfYear: Int?
    let endType: ChoreRecurrenceEndType
    let endsOn: Date?
    let occurrenceCount: Int?
    let timezone: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case frequency
        case intervalValue = "interval_value"
        case startDate = "start_date"
        case dueTime = "due_time"
        case durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day"
        case weekdays
        case dayOfMonth = "day_of_month"
        case monthOfYear = "month_of_year"
        case endType = "end_type"
        case endsOn = "ends_on"
        case occurrenceCount = "occurrence_count"
        case timezone
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        templateId = try container.decode(UUID.self, forKey: .templateId)
        frequency = try container.decode(ChoreFrequency.self, forKey: .frequency)
        intervalValue = try container.decode(Int.self, forKey: .intervalValue)
        startDate = try container.decodeDateOnly(forKey: .startDate)
        dueTime = try container.decodeIfPresent(ChoreLocalTime.self, forKey: .dueTime)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        dayOfMonth = try container.decodeIfPresent(Int.self, forKey: .dayOfMonth)
        monthOfYear = try container.decodeIfPresent(Int.self, forKey: .monthOfYear)
        endType = try container.decode(ChoreRecurrenceEndType.self, forKey: .endType)
        endsOn = try container.decodeDateOnlyIfPresent(forKey: .endsOn)
        occurrenceCount = try container.decodeIfPresent(Int.self, forKey: .occurrenceCount)
        timezone = try container.decode(String.self, forKey: .timezone)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct ChoreOccurrence: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let templateId: UUID
    let scheduledKey: String
    let titleSnapshot: String
    let descriptionSnapshot: String?
    let instructionsSnapshot: String?
    let categoryIdSnapshot: UUID?
    let roomIdSnapshot: UUID?
    let assignmentMode: ChoreAssignmentMode
    let completionMode: ChoreCompletionMode
    let pointsValueSnapshot: Int
    let requiresApprovalSnapshot: Bool
    let requiresPhotoSnapshot: Bool
    let dueAt: Date
    let endAt: Date
    let dueLocalDate: Date
    let isAllDay: Bool
    let status: ChoreOccurrenceStatus
    let claimedBy: UUID?
    let claimedAt: Date?
    let calendarEventId: UUID?
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let approvedAt: Date?
    let skippedAt: Date?
    let cancelledAt: Date?

    var isOverdue: Bool {
        dueAt < Date() && !status.isTerminalForOverdue
    }

    var displayStatus: ChoreOccurrenceDisplayStatus {
        isOverdue ? .overdue : .stored(status)
    }

    var title: String { titleSnapshot }
    var description: String? { descriptionSnapshot }
    var instructions: String? { instructionsSnapshot }
    var categoryId: UUID? { categoryIdSnapshot }
    var roomId: UUID? { roomIdSnapshot }
    var pointsValue: Int { pointsValueSnapshot }
    var requiresApproval: Bool { requiresApprovalSnapshot }
    var requiresPhoto: Bool { requiresPhotoSnapshot }
    var dueTime: ChoreLocalTime? { nil }
    var timezone: String { TimeZone.autoupdatingCurrent.identifier }

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case templateId = "template_id"
        case scheduledKey = "scheduled_key"
        case titleSnapshot = "title_snapshot"
        case descriptionSnapshot = "description_snapshot"
        case instructionsSnapshot = "instructions_snapshot"
        case categoryIdSnapshot = "category_id_snapshot"
        case roomIdSnapshot = "room_id_snapshot"
        case assignmentMode = "assignment_mode"
        case completionMode = "completion_mode"
        case pointsValueSnapshot = "points_value_snapshot"
        case requiresApprovalSnapshot = "requires_approval_snapshot"
        case requiresPhotoSnapshot = "requires_photo_snapshot"
        case dueAt = "due_at"
        case endAt = "end_at"
        case dueLocalDate = "due_local_date"
        case isAllDay = "is_all_day"
        case status
        case claimedBy = "claimed_by"
        case claimedAt = "claimed_at"
        case calendarEventId = "calendar_event_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case approvedAt = "approved_at"
        case skippedAt = "skipped_at"
        case cancelledAt = "cancelled_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeId = try container.decode(UUID.self, forKey: .homeId)
        templateId = try container.decode(UUID.self, forKey: .templateId)
        scheduledKey = try container.decode(String.self, forKey: .scheduledKey)
        titleSnapshot = try container.decode(String.self, forKey: .titleSnapshot)
        descriptionSnapshot = try container.decodeIfPresent(String.self, forKey: .descriptionSnapshot)
        instructionsSnapshot = try container.decodeIfPresent(String.self, forKey: .instructionsSnapshot)
        categoryIdSnapshot = try container.decodeIfPresent(UUID.self, forKey: .categoryIdSnapshot)
        roomIdSnapshot = try container.decodeIfPresent(UUID.self, forKey: .roomIdSnapshot)
        assignmentMode = try container.decode(ChoreAssignmentMode.self, forKey: .assignmentMode)
        completionMode = try container.decode(ChoreCompletionMode.self, forKey: .completionMode)
        pointsValueSnapshot = try container.decode(Int.self, forKey: .pointsValueSnapshot)
        requiresApprovalSnapshot = try container.decode(Bool.self, forKey: .requiresApprovalSnapshot)
        requiresPhotoSnapshot = try container.decode(Bool.self, forKey: .requiresPhotoSnapshot)
        dueAt = try container.decode(Date.self, forKey: .dueAt)
        endAt = try container.decode(Date.self, forKey: .endAt)
        dueLocalDate = try container.decodeDateOnly(forKey: .dueLocalDate)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        status = try container.decode(ChoreOccurrenceStatus.self, forKey: .status)
        claimedBy = try container.decodeIfPresent(UUID.self, forKey: .claimedBy)
        claimedAt = try container.decodeIfPresent(Date.self, forKey: .claimedAt)
        calendarEventId = try container.decodeIfPresent(UUID.self, forKey: .calendarEventId)
        createdBy = try container.decode(UUID.self, forKey: .createdBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        approvedAt = try container.decodeIfPresent(Date.self, forKey: .approvedAt)
        skippedAt = try container.decodeIfPresent(Date.self, forKey: .skippedAt)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
    }
}

struct ChoreOccurrenceAssignee: Codable, Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let occurrenceId: UUID
        let userId: UUID
    }

    let occurrenceId: UUID
    let userId: UUID
    let status: ChoreAssigneeStatus
    let assignedAt: Date
    let startedAt: Date?
    let submittedAt: Date?
    let completedAt: Date?

    var id: ID {
        ID(occurrenceId: occurrenceId, userId: userId)
    }

    enum CodingKeys: String, CodingKey {
        case occurrenceId = "occurrence_id"
        case userId = "user_id"
        case status
        case assignedAt = "assigned_at"
        case startedAt = "started_at"
        case submittedAt = "submitted_at"
        case completedAt = "completed_at"
    }
}

struct ChoreClaim: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let occurrenceId: UUID
    let userId: UUID
    let claimedAt: Date
    let releasedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case occurrenceId = "occurrence_id"
        case userId = "user_id"
        case claimedAt = "claimed_at"
        case releasedAt = "released_at"
    }
}

struct ChoreSubmission: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let occurrenceId: UUID
    let submittedBy: UUID
    let note: String?
    let photoPath: String?
    let status: ChoreSubmissionStatus
    let submittedAt: Date
    let reviewedAt: Date?
    let reviewedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case occurrenceId = "occurrence_id"
        case submittedBy = "submitted_by"
        case note
        case photoPath = "photo_path"
        case status
        case submittedAt = "submitted_at"
        case reviewedAt = "reviewed_at"
        case reviewedBy = "reviewed_by"
    }
}

struct ChoreApproval: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let submissionId: UUID
    let occurrenceId: UUID
    let decision: ChoreApprovalDecision
    let adminNote: String?
    let pointsAwarded: Int?
    let reviewedBy: UUID
    let reviewedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case submissionId = "submission_id"
        case occurrenceId = "occurrence_id"
        case decision
        case adminNote = "admin_note"
        case pointsAwarded = "points_awarded"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
    }
}

struct ChorePointTransaction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let homeId: UUID
    let userId: UUID
    let transactionType: ChorePointTransactionType
    let pointsDelta: Int
    let occurrenceId: UUID?
    let submissionId: UUID?
    let rewardId: UUID?
    let note: String?
    let createdBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case userId = "user_id"
        case transactionType = "transaction_type"
        case pointsDelta = "points_delta"
        case occurrenceId = "occurrence_id"
        case submissionId = "submission_id"
        case rewardId = "reward_id"
        case note
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case points
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alternateContainer = try decoder.container(keyedBy: AlternateCodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        homeId = try container.decode(UUID.self, forKey: .homeId)
        userId = try container.decode(UUID.self, forKey: .userId)
        transactionType = try container.decode(ChorePointTransactionType.self, forKey: .transactionType)
        pointsDelta = try container.decodeIfPresent(Int.self, forKey: .pointsDelta)
            ?? alternateContainer.decode(Int.self, forKey: .points)
        occurrenceId = try container.decodeIfPresent(UUID.self, forKey: .occurrenceId)
        submissionId = try container.decodeIfPresent(UUID.self, forKey: .submissionId)
        rewardId = try container.decodeIfPresent(UUID.self, forKey: .rewardId)
        note = try container.decodeIfPresent(String.self, forKey: .note)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .description)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
