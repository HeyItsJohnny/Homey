import Foundation

@MainActor
final class ChoreCalendarSyncService {
    private let choresRepository: ChoresRepository
    private let calendarService: CalendarService

    init(
        choresRepository: ChoresRepository,
        calendarService: CalendarService? = nil
    ) {
        self.choresRepository = choresRepository
        self.calendarService = calendarService ?? CalendarService()
    }

    func syncMissingCalendarEvents(homeId: UUID, occurrences: [ChoreOccurrence]) async throws -> [ChoreOccurrence] {
        let unsyncedOccurrences = occurrences.filter { $0.calendarEventId == nil }
        guard !unsyncedOccurrences.isEmpty else {
            return occurrences
        }

        let choreCategory = try await calendarService.resolveChoreCategory(homeId: homeId)
        var syncedOccurrencesById: [UUID: ChoreOccurrence] = [:]

        for occurrence in unsyncedOccurrences {
            let createdEventId: UUID
            do {
                createdEventId = try await calendarService.createEvent(
                    homeId: homeId,
                    title: occurrence.titleSnapshot,
                    notes: nil,
                    location: nil,
                    startsAt: occurrence.dueAt,
                    endsAt: occurrence.endAt,
                    isAllDay: occurrence.isAllDay,
                    timezone: occurrence.timezone,
                    categoryId: occurrence.categoryIdSnapshot ?? choreCategory.id,
                    assignedUserIds: [],
                    recurrence: CalendarRecurrenceInput()
                )
            } catch {
                logChoreCalendarSyncError(error, operation: "create_calendar_event", occurrenceId: occurrence.id)
                throw ChoreRepositoryError.calendarSynchronizationFailed
            }

            do {
                try await choresRepository.linkCalendarEvent(occurrenceId: occurrence.id, calendarEventId: createdEventId)
                if let refreshedOccurrence = try await choresRepository.fetchOccurrence(id: occurrence.id) {
                    syncedOccurrencesById[occurrence.id] = refreshedOccurrence
                }
            } catch {
                logChoreCalendarSyncError(error, operation: "link_calendar_event", occurrenceId: occurrence.id)
                do {
                    try await calendarService.deleteEvent(eventId: createdEventId)
                } catch {
                    logChoreCalendarSyncError(error, operation: "delete_orphan_calendar_event", occurrenceId: occurrence.id)
                }
                throw ChoreRepositoryError.calendarSynchronizationFailed
            }
        }

        return occurrences.map { occurrence in
            syncedOccurrencesById[occurrence.id] ?? occurrence
        }
    }

    func rescheduleOccurrence(
        occurrenceId: UUID,
        dueAt: Date,
        endAt: Date,
        dueLocalDate: Date,
        dueTime: ChoreLocalTime?,
        isAllDay: Bool,
        timezone: String
    ) async throws -> ChoreOccurrence {
        guard endAt >= dueAt else {
            throw ChoreRepositoryError.invalidDateRange
        }

        guard let originalOccurrence = try await choresRepository.fetchOccurrence(id: occurrenceId) else {
            throw ChoreRepositoryError.notFound
        }

        do {
            try await choresRepository.updateOccurrenceSchedule(
                occurrenceId: occurrenceId,
                dueAt: dueAt,
                endAt: endAt,
                dueLocalDate: dueLocalDate,
                dueTime: dueTime,
                isAllDay: isAllDay,
                timezone: timezone
            )
        } catch {
            throw error
        }

        guard let calendarEventId = originalOccurrence.calendarEventId else {
            guard let updatedOccurrence = try await choresRepository.fetchOccurrence(id: occurrenceId) else {
                throw ChoreRepositoryError.notFound
            }
            return updatedOccurrence
        }

        do {
            try await calendarService.updateEvent(
                eventId: calendarEventId,
                title: originalOccurrence.titleSnapshot,
                notes: nil,
                location: nil,
                startsAt: dueAt,
                endsAt: endAt,
                isAllDay: isAllDay,
                timezone: timezone,
                categoryId: originalOccurrence.categoryIdSnapshot,
                assignedUserIds: [],
                recurrence: CalendarRecurrenceInput()
            )
        } catch {
            logChoreCalendarSyncError(error, operation: "update_linked_calendar_event", occurrenceId: occurrenceId)
            do {
                try await choresRepository.updateOccurrenceSchedule(
                    occurrenceId: occurrenceId,
                    dueAt: originalOccurrence.dueAt,
                    endAt: originalOccurrence.endAt,
                    dueLocalDate: originalOccurrence.dueLocalDate,
                    dueTime: originalOccurrence.dueTime,
                    isAllDay: originalOccurrence.isAllDay,
                    timezone: originalOccurrence.timezone
                )
            } catch {
                logChoreCalendarSyncError(error, operation: "rollback_occurrence_schedule", occurrenceId: occurrenceId)
            }
            throw ChoreRepositoryError.calendarSynchronizationFailed
        }

        guard let updatedOccurrence = try await choresRepository.fetchOccurrence(id: occurrenceId) else {
            throw ChoreRepositoryError.notFound
        }
        return updatedOccurrence
    }

    private func logChoreCalendarSyncError(_ error: Error, operation: String, occurrenceId: UUID) {
        #if DEBUG
        print("========== CHORE CALENDAR SYNC FAILED ==========")
        print("operation: \(operation)")
        print("occurrence_id: \(occurrenceId.uuidString)")
        print(String(reflecting: error))
        print("================================================")
        #endif
    }
}
