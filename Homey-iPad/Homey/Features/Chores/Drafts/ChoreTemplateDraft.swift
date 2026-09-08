import Foundation

struct ChoreTemplateDraft: Equatable, Sendable {
    var id: UUID?
    var homeId: UUID
    var title: String
    var description: String
    var instructions: String
    var categoryId: UUID?
    var roomId: UUID?
    var assignmentMode: ChoreAssignmentMode
    var completionMode: ChoreCompletionMode
    var pointsValue: Int
    var requiresApproval: Bool
    var requiresPhoto: Bool
    var contributesToRoomCleaning: Bool
    var frequency: ChoreFrequency
    var intervalValue: Int
    var startDate: Date
    var dueTime: ChoreLocalTime?
    var durationMinutes: Int
    var isAllDay: Bool
    var weekdays: Set<Int>
    var dayOfMonth: Int?
    var monthOfYear: Int?
    var endType: ChoreRecurrenceEndType
    var endsOn: Date?
    var occurrenceCount: Int?
    var timezone: String
    var assigneeIds: [UUID]

    init(
        id: UUID? = nil,
        homeId: UUID,
        title: String,
        description: String = "",
        instructions: String = "",
        categoryId: UUID? = nil,
        roomId: UUID? = nil,
        assignmentMode: ChoreAssignmentMode = .assigned,
        completionMode: ChoreCompletionMode = .single,
        pointsValue: Int = 0,
        requiresApproval: Bool = false,
        requiresPhoto: Bool = false,
        contributesToRoomCleaning: Bool = false,
        frequency: ChoreFrequency = .none,
        intervalValue: Int = 1,
        startDate: Date,
        dueTime: ChoreLocalTime? = nil,
        durationMinutes: Int = 30,
        isAllDay: Bool = true,
        weekdays: Set<Int> = [],
        dayOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        endType: ChoreRecurrenceEndType = .never,
        endsOn: Date? = nil,
        occurrenceCount: Int? = nil,
        timezone: String,
        assigneeIds: [UUID] = []
    ) {
        self.id = id
        self.homeId = homeId
        self.title = title
        self.description = description
        self.instructions = instructions
        self.categoryId = categoryId
        self.roomId = roomId
        self.assignmentMode = assignmentMode
        self.completionMode = completionMode
        self.pointsValue = pointsValue
        self.requiresApproval = requiresApproval
        self.requiresPhoto = requiresPhoto
        self.contributesToRoomCleaning = contributesToRoomCleaning
        self.frequency = frequency
        self.intervalValue = intervalValue
        self.startDate = startDate
        self.dueTime = dueTime
        self.durationMinutes = durationMinutes
        self.isAllDay = isAllDay
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.monthOfYear = monthOfYear
        self.endType = endType
        self.endsOn = endsOn
        self.occurrenceCount = occurrenceCount
        self.timezone = timezone
        self.assigneeIds = assigneeIds
    }

    var normalized: ChoreTemplateDraft {
        var draft = self
        draft.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.timezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.assigneeIds = Array(Set(assigneeIds)).sorted { $0.uuidString < $1.uuidString }
        draft.categoryId = nil
        draft.requiresPhoto = false

        if draft.frequency == .none {
            draft.endType = .afterCount
            draft.occurrenceCount = 1
            draft.weekdays = []
            draft.dayOfMonth = nil
            draft.monthOfYear = nil
        }

        if draft.isAllDay {
            draft.dueTime = nil
        }

        if draft.assignmentMode == .open {
            draft.assigneeIds = []
            draft.completionMode = .single
        } else if draft.assigneeIds.count <= 1 {
            draft.completionMode = .single
        } else {
            draft.completionMode = .everyone
        }

        return draft
    }

