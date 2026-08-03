import Foundation

struct CalendarEvent: Codable, Identifiable, Hashable {
    let eventId: UUID
    let occurrenceId: String
    let occurrenceStartsAt: Date
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
    let isRecurring: Bool
    let isException: Bool
    let recurrenceFrequency: CalendarRecurrenceFrequency?
    let recurrenceInterval: Int
    let recurrenceDaysOfWeek: [CalendarWeekday]?
    let recurrenceEndDate: Date?
    let recurrenceCount: Int?
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date
    let updatedAt: Date
    let assignedUserIds: [UUID]

    var id: String { occurrenceId }

    var occurrenceEndsAt: Date {
        occurrenceStartsAt.addingTimeInterval(endsAt.timeIntervalSince(startsAt))
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case occurrenceId = "occurrence_id"
        case occurrenceStartsAt = "occurrence_starts_at"
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
        case isRecurring = "is_recurring"
        case isException = "is_exception"
        case recurrenceFrequency = "recurrence_frequency"
        case recurrenceInterval = "recurrence_interval"
        case recurrenceDaysOfWeek = "recurrence_days_of_week"
        case recurrenceEndDate = "recurrence_end_date"
        case recurrenceCount = "recurrence_count"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case assignedUserIds = "assigned_user_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(UUID.self, forKey: .eventId)
        homeId = try container.decode(UUID.self, forKey: .homeId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        categoryColorHex = try container.decodeIfPresent(String.self, forKey: .categoryColorHex)
        categoryIconName = try container.decodeIfPresent(String.self, forKey: .categoryIconName)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        timezone = try container.decode(String.self, forKey: .timezone)
        occurrenceStartsAt = try container.decodeIfPresent(Date.self, forKey: .occurrenceStartsAt) ?? startsAt
        occurrenceId = try container.decodeIfPresent(String.self, forKey: .occurrenceId)
            ?? "\(eventId.uuidString):\(CalendarEventOccurrenceIdentityFormatter.string(from: occurrenceStartsAt))"
        isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        isException = try container.decodeIfPresent(Bool.self, forKey: .isException) ?? false
        recurrenceFrequency = try container.decodeIfPresent(CalendarRecurrenceFrequency.self, forKey: .recurrenceFrequency)
        recurrenceInterval = try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval) ?? 1
        recurrenceDaysOfWeek = try container.decodeIfPresent([CalendarWeekday].self, forKey: .recurrenceDaysOfWeek)
        recurrenceEndDate = try Self.decodeDateOnlyIfPresent(from: container, forKey: .recurrenceEndDate)
        recurrenceCount = try container.decodeIfPresent(Int.self, forKey: .recurrenceCount)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        updatedBy = try container.decodeIfPresent(UUID.self, forKey: .updatedBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        assignedUserIds = try container.decodeIfPresent([UUID].self, forKey: .assignedUserIds) ?? []
    }

    private static func decodeDateOnlyIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        return CalendarDateOnlyFormatter.date(from: value)
    }
}

enum CalendarRecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Hashable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }
}

enum CalendarWeekday: Int, Codable, CaseIterable, Identifiable, Hashable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        case .sunday:
            return "Sunday"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .monday:
            return "Mon"
        case .tuesday:
            return "Tue"
        case .wednesday:
            return "Wed"
        case .thursday:
            return "Thu"
        case .friday:
            return "Fri"
        case .saturday:
            return "Sat"
        case .sunday:
            return "Sun"
        }
    }
}

enum CalendarRecurrenceEnd: Equatable, Hashable {
    case never
    case onDate(Date)
    case afterCount(Int)
}

struct CalendarRecurrenceInput: Equatable, Hashable {
    var frequency: CalendarRecurrenceFrequency?
    var interval: Int
    var daysOfWeek: [CalendarWeekday]?
    var endDate: Date?
    var count: Int?

    nonisolated init(
        frequency: CalendarRecurrenceFrequency? = nil,
        interval: Int = 1,
        daysOfWeek: [CalendarWeekday]? = nil,
        endDate: Date? = nil,
        count: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.daysOfWeek = daysOfWeek
        self.endDate = endDate
        self.count = count
    }
}

enum CalendarDateOnlyFormatter {
    static func string(from date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private enum CalendarEventOccurrenceIdentityFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

struct CalendarCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let homeId: UUID
    let name: String
    let colorHex: String
    let iconName: String?
    let sortOrder: Int
    let systemKey: String?
    let isSystem: Bool
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    var systemCategoryKey: CalendarSystemCategoryKey? {
        guard isSystem, let systemKey else {
            return nil
        }

        return CalendarSystemCategoryKey(rawValue: systemKey)
    }

    var isProtectedSystemCategory: Bool {
        isSystem
    }

    var isMealSystemCategory: Bool {
        systemCategoryKey == .meal
    }

    var capabilities: CalendarCategoryCapabilities {
        CalendarCategoryCapabilities(isSystemCategory: isProtectedSystemCategory)
    }

    func replacingColorHex(_ colorHex: String) -> CalendarCategory {
        CalendarCategory(
            id: id,
            homeId: homeId,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
            sortOrder: sortOrder,
            systemKey: systemKey,
            isSystem: isSystem,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case systemKey = "system_key"
        case isSystem = "is_system"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        homeId: UUID,
        name: String,
        colorHex: String,
        iconName: String?,
        sortOrder: Int,
        systemKey: String? = nil,
        isSystem: Bool = false,
        createdBy: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.homeId = homeId
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.systemKey = systemKey
        self.isSystem = isSystem
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeId = try container.decode(UUID.self, forKey: .homeId)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        systemKey = try container.decodeIfPresent(String.self, forKey: .systemKey)
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum CalendarSystemCategoryKey: String, Codable, CaseIterable {
    case family
    case school
    case work
    case sports
    case appointment
    case meal
    case chore
    case birthday
    case holiday
    case other
}

struct CalendarCategoryCapabilities: Hashable {
    let canRename: Bool
    let canDelete: Bool
    let canChangeColor: Bool
    let canChangeIcon: Bool

    init(isSystemCategory: Bool) {
        canRename = !isSystemCategory
        canDelete = !isSystemCategory
        canChangeColor = true
        canChangeIcon = !isSystemCategory
    }
}
