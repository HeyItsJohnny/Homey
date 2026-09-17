import Foundation
import Supabase

/// The subset of a chore occurrence required to mirror it into Calendar.
/// Recurrence remains backend-owned; this model only represents generated rows.
struct ChoreCalendarOccurrence: Decodable, Identifiable, Sendable {
    let id: UUID
    let homeId: UUID
    let titleSnapshot: String
    let categoryIdSnapshot: UUID?
    let dueAt: Date
    let endAt: Date
    let isAllDay: Bool
    let calendarEventId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case titleSnapshot = "title_snapshot"
        case categoryIdSnapshot = "category_id_snapshot"
        case dueAt = "due_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case calendarEventId = "calendar_event_id"
    }

    func linking(calendarEventId: UUID) -> ChoreCalendarOccurrence {
        ChoreCalendarOccurrence(
            id: id, homeId: homeId, titleSnapshot: titleSnapshot,
            categoryIdSnapshot: categoryIdSnapshot, dueAt: dueAt, endAt: endAt,
            isAllDay: isAllDay, calendarEventId: calendarEventId
        )
    }
}

struct ChoreOccurrenceReplacementResult: Sendable {
    let removedOccurrenceIds: [UUID]
    let calendarEventIds: [UUID]
}

struct ChoreAssignmentRefreshResult: Sendable {
    let futureOccurrencesUpdated: Int
    let newAssigneeCount: Int
}

enum ChoreCalendarInfrastructureError: LocalizedError {
    case authenticationRequired
    case invalidDateRange
    case choreCategoryUnavailable
    case calendarSynchronizationFailed
    case repositoryOperationFailed

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "Your session has expired. Please sign in again."
        case .invalidDateRange: "Choose a valid date range."
        case .choreCategoryUnavailable: "Homey could not find the Chore calendar category for this Home."
        case .calendarSynchronizationFailed: "We could not synchronize this chore with the calendar."
        case .repositoryOperationFailed: "We could not update this chore."
        }
    }
}

