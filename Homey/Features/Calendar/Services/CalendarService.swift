import Foundation
import PostgREST
import Supabase

@MainActor
final class CalendarService: ObservableObject {
    private let client = SupabaseManager.shared.client
    private let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func fetchEvents(homeId: UUID, rangeStart: Date, rangeEnd: Date) async throws -> [CalendarEvent] {
        guard rangeEnd > rangeStart else {
            throw CalendarServiceError.invalidDateRange
        }

        do {
            try await requireAuthenticatedSession()

            let events: [CalendarEvent] = try await client
                .rpc(
                    "get_calendar_events",
                    params: GetCalendarEventsParameters(
                        targetHomeId: homeId,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd
                    )
                )
                .execute()
                .value

            return events.sorted { lhs, rhs in
                if lhs.startsAt != rhs.startsAt {
                    return lhs.startsAt < rhs.startsAt
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        } catch {
            logCalendarError(error, rpcName: "get_calendar_events", homeId: homeId)
            throw CalendarServiceError.loadEventsFailed
        }
    }

    func fetchEventsForDay(homeId: UUID, date: Date) async throws -> [CalendarEvent] {
        let startOfDay = calendar.startOfDay(for: date)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw CalendarServiceError.invalidDateRange
        }

        return try await fetchEvents(homeId: homeId, rangeStart: startOfDay, rangeEnd: startOfNextDay)
    }

    func fetchEventsForVisibleMonth(homeId: UUID, month: Date) async throws -> [CalendarEvent] {
        let range = try visibleMonthRange(containing: month)
        return try await fetchEvents(homeId: homeId, rangeStart: range.start, rangeEnd: range.end)
    }

    func fetchUpcomingEvents(homeId: UUID, from date: Date = Date(), limit: Int) async throws -> [CalendarEvent] {
        guard limit > 0 else {
            return []
        }

        guard let rangeEnd = calendar.date(byAdding: .day, value: 90, to: date) else {
            throw CalendarServiceError.invalidDateRange
        }

        let events = try await fetchEvents(homeId: homeId, rangeStart: date, rangeEnd: rangeEnd)
        return Array(
            events
                .filter { $0.endsAt >= date }
                .sorted { lhs, rhs in
                    if lhs.startsAt != rhs.startsAt {
                        return lhs.startsAt < rhs.startsAt
                    }

                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    func createEvent(
        homeId: UUID,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String? = nil,
        categoryId: UUID? = nil,
        assignedUserIds: [UUID] = []
    ) async throws -> UUID {
        let normalizedInput = try normalizedEventInput(
            title: title,
            notes: notes,
            location: location,
            startsAt: startsAt,
            endsAt: endsAt,
            timezone: timezone,
            assignedUserIds: assignedUserIds
        )

        do {
            try await requireAuthenticatedSession()

            let eventId: UUID = try await client
                .rpc(
                    "create_calendar_event",
                    params: CreateCalendarEventParameters(
                        targetHomeId: homeId,
                        title: normalizedInput.title,
                        notes: normalizedInput.notes,
                        location: normalizedInput.location,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timezone: normalizedInput.timezone,
                        categoryId: categoryId,
                        assignedUserIds: normalizedInput.assignedUserIds
                    )
                )
                .execute()
                .value

            return eventId
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "create_calendar_event", homeId: homeId)
            throw CalendarServiceError.createEventFailed
        }
    }

    func updateEvent(
        eventId: UUID,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String? = nil,
        categoryId: UUID? = nil,
        assignedUserIds: [UUID] = []
    ) async throws {
        let normalizedInput = try normalizedEventInput(
            title: title,
            notes: notes,
            location: location,
            startsAt: startsAt,
            endsAt: endsAt,
            timezone: timezone,
            assignedUserIds: assignedUserIds
        )

        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "update_calendar_event",
                    params: UpdateCalendarEventParameters(
                        targetEventId: eventId,
                        title: normalizedInput.title,
                        notes: normalizedInput.notes,
                        location: normalizedInput.location,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timezone: normalizedInput.timezone,
                        categoryId: categoryId,
                        assignedUserIds: normalizedInput.assignedUserIds
                    )
                )
                .execute()
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "update_calendar_event", eventId: eventId)
            throw CalendarServiceError.updateEventFailed
        }
    }

