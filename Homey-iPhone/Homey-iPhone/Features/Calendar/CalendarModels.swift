import Foundation

struct PhoneCalendarEvent: Decodable, Identifiable, Hashable {
    let eventID: UUID
    let occurrenceID: String
    let occurrenceStartsAt: Date
    let homeID: UUID
    let categoryID: UUID?
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
    let recurrenceFrequency: PhoneCalendarRecurrenceFrequency?
    let recurrenceInterval: Int
    let recurrenceDaysOfWeek: [Int]?
    let recurrenceEndDate: String?
    let recurrenceCount: Int?
    let assignedUserIDs: [UUID]

    var id: String { occurrenceID }
    var occurrenceEndsAt: Date { occurrenceStartsAt.addingTimeInterval(endsAt.timeIntervalSince(startsAt)) }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", occurrenceID = "occurrence_id", occurrenceStartsAt = "occurrence_starts_at"
        case homeID = "home_id", categoryID = "category_id", categoryName = "category_name"
        case categoryColorHex = "category_color_hex", categoryIconName = "category_icon_name"
        case title, notes, location, timezone
        case startsAt = "starts_at", endsAt = "ends_at", isAllDay = "is_all_day"
        case isRecurring = "is_recurring", isException = "is_exception"
        case recurrenceFrequency = "recurrence_frequency", recurrenceInterval = "recurrence_interval"
        case recurrenceDaysOfWeek = "recurrence_days_of_week", recurrenceEndDate = "recurrence_end_date"
        case recurrenceCount = "recurrence_count"
        case assignedUserIDs = "assigned_user_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(UUID.self, forKey: .eventID)
        occurrenceID = try container.decodeIfPresent(String.self, forKey: .occurrenceID) ?? eventID.uuidString
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        occurrenceStartsAt = try container.decodeIfPresent(Date.self, forKey: .occurrenceStartsAt) ?? startsAt
        homeID = try container.decode(UUID.self, forKey: .homeID)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        categoryColorHex = try container.decodeIfPresent(String.self, forKey: .categoryColorHex)
        categoryIconName = try container.decodeIfPresent(String.self, forKey: .categoryIconName)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        timezone = try container.decode(String.self, forKey: .timezone)
        isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        isException = try container.decodeIfPresent(Bool.self, forKey: .isException) ?? false
        recurrenceFrequency = try container.decodeIfPresent(PhoneCalendarRecurrenceFrequency.self, forKey: .recurrenceFrequency)
        recurrenceInterval = try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval) ?? 1
        recurrenceDaysOfWeek = try container.decodeIfPresent([Int].self, forKey: .recurrenceDaysOfWeek)
        recurrenceEndDate = try container.decodeIfPresent(String.self, forKey: .recurrenceEndDate)
        recurrenceCount = try container.decodeIfPresent(Int.self, forKey: .recurrenceCount)
        assignedUserIDs = try container.decodeIfPresent([UUID].self, forKey: .assignedUserIDs) ?? []
    }

    func overlaps(_ day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return occurrenceStartsAt < end && occurrenceEndsAt > start
    }
}

enum PhoneCalendarRecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Hashable {
    case daily, weekly, monthly, yearly
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct PhoneCalendarRecurrence: Hashable {
    var frequency: PhoneCalendarRecurrenceFrequency?
    var interval = 1
    var daysOfWeek: [Int]?
    var endDate: Date?
    var count: Int?
}

struct PhoneCalendarDraft {
    var title = ""
    var isAllDay = false
    var startsAt: Date
    var endsAt: Date
    var categoryID: UUID?
    var location = ""
    var notes = ""
    var recurrence = PhoneCalendarRecurrence()
    var assignedUserIDs: [UUID] = []

    init(date: Date, calendar: Calendar) {
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        components.hour = time.hour
        components.minute = time.minute
        startsAt = calendar.date(from: components) ?? date
        endsAt = calendar.date(byAdding: .hour, value: 1, to: startsAt) ?? startsAt
    }

    init(event: PhoneCalendarEvent, calendar: Calendar, occurrenceOnly: Bool) {
        title = event.title
        isAllDay = event.isAllDay
        startsAt = occurrenceOnly ? event.occurrenceStartsAt : event.startsAt
        let rawEnd = occurrenceOnly ? event.occurrenceEndsAt : event.endsAt
        endsAt = event.isAllDay ? (calendar.date(byAdding: .day, value: -1, to: rawEnd) ?? rawEnd) : rawEnd
        categoryID = event.categoryID
        location = event.location ?? ""
        notes = event.notes ?? ""
        assignedUserIDs = event.assignedUserIDs
        if !occurrenceOnly {
            recurrence = PhoneCalendarRecurrence(
                frequency: event.recurrenceFrequency,
                interval: event.recurrenceInterval,
                daysOfWeek: event.recurrenceDaysOfWeek,
                endDate: event.recurrenceEndDate.flatMap { PhoneCalendarDateOnly.date($0, timezone: calendar.timeZone) },
                count: event.recurrenceCount
            )
        }
    }
}

enum PhoneCalendarDateOnly {
    nonisolated static func string(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    nonisolated static func date(_ value: String, timezone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