@MainActor
final class ChoreCalendarService {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseManager.shared.client
    }

    func createEvent(
        homeId: UUID,
        title: String,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID
    ) async throws -> UUID {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, endsAt >= startsAt else {
            throw ChoreCalendarInfrastructureError.invalidDateRange
        }

        do {
            try await requireAuthenticatedSession()
            return try await client.rpc(
                "create_calendar_event",
                params: CreateCalendarEventParameters(
                    homeId: homeId,
                    title: trimmedTitle,
                    startsAt: startsAt,
                    endsAt: endsAt,
                    isAllDay: isAllDay,
                    timezone: timezone,
                    categoryId: categoryId
                )
            ).execute().value
        } catch let error as ChoreCalendarInfrastructureError {
            throw error
        } catch {
            log(error, operation: "create_calendar_event", identifier: homeId)
            throw ChoreCalendarInfrastructureError.calendarSynchronizationFailed
        }
    }

    /// Deletes exactly one base calendar event by its backend event UUID.
    func deleteEvent(eventId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client.rpc(
                "delete_calendar_event",
                params: CalendarEventIdParameters(eventId: eventId)
            ).execute()
        } catch {
            log(error, operation: "delete_calendar_event", identifier: eventId)
            throw ChoreCalendarInfrastructureError.calendarSynchronizationFailed
        }
    }

    func resolveChoreCategory(homeId: UUID) async throws -> UUID {
        do {
            try await requireAuthenticatedSession()
            let rows: [CalendarCategoryRow] = try await client
                .from("calendar_categories")
                .select("id,name,system_key,is_system")
                .eq("home_id", value: homeId.uuidString)
                .eq("system_key", value: "chore")
                .eq("is_system", value: true)
                .limit(2)
                .execute()
                .value

            if let category = rows.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("Chore") == .orderedSame
            }) {
                return category.id
            }

            // Match the iPad recovery path without adding a new backend API.
            let userId = try await client.auth.session.user.id
            do {
                try await client.from("calendar_categories").insert(
                    CreateChoreCategoryPayload(homeId: homeId, createdBy: userId)
                ).execute()
            } catch {
                // A concurrent client may have created it; the authoritative
                // follow-up query below decides whether recovery succeeded.
                log(error, operation: "calendar_categories.insert_chore", identifier: homeId)
            }

            let repaired: [CalendarCategoryRow] = try await client
                .from("calendar_categories")
                .select("id,name,system_key,is_system")
                .eq("home_id", value: homeId.uuidString)
                .eq("system_key", value: "chore")
                .eq("is_system", value: true)
                .limit(2)
                .execute().value
            guard let category = repaired.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("Chore") == .orderedSame
            }) else { throw ChoreCalendarInfrastructureError.choreCategoryUnavailable }
            return category.id
        } catch let error as ChoreCalendarInfrastructureError {
            throw error
        } catch {
            log(error, operation: "calendar_categories.resolve_chore", identifier: homeId)
            throw ChoreCalendarInfrastructureError.choreCategoryUnavailable
        }
    }

    private func requireAuthenticatedSession() async throws {
        do {
            _ = try await client.auth.session
        } catch {
            throw ChoreCalendarInfrastructureError.authenticationRequired
        }
    }

    private func log(_ error: Error, operation: String, identifier: UUID) {
        #if DEBUG
        print("[ChoreCalendar] operation=\(operation) id=\(identifier.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

@MainActor
final class ChoreCalendarRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseManager.shared.client
    }

    func replaceFutureOccurrences(
        templateId: UUID,
        effectiveFrom: Date,
        generateThrough: Date,
        timezone: String
    ) async throws -> ChoreOccurrenceReplacementResult {
        guard generateThrough >= effectiveFrom else {
            throw ChoreCalendarInfrastructureError.invalidDateRange
        }
        do {
            try await requireAuthenticatedSession()
            let rows: [ReplacedChoreOccurrenceRow] = try await client.rpc(
                "replace_future_chore_occurrences",
                params: ReplaceFutureOccurrencesParameters(
                    templateId: templateId,
                    effectiveFrom: effectiveFrom,
                    generateThrough: generateThrough,
                    timezone: timezone
                )
            ).execute().value
            return ChoreOccurrenceReplacementResult(
                removedOccurrenceIds: rows.map(\.occurrenceId),
                calendarEventIds: rows.compactMap(\.calendarEventId)
            )
        } catch let error as ChoreCalendarInfrastructureError {
            throw error
        } catch {
            log(error, operation: "replace_future_chore_occurrences", identifier: templateId)
            throw ChoreCalendarInfrastructureError.repositoryOperationFailed
        }
    }

    func generateOccurrences(templateId: UUID, through: Date, timezone: String) async throws -> [ChoreCalendarOccurrence] {
        do {
            try await requireAuthenticatedSession()
            let ids: [UUID] = try await client.rpc(
                "generate_chore_occurrences",
                params: GenerateOccurrencesParameters(templateId: templateId, through: through, timezone: timezone)
            ).execute().value
            return try await fetchOccurrences(ids: ids)
        } catch let error as ChoreCalendarInfrastructureError {
            throw error
        } catch {
            log(error, operation: "generate_chore_occurrences", identifier: templateId)
            throw ChoreCalendarInfrastructureError.repositoryOperationFailed
        }
    }

    func fetchOccurrences(ids: [UUID]) async throws -> [ChoreCalendarOccurrence] {
        guard !ids.isEmpty else { return [] }
        do {
            try await requireAuthenticatedSession()
            return try await client.from("chore_occurrences")
                .select("id,home_id,title_snapshot,category_id_snapshot,due_at,end_at,is_all_day,calendar_event_id")
                .in("id", values: Array(Set(ids)).map(\.uuidString))
                .order("due_at", ascending: true)
                .execute().value
        } catch {
            log(error, operation: "chore_occurrences.select_ids", identifier: ids[0])
            throw ChoreCalendarInfrastructureError.repositoryOperationFailed
        }
    }

    func fetchOccurrence(id: UUID) async throws -> ChoreCalendarOccurrence? {
        try await fetchOccurrences(ids: [id]).first
    }

    func linkCalendarEvent(occurrenceId: UUID, calendarEventId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client.from("chore_occurrences")
                .update(LinkCalendarEventPayload(calendarEventId: calendarEventId))
                .eq("id", value: occurrenceId.uuidString)
                .execute()
        } catch {
            log(error, operation: "chore_occurrences.link_calendar_event", identifier: occurrenceId)
            throw ChoreCalendarInfrastructureError.repositoryOperationFailed
        }
    }

    func refreshFutureOccurrenceAssignees(templateId: UUID, effectiveFrom: Date) async throws -> ChoreAssignmentRefreshResult {
        do {
            try await requireAuthenticatedSession()
            let rows: [AssignmentRefreshRow] = try await client.rpc(
                "refresh_future_chore_occurrence_assignees",
                params: RefreshAssigneesParameters(templateId: templateId, effectiveFrom: effectiveFrom)
            ).execute().value
            guard let row = rows.first else {
                return ChoreAssignmentRefreshResult(futureOccurrencesUpdated: 0, newAssigneeCount: 0)
            }
            return ChoreAssignmentRefreshResult(
                futureOccurrencesUpdated: row.futureOccurrencesUpdated,
                newAssigneeCount: row.newAssigneeCount
            )
        } catch {
            log(error, operation: "refresh_future_chore_occurrence_assignees", identifier: templateId)
            throw ChoreCalendarInfrastructureError.repositoryOperationFailed
        }
    }

    private func requireAuthenticatedSession() async throws {
        do { _ = try await client.auth.session }
        catch { throw ChoreCalendarInfrastructureError.authenticationRequired }
    }

    private func log(_ error: Error, operation: String, identifier: UUID) {
        #if DEBUG
        print("[ChoreCalendarRepository] operation=\(operation) id=\(identifier.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

private struct CalendarCategoryRow: Decodable {
    let id: UUID
    let name: String
}

private struct CreateChoreCategoryPayload: Encodable {
    let homeId: UUID
    let name = "Chore"
    let colorHex = "90BE6D"
    let iconName = "checklist"
    let sortOrder = 6
    let systemKey = "chore"
    let isSystem = true
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case systemKey = "system_key"
        case isSystem = "is_system"
        case createdBy = "created_by"
    }
}

private struct CreateCalendarEventParameters: Encodable {
    let homeId: UUID
    let title: String
    let startsAt: String
    let endsAt: String
    let isAllDay: Bool
    let timezone: String
    let categoryId: UUID
    let assignedUserIds: [UUID] = []
    let recurrenceInterval = 1

    init(homeId: UUID, title: String, startsAt: Date, endsAt: Date, isAllDay: Bool, timezone: String, categoryId: UUID) {
        self.homeId = homeId
        self.title = title
        self.startsAt = ChoreCalendarDateFormatting.timestamp(startsAt)
        self.endsAt = ChoreCalendarDateFormatting.timestamp(endsAt)
        self.isAllDay = isAllDay
        self.timezone = timezone
        self.categoryId = categoryId
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "target_home_id"
        case title = "event_title"
        case startsAt = "event_starts_at"
        case endsAt = "event_ends_at"
        case isAllDay = "event_is_all_day"
        case timezone = "event_timezone"
        case categoryId = "event_category_id"
        case assignedUserIds = "assigned_user_ids"
        case recurrenceInterval = "event_recurrence_interval"
    }
}

private struct CalendarEventIdParameters: Encodable {
    let eventId: UUID
    enum CodingKeys: String, CodingKey { case eventId = "target_event_id" }
}

private struct ReplaceFutureOccurrencesParameters: Encodable {
    let templateId: UUID
    let effectiveFrom: String
    let generateThrough: String

    init(templateId: UUID, effectiveFrom: Date, generateThrough: Date, timezone: String) {
        self.templateId = templateId
        self.effectiveFrom = ChoreCalendarDateFormatting.timestamp(effectiveFrom)
        self.generateThrough = ChoreCalendarDateFormatting.date(generateThrough, timezone: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case templateId = "requested_template_id"
        case effectiveFrom = "effective_from"
        case generateThrough = "generate_through"
    }
}

private struct ReplacedChoreOccurrenceRow: Decodable {
    let occurrenceId: UUID
    let calendarEventId: UUID?
    enum CodingKeys: String, CodingKey {
        case occurrenceId = "occurrence_id"
        case calendarEventId = "calendar_event_id"
    }
}

private struct GenerateOccurrencesParameters: Encodable {
    let templateId: UUID
    let generateThrough: String
    init(templateId: UUID, through: Date, timezone: String) {
        self.templateId = templateId
        generateThrough = ChoreCalendarDateFormatting.date(through, timezone: timezone)
    }
    enum CodingKeys: String, CodingKey {
        case templateId = "requested_template_id"
        case generateThrough = "generate_through"
    }
}

private struct LinkCalendarEventPayload: Encodable {
    let calendarEventId: UUID
    enum CodingKeys: String, CodingKey { case calendarEventId = "calendar_event_id" }
}

private struct RefreshAssigneesParameters: Encodable {
    let templateId: UUID
    let effectiveFrom: String
    init(templateId: UUID, effectiveFrom: Date) {
        self.templateId = templateId
        self.effectiveFrom = ChoreCalendarDateFormatting.timestamp(effectiveFrom)
    }
    enum CodingKeys: String, CodingKey {
        case templateId = "requested_template_id"
        case effectiveFrom = "effective_from"
    }
}

private struct AssignmentRefreshRow: Decodable {
    let futureOccurrencesUpdated: Int
    let newAssigneeCount: Int
    enum CodingKeys: String, CodingKey {
        case futureOccurrencesUpdated = "future_occurrences_updated"
        case newAssigneeCount = "new_assignee_count"
    }
}

enum ChoreCalendarDateFormatting {
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(_ date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