    func deleteEvent(eventId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "delete_calendar_event",
                    params: CalendarEventIdParameters(targetEventId: eventId)
                )
                .execute()
        } catch {
            logCalendarError(error, rpcName: "delete_calendar_event", eventId: eventId)
            throw CalendarServiceError.deleteEventFailed
        }
    }

    func createCategory(homeId: UUID, name: String, colorHex: String, iconName: String? = nil) async throws -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColorHex = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIconName = normalizedOptionalString(iconName)

        guard !trimmedName.isEmpty else {
            throw CalendarServiceError.emptyCategoryName
        }

        guard !trimmedColorHex.isEmpty else {
            throw CalendarServiceError.invalidCategoryColor
        }

        do {
            try await requireAuthenticatedSession()

            let categoryId: UUID = try await client
                .rpc(
                    "create_calendar_category",
                    params: CreateCalendarCategoryParameters(
                        targetHomeId: homeId,
                        categoryName: trimmedName,
                        categoryColorHex: trimmedColorHex,
                        categoryIconName: trimmedIconName
                    )
                )
                .execute()
                .value

            return categoryId
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "create_calendar_category", homeId: homeId)
            throw CalendarServiceError.createCategoryFailed
        }
    }

    func deleteCategory(categoryId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "delete_calendar_category",
                    params: CalendarCategoryIdParameters(targetCategoryId: categoryId)
                )
                .execute()
        } catch {
            logCalendarError(error, rpcName: "delete_calendar_category", categoryId: categoryId)
            throw CalendarServiceError.deleteCategoryFailed
        }
    }

    private func requireAuthenticatedSession() async throws {
        _ = try await client.auth.session
    }

    private func normalizedEventInput(
        title: String,
        notes: String?,
        location: String?,
        startsAt: Date,
        endsAt: Date,
        timezone: String?,
        assignedUserIds: [UUID]
    ) throws -> NormalizedCalendarEventInput {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            throw CalendarServiceError.emptyTitle
        }

        guard endsAt >= startsAt else {
            throw CalendarServiceError.invalidDateRange
        }

        let resolvedTimezone = normalizedTimezone(timezone)
        let uniqueAssignedUserIds = Array(Set(assignedUserIds)).sorted { $0.uuidString < $1.uuidString }

        return NormalizedCalendarEventInput(
            title: trimmedTitle,
            notes: normalizedOptionalString(notes),
            location: normalizedOptionalString(location),
            timezone: resolvedTimezone,
            assignedUserIds: uniqueAssignedUserIds
        )
    }

    private func normalizedTimezone(_ timezone: String?) -> String {
        let trimmedTimezone = timezone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedTimezone.isEmpty,
           TimeZone(identifier: trimmedTimezone) != nil {
            return trimmedTimezone
        }

        return TimeZone.autoupdatingCurrent.identifier
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func visibleMonthRange(containing month: Date) throws -> (start: Date, end: Date) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let lastDayInMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            throw CalendarServiceError.invalidDateRange
        }

        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndDay = calendar.startOfDay(for: lastDayInMonth)
        let leadingDays = daysFromStartOfWeek(to: monthStart)
        let trailingDays = daysToEndOfWeek(from: monthEndDay)

        guard let visibleStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart),
              let visibleEnd = calendar.date(byAdding: .day, value: trailingDays + 1, to: monthEndDay) else {
            throw CalendarServiceError.invalidDateRange
        }

        return (visibleStart, visibleEnd)
    }

    private func daysFromStartOfWeek(to date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func daysToEndOfWeek(from date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let endOfWeekday = ((calendar.firstWeekday + 5) % 7) + 1
        return (endOfWeekday - weekday + 7) % 7
    }

    private func logCalendarError(
        _ error: Error,
        rpcName: String,
        homeId: UUID? = nil,
        eventId: UUID? = nil,
        categoryId: UUID? = nil
    ) {
        #if DEBUG
        print("========== CALENDAR RPC FAILED ==========")
        print("rpc: \(rpcName)")
        if let homeId {
            print("home_id: \(homeId.uuidString)")
        }
        if let eventId {
            print("event_id: \(eventId.uuidString)")
        }
        if let categoryId {
            print("category_id: \(categoryId.uuidString)")
        }
        print(String(reflecting: error))

        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        print("=========================================")
        #endif
    }
}

enum CalendarServiceError: LocalizedError, Equatable {
    case unauthenticated
    case emptyTitle
    case invalidDateRange
    case emptyCategoryName
    case invalidCategoryColor
    case loadEventsFailed
    case createEventFailed
    case updateEventFailed
    case deleteEventFailed
    case createCategoryFailed
    case deleteCategoryFailed

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .emptyTitle:
            return "Enter an event title."
        case .invalidDateRange:
            return "The event end time must be after the start time."
        case .emptyCategoryName:
            return "Enter a category name."
        case .invalidCategoryColor:
            return "Choose a category color."
        case .loadEventsFailed:
            return "We could not load calendar events."
        case .createEventFailed:
            return "We could not save this event."
        case .updateEventFailed:
            return "We could not update this event."
        case .deleteEventFailed:
            return "We could not delete this event."
        case .createCategoryFailed:
            return "We could not save this category."
        case .deleteCategoryFailed:
            return "We could not delete this category."
        }
    }
}