    func validated() throws -> ChoreTemplateDraft {
        let draft = normalized

        guard !draft.title.isEmpty else {
            throw ChoreValidationError.titleRequired
        }

        guard draft.pointsValue >= 0 else {
            throw ChoreValidationError.pointsCannotBeNegative
        }

        guard draft.intervalValue > 0 else {
            throw ChoreValidationError.intervalMustBePositive
        }

        guard draft.durationMinutes > 0 else {
            throw ChoreValidationError.durationMustBePositive
        }

        guard draft.roomId != nil else {
            throw ChoreValidationError.roomRequired
        }

        guard !draft.timezone.isEmpty, TimeZone(identifier: draft.timezone) != nil else {
            throw ChoreValidationError.invalidTimezone
        }

        switch draft.assignmentMode {
        case .assigned:
            guard !draft.assigneeIds.isEmpty else {
                throw ChoreValidationError.assignedChoreRequiresAssignee
            }
        case .open:
            guard draft.assigneeIds.isEmpty else {
                throw ChoreValidationError.openChoreCannotContainAssignees
            }
            guard draft.completionMode == .single else {
                throw ChoreValidationError.openChoreRequiresSingleCompletion
            }
        }

        if draft.isAllDay {
            guard draft.dueTime == nil else {
                throw ChoreValidationError.allDayChoreCannotHaveDueTime
            }
        } else {
            guard draft.dueTime != nil else {
                throw ChoreValidationError.timedChoreRequiresDueTime
            }
        }

        switch draft.frequency {
        case .none:
            guard draft.occurrenceCount == 1 else {
                throw ChoreValidationError.oneTimeChoreRequiresOneOccurrence
            }
        case .daily:
            break
        case .weekly:
            guard !draft.weekdays.isEmpty else {
                throw ChoreValidationError.weeklyRequiresWeekdays
            }
            guard draft.weekdays.allSatisfy({ (0...6).contains($0) }) else {
                throw ChoreValidationError.invalidWeekday
            }
        case .monthly:
            guard let dayOfMonth = draft.dayOfMonth, (1...31).contains(dayOfMonth) else {
                throw ChoreValidationError.monthlyRequiresDayOfMonth
            }
        case .yearly:
            guard let monthOfYear = draft.monthOfYear, (1...12).contains(monthOfYear) else {
                throw ChoreValidationError.yearlyRequiresMonthAndDay
            }
            guard let dayOfMonth = draft.dayOfMonth, (1...31).contains(dayOfMonth) else {
                throw ChoreValidationError.yearlyRequiresMonthAndDay
            }
        }

        switch draft.endType {
        case .never:
            break
        case .onDate:
            guard draft.endsOn != nil else {
                throw ChoreValidationError.endDateRequired
            }
        case .afterCount:
            guard let occurrenceCount = draft.occurrenceCount, occurrenceCount > 0 else {
                throw ChoreValidationError.occurrenceCountRequired
            }
        }

        return draft
    }
}

enum ChoreValidationError: LocalizedError, Equatable {
    case titleRequired
    case pointsCannotBeNegative
    case assignedChoreRequiresAssignee
    case openChoreCannotContainAssignees
    case openChoreRequiresSingleCompletion
    case weeklyRequiresWeekdays
    case invalidWeekday
    case monthlyRequiresDayOfMonth
    case yearlyRequiresMonthAndDay
    case oneTimeChoreRequiresOneOccurrence
    case allDayChoreCannotHaveDueTime
    case timedChoreRequiresDueTime
    case intervalMustBePositive
    case durationMustBePositive
    case roomRequired
    case invalidTimezone
    case endDateRequired
    case occurrenceCountRequired

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            return "Enter a chore title."
        case .pointsCannotBeNegative:
            return "Points cannot be negative."
        case .assignedChoreRequiresAssignee:
            return "Assigned chores require at least one assignee."
        case .openChoreCannotContainAssignees:
            return "Open chores cannot contain assignees."
        case .openChoreRequiresSingleCompletion:
            return "Open chores must use single completion mode."
        case .weeklyRequiresWeekdays:
            return "Weekly chores require at least one weekday."
        case .invalidWeekday:
            return "Choose valid weekdays."
        case .monthlyRequiresDayOfMonth:
            return "Monthly chores require a day of the month."
        case .yearlyRequiresMonthAndDay:
            return "Yearly chores require a month and day."
        case .oneTimeChoreRequiresOneOccurrence:
            return "One-time chores must generate exactly one occurrence."
        case .allDayChoreCannotHaveDueTime:
            return "All-day chores cannot have a due time."
        case .timedChoreRequiresDueTime:
            return "Timed chores require a due time."
        case .intervalMustBePositive:
            return "Interval must be positive."
        case .durationMustBePositive:
            return "Duration must be positive."
        case .roomRequired:
            return "Choose a Room."
        case .invalidTimezone:
            return "Choose a valid timezone."
        case .endDateRequired:
            return "Choose an end date."
        case .occurrenceCountRequired:
            return "Enter how many occurrences to create."
        }
    }
}
