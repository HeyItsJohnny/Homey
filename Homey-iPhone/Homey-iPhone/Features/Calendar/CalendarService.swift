import Foundation
import Supabase

struct PhoneCalendarService {
    private let client = SupabaseManager.shared.client

    func fetchUserEvents(homeID: UUID, start: Date, end: Date) async throws -> (events: [PhoneCalendarEvent], categories: [PhoneCalendarCategory]) {
        do {
            let events: [PhoneCalendarEvent] = try await client.rpc(
                "get_calendar_events",
                params: PhoneCalendarRangeParameters(homeID: homeID, start: start, end: end)
            ).execute().value
            let unique = Dictionary(grouping: events, by: \.occurrenceID).compactMap { $0.value.max(by: { $0.occurrenceStartsAt < $1.occurrenceStartsAt }) }
            return (
                unique.sortedForCalendar,
                try await fetchCategories(homeID: homeID)
            )
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "load", id: homeID)
            throw PhoneCalendarError.loadFailed
        }
    }

    func fetchCategories(homeID: UUID) async throws -> [PhoneCalendarCategory] {
        do {
            let rows: [PhoneCalendarCategory] = try await client.from("calendar_categories")
                .select("id,home_id,name,color_hex,icon_name,sort_order,system_key,is_system")
                .eq("home_id", value: homeID.uuidString)
                .order("sort_order")
                .execute().value
            return rows
        } catch {
            if isCancellation(error) { throw CancellationError() }
            throw error
        }
    }

    func create(homeID: UUID, draft: PhoneCalendarDraft, timezone: TimeZone, calendar: Calendar) async throws {
        let input = try normalized(draft, timezone: timezone, calendar: calendar)
        do {
            try await client.rpc("create_calendar_event", params: PhoneCreateCalendarEventParameters(
                homeID: homeID, input: input, timezone: timezone
            )).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "create_calendar_event", id: homeID)
            throw PhoneCalendarError.saveFailed
        }
    }

    func updateSeries(eventID: UUID, draft: PhoneCalendarDraft, timezone: TimeZone, calendar: Calendar) async throws {
        let input = try normalized(draft, timezone: timezone, calendar: calendar)
        do {
            try await client.rpc("update_calendar_event", params: PhoneUpdateCalendarEventParameters(
                eventID: eventID, input: input, timezone: timezone
            )).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "update_calendar_event", id: eventID)
            throw PhoneCalendarError.saveFailed
        }
    }

    func updateOccurrence(event: PhoneCalendarEvent, draft: PhoneCalendarDraft, timezone: TimeZone, calendar: Calendar) async throws {
        let input = try normalized(draft, timezone: timezone, calendar: calendar)
        do {
            try await client.rpc("update_calendar_event_occurrence", params: PhoneUpdateOccurrenceParameters(
                event: event, input: input, timezone: timezone
            )).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "update_calendar_event_occurrence", id: event.eventID)
            throw PhoneCalendarError.saveFailed
        }
    }

    func deleteSeries(eventID: UUID) async throws {
        do {
            try await client.rpc("delete_calendar_event", params: PhoneCalendarEventIDParameters(eventID: eventID)).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "delete_calendar_event", id: eventID)
            throw PhoneCalendarError.deleteFailed
        }
    }

    func deleteOccurrence(event: PhoneCalendarEvent) async throws {
        do {
            try await client.rpc("delete_calendar_event_occurrence", params: PhoneDeleteOccurrenceParameters(event: event)).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "delete_calendar_event_occurrence", id: event.eventID)
            throw PhoneCalendarError.deleteFailed
        }
    }

    private func normalized(_ draft: PhoneCalendarDraft, timezone: TimeZone, calendar: Calendar) throws -> PhoneNormalizedCalendarInput {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw PhoneCalendarError.emptyTitle }
        let startsAt: Date
        let endsAt: Date
        if draft.isAllDay {
            startsAt = calendar.startOfDay(for: draft.startsAt)
            let inclusiveEnd = max(calendar.startOfDay(for: draft.endsAt), startsAt)
            endsAt = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
        } else {
            startsAt = draft.startsAt
            endsAt = draft.endsAt
        }
        guard endsAt > startsAt else { throw PhoneCalendarError.invalidRange }
        var recurrence = draft.recurrence
        recurrence.interval = max(1, recurrence.interval)
        if recurrence.frequency == .weekly, recurrence.daysOfWeek?.isEmpty != false {
            recurrence.daysOfWeek = [PhoneCalendarWeekday.isoValue(for: startsAt, calendar: calendar)]
        }
        return PhoneNormalizedCalendarInput(
            title: title,
            notes: draft.notes.trimmedNil,
            location: draft.location.trimmedNil,
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: draft.isAllDay,
            categoryID: draft.categoryID,
            assignedUserIDs: draft.assignedUserIDs,
            recurrence: recurrence
        )
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { return isCancellation(underlying) }
        return false
    }

    private func log(_ error: Error, operation: String, id: UUID) {
        #if DEBUG
        print("[Homey Calendar] \(operation) id=\(id.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

enum PhoneCalendarError: LocalizedError {
    case loadFailed, emptyTitle, invalidRange, saveFailed, deleteFailed
    var errorDescription: String? {
        switch self {
        case .loadFailed: "We couldn't refresh the calendar."
        case .emptyTitle: "Enter an event title."
        case .invalidRange: "The event must end after it starts."
        case .saveFailed: "We couldn't save this event."
        case .deleteFailed: "We couldn't delete this event."
        }
    }
}

private struct PhoneNormalizedCalendarInput {
    let title: String
    let notes: String?
    let location: String?
    let startsAt: Date
    let endsAt: Date
    let isAllDay: Bool
    let categoryID: UUID?
    let assignedUserIDs: [UUID]
    let recurrence: PhoneCalendarRecurrence
}

private struct PhoneCalendarRangeParameters: Encodable {
    let homeID: UUID
    let start: String
    let end: String
    init(homeID: UUID, start: Date, end: Date) {
        self.homeID = homeID
        self.start = PhoneCalendarRPCDate.string(start)
        self.end = PhoneCalendarRPCDate.string(end)
    }
    enum CodingKeys: String, CodingKey { case homeID = "target_home_id", start = "range_start", end = "range_end" }
}

private struct PhoneCreateCalendarEventParameters: Encodable {
    let homeID: UUID
    let title: String
    let notes: String?
    let location: String?
    let startsAt: String
    let endsAt: String
    let isAllDay: Bool
    let timezone: String
    let categoryID: UUID?
    let assignedUserIDs: [UUID]
    let frequency: PhoneCalendarRecurrenceFrequency?
    let interval: Int
    let weekdays: [Int]?
    let endDate: String?
    let count: Int?
    init(homeID: UUID, input: PhoneNormalizedCalendarInput, timezone: TimeZone) {
        self.homeID = homeID; title = input.title; notes = input.notes; location = input.location
        startsAt = PhoneCalendarRPCDate.string(input.startsAt); endsAt = PhoneCalendarRPCDate.string(input.endsAt)
        isAllDay = input.isAllDay; self.timezone = timezone.identifier; categoryID = input.categoryID
        assignedUserIDs = input.assignedUserIDs
        frequency = input.recurrence.frequency; interval = frequency == nil ? 1 : input.recurrence.interval
        weekdays = frequency == nil ? nil : input.recurrence.daysOfWeek
        endDate = frequency == nil ? nil : input.recurrence.endDate.map { PhoneCalendarDateOnly.string($0, timezone: timezone) }
        count = frequency == nil ? nil : input.recurrence.count
    }
    enum CodingKeys: String, CodingKey {
        case homeID = "target_home_id", title = "event_title", notes = "event_notes", location = "event_location"
        case startsAt = "event_starts_at", endsAt = "event_ends_at", isAllDay = "event_is_all_day"
        case timezone = "event_timezone", categoryID = "event_category_id", assignedUserIDs = "assigned_user_ids"
        case frequency = "event_recurrence_frequency", interval = "event_recurrence_interval"
        case weekdays = "event_recurrence_days_of_week", endDate = "event_recurrence_end_date", count = "event_recurrence_count"
    }
}

private struct PhoneUpdateCalendarEventParameters: Encodable {
    let eventID: UUID
    let title: String
    let notes: String?
    let location: String?
    let startsAt: String
    let endsAt: String
    let isAllDay: Bool
    let timezone: String
    let categoryID: UUID?
    let assignedUserIDs: [UUID]
    let frequency: PhoneCalendarRecurrenceFrequency?
    let interval: Int
    let weekdays: [Int]?
    let endDate: String?
    let count: Int?
    init(eventID: UUID, input: PhoneNormalizedCalendarInput, timezone: TimeZone) {
        self.eventID = eventID; title = input.title; notes = input.notes; location = input.location
        startsAt = PhoneCalendarRPCDate.string(input.startsAt); endsAt = PhoneCalendarRPCDate.string(input.endsAt)
        isAllDay = input.isAllDay; self.timezone = timezone.identifier; categoryID = input.categoryID
        assignedUserIDs = input.assignedUserIDs
        frequency = input.recurrence.frequency; interval = frequency == nil ? 1 : input.recurrence.interval
        weekdays = frequency == nil ? nil : input.recurrence.daysOfWeek
        endDate = frequency == nil ? nil : input.recurrence.endDate.map { PhoneCalendarDateOnly.string($0, timezone: timezone) }
        count = frequency == nil ? nil : input.recurrence.count
    }
    enum CodingKeys: String, CodingKey {
        case eventID = "target_event_id", title = "event_title", notes = "event_notes", location = "event_location"
        case startsAt = "event_starts_at", endsAt = "event_ends_at", isAllDay = "event_is_all_day"
        case timezone = "event_timezone", categoryID = "event_category_id", assignedUserIDs = "assigned_user_ids"
        case frequency = "event_recurrence_frequency", interval = "event_recurrence_interval"
        case weekdays = "event_recurrence_days_of_week", endDate = "event_recurrence_end_date", count = "event_recurrence_count"
    }
}

private struct PhoneUpdateOccurrenceParameters: Encodable {
    let eventID: UUID; let occurrenceStartsAt: String; let title: String; let startsAt: String; let endsAt: String
    let timezone: String; let isAllDay: Bool; let notes: String?; let location: String?; let categoryID: UUID?
    init(event: PhoneCalendarEvent, input: PhoneNormalizedCalendarInput, timezone: TimeZone) {
        eventID = event.eventID; occurrenceStartsAt = PhoneCalendarRPCDate.string(event.occurrenceStartsAt)
        title = input.title; startsAt = PhoneCalendarRPCDate.string(input.startsAt); endsAt = PhoneCalendarRPCDate.string(input.endsAt)
        self.timezone = timezone.identifier; isAllDay = input.isAllDay; notes = input.notes; location = input.location; categoryID = input.categoryID
    }
    enum CodingKeys: String, CodingKey {
        case eventID = "target_event_id", occurrenceStartsAt = "target_occurrence_starts_at", title = "event_title"
        case startsAt = "event_starts_at", endsAt = "event_ends_at", timezone = "event_timezone"
        case isAllDay = "event_is_all_day", notes = "event_notes", location = "event_location", categoryID = "event_category_id"
    }
}

private struct PhoneCalendarEventIDParameters: Encodable {
    let eventID: UUID
    enum CodingKeys: String, CodingKey { case eventID = "target_event_id" }
}
private struct PhoneDeleteOccurrenceParameters: Encodable {
    let eventID: UUID; let occurrenceStartsAt: String
    init(event: PhoneCalendarEvent) { eventID = event.eventID; occurrenceStartsAt = PhoneCalendarRPCDate.string(event.occurrenceStartsAt) }
    enum CodingKeys: String, CodingKey { case eventID = "target_event_id", occurrenceStartsAt = "target_occurrence_starts_at" }
}

private enum PhoneCalendarRPCDate {
    static let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

private enum PhoneCalendarWeekday {
    static func isoValue(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}

private extension String {
    var trimmedNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element == PhoneCalendarEvent {
    var sortedForCalendar: [PhoneCalendarEvent] {
        sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.occurrenceStartsAt != $1.occurrenceStartsAt { return $0.occurrenceStartsAt < $1.occurrenceStartsAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}