private struct NormalizedCalendarEventInput {
    let title: String
    let notes: String?
    let location: String?
    let timezone: String
    let assignedUserIds: [UUID]
}

private struct CreateCalendarEventParameters: Encodable {
    let targetHomeId: UUID
    let eventTitle: String
    let eventNotes: String?
    let eventLocation: String?
    let eventStartsAt: String
    let eventEndsAt: String
    let eventIsAllDay: Bool
    let eventTimezone: String
    let eventCategoryId: UUID?
    let assignedUserIds: [UUID]

    init(
        targetHomeId: UUID,
        title: String,
        notes: String?,
        location: String?,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?,
        assignedUserIds: [UUID]
    ) {
        self.targetHomeId = targetHomeId
        self.eventTitle = title
        self.eventNotes = notes
        self.eventLocation = location
        self.eventStartsAt = CalendarRPCDateFormatter.string(from: startsAt)
        self.eventEndsAt = CalendarRPCDateFormatter.string(from: endsAt)
        self.eventIsAllDay = isAllDay
        self.eventTimezone = timezone
        self.eventCategoryId = categoryId
        self.assignedUserIds = assignedUserIds
    }

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case eventTitle = "event_title"
        case eventNotes = "event_notes"
        case eventLocation = "event_location"
        case eventStartsAt = "event_starts_at"
        case eventEndsAt = "event_ends_at"
        case eventIsAllDay = "event_is_all_day"
        case eventTimezone = "event_timezone"
        case eventCategoryId = "event_category_id"
        case assignedUserIds = "assigned_user_ids"
    }
}

private struct UpdateCalendarEventParameters: Encodable {
    let targetEventId: UUID
    let eventTitle: String
    let eventNotes: String?
    let eventLocation: String?
    let eventStartsAt: String
    let eventEndsAt: String
    let eventIsAllDay: Bool
    let eventTimezone: String
    let eventCategoryId: UUID?
    let assignedUserIds: [UUID]

    init(
        targetEventId: UUID,
        title: String,
        notes: String?,
        location: String?,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?,
        assignedUserIds: [UUID]
    ) {
        self.targetEventId = targetEventId
        self.eventTitle = title
        self.eventNotes = notes
        self.eventLocation = location
        self.eventStartsAt = CalendarRPCDateFormatter.string(from: startsAt)
        self.eventEndsAt = CalendarRPCDateFormatter.string(from: endsAt)
        self.eventIsAllDay = isAllDay
        self.eventTimezone = timezone
        self.eventCategoryId = categoryId
        self.assignedUserIds = assignedUserIds
    }

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
        case eventTitle = "event_title"
        case eventNotes = "event_notes"
        case eventLocation = "event_location"
        case eventStartsAt = "event_starts_at"
        case eventEndsAt = "event_ends_at"
        case eventIsAllDay = "event_is_all_day"
        case eventTimezone = "event_timezone"
        case eventCategoryId = "event_category_id"
        case assignedUserIds = "assigned_user_ids"
    }
}

private struct CalendarEventIdParameters: Encodable {
    let targetEventId: UUID

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
    }
}

private struct GetCalendarEventsParameters: Encodable {
    let targetHomeId: UUID
    let rangeStart: String
    let rangeEnd: String

    init(targetHomeId: UUID, rangeStart: Date, rangeEnd: Date) {
        self.targetHomeId = targetHomeId
        self.rangeStart = CalendarRPCDateFormatter.string(from: rangeStart)
        self.rangeEnd = CalendarRPCDateFormatter.string(from: rangeEnd)
    }

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
    }
}

private struct CreateCalendarCategoryParameters: Encodable {
    let targetHomeId: UUID
    let categoryName: String
    let categoryColorHex: String
    let categoryIconName: String?

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case categoryName = "category_name"
        case categoryColorHex = "category_color_hex"
        case categoryIconName = "category_icon_name"
    }
}

private struct CalendarCategoryIdParameters: Encodable {
    let targetCategoryId: UUID

    enum CodingKeys: String, CodingKey {
        case targetCategoryId = "target_category_id"
    }
}

private enum CalendarRPCDateFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
