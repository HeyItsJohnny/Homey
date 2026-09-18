import Foundation

@MainActor
final class ChoreCalendarSyncService {
    private let repository: ChoreCalendarRepository
    private let calendarService: ChoreCalendarService

    init(
        repository: ChoreCalendarRepository? = nil,
        calendarService: ChoreCalendarService? = nil
    ) {
        self.repository = repository ?? ChoreCalendarRepository()
        self.calendarService = calendarService ?? ChoreCalendarService()
    }

    /// Only rows without `calendar_event_id` are synchronized. Linking each newly
    /// created event makes subsequent runs idempotent.
    func syncMissingCalendarEvents(
        homeId: UUID,
        occurrences: [ChoreCalendarOccurrence],
        timezone: String
    ) async throws -> [ChoreCalendarOccurrence] {
        let missing = occurrences.filter { $0.calendarEventId == nil }
        guard !missing.isEmpty else { return occurrences }
        guard missing.allSatisfy({ $0.homeId == homeId }) else {
            throw ChoreCalendarInfrastructureError.calendarSynchronizationFailed
        }

        let choreCategoryId = try await calendarService.resolveChoreCategory(homeId: homeId)
        var refreshedById: [UUID: ChoreCalendarOccurrence] = [:]

        for occurrence in missing {
            let eventId = try await calendarService.createEvent(
                homeId: homeId,
                title: occurrence.titleSnapshot,
                startsAt: occurrence.dueAt,
                endsAt: occurrence.endAt,
                isAllDay: occurrence.isAllDay,
                timezone: timezone,
                categoryId: occurrence.categoryIdSnapshot ?? choreCategoryId
            )

            do {
                try await repository.linkCalendarEvent(occurrenceId: occurrence.id, calendarEventId: eventId)
                refreshedById[occurrence.id] = occurrence.linking(calendarEventId: eventId)
            } catch {
                // Match iPad behavior: remove the newly-created orphan if linking fails.
                do { try await calendarService.deleteEvent(eventId: eventId) }
                catch { log(error, operation: "delete_orphan_calendar_event", id: occurrence.id) }
                throw ChoreCalendarInfrastructureError.calendarSynchronizationFailed
            }
        }

        return occurrences.map { refreshedById[$0.id] ?? $0 }
    }

    private func log(_ error: Error, operation: String, id: UUID) {
        #if DEBUG
        print("[ChoreCalendarSync] operation=\(operation) occurrence_id=\(id.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

enum ChoreRecurringEditStage: String, Sendable {
    case replaceOccurrences
    case deleteObsoleteCalendarEvents
    case generateOccurrences
    case synchronizeCalendar
}

enum ChoreRecurringEditProgress: Sendable {
    case savingTemplate
    case replacingOccurrences
    case updatingCalendar
    case refreshing
}

struct ChoreRecurringEditPartialFailure: LocalizedError, Sendable {
    let templateId: UUID
    let stage: ChoreRecurringEditStage
    let remainingCalendarEventIds: [UUID]
    let generatedOccurrenceIds: [UUID]
    let underlyingDescription: String

    var errorDescription: String? {
        switch stage {
        case .replaceOccurrences:
            "The chore was saved, but Homey could not confirm that future chores were updated. Your changes may already be present. Close this editor and try again later."
        case .deleteObsoleteCalendarEvents, .generateOccurrences, .synchronizeCalendar:
            "The chore was saved, but calendar synchronization did not finish. Retry Save to safely resume synchronization."
        }
    }
}

struct ChoreRecurringEditResult: Sendable {
    let templateId: UUID
    let replacement: ChoreOccurrenceReplacementResult
    let synchronizedOccurrences: [ChoreCalendarOccurrence]
}

/// Backend-only orchestration for the established iPad recurring-edit sequence.
/// The future editor supplies its existing `save_chore_template` operation so a
/// successfully saved template ID remains available if a later stage fails.
@MainActor
final class ChoreRecurringEditCoordinator {
    private let repository: ChoreCalendarRepository
    private let calendarService: ChoreCalendarService
    private let syncService: ChoreCalendarSyncService

    init(
        repository: ChoreCalendarRepository? = nil,
        calendarService: ChoreCalendarService? = nil
    ) {
        let resolvedRepository = repository ?? ChoreCalendarRepository()
        let resolvedCalendarService = calendarService ?? ChoreCalendarService()
        self.repository = resolvedRepository
        self.calendarService = resolvedCalendarService
        self.syncService = ChoreCalendarSyncService(
            repository: resolvedRepository,
            calendarService: resolvedCalendarService
        )
    }

    func replaceRecurringSchedule(
        homeId: UUID,
        effectiveFrom: Date,
        generateThrough: Date,
        timezone: String,
        progress: @escaping (ChoreRecurringEditProgress) -> Void = { _ in },
        saveTemplate: () async throws -> UUID
    ) async throws -> ChoreRecurringEditResult {
        progress(.savingTemplate)
        let templateId = try await saveTemplate()

        let replacement: ChoreOccurrenceReplacementResult
        do {
            progress(.replacingOccurrences)
            replacement = try await repository.replaceFutureOccurrences(
                templateId: templateId,
                effectiveFrom: effectiveFrom,
                generateThrough: generateThrough,
                timezone: timezone
            )
        } catch {
            throw partialFailure(templateId, .replaceOccurrences, [], [], error)
        }

        for (index, eventId) in replacement.calendarEventIds.enumerated() {
            do {
                progress(.updatingCalendar)
                try await calendarService.deleteEvent(eventId: eventId)
            } catch {
                throw partialFailure(
                    templateId,
                    .deleteObsoleteCalendarEvents,
                    Array(replacement.calendarEventIds[index...]),
                    [],
                    error
                )
            }
        }

        let generated: [ChoreCalendarOccurrence]
        do {
            progress(.replacingOccurrences)
            generated = try await repository.generateOccurrences(
                templateId: templateId,
                through: generateThrough,
                timezone: timezone
            )
        } catch {
            throw partialFailure(templateId, .generateOccurrences, [], [], error)
        }

        do {
            progress(.updatingCalendar)
            let synchronized = try await syncService.syncMissingCalendarEvents(
                homeId: homeId,
                occurrences: generated,
                timezone: timezone
            )
            NotificationCenter.default.post(
                name: Notification.Name("homeyChoresDidChange"),
                object: nil
            )
            progress(.refreshing)
            NotificationCenter.default.post(
                name: Notification.Name("homeyCalendarEventsDidChange"),
                object: nil
            )
            return ChoreRecurringEditResult(
                templateId: templateId,
                replacement: replacement,
                synchronizedOccurrences: synchronized
            )
        } catch {
            throw partialFailure(templateId, .synchronizeCalendar, [], generated.map(\.id), error)
        }
    }

    func refreshAssignmentsOnly(templateId: UUID, effectiveFrom: Date) async throws -> ChoreAssignmentRefreshResult {
        try await repository.refreshFutureOccurrenceAssignees(
            templateId: templateId,
            effectiveFrom: effectiveFrom
        )
    }

    /// Allows a future editor to retry the exact undeleted IDs retained in a
    /// partial-failure value without replacing occurrences again.
    func retryCalendarEventDeletions(_ eventIds: [UUID]) async throws {
        for eventId in eventIds {
            try await calendarService.deleteEvent(eventId: eventId)
        }
    }

    func resumeRecurringSchedule(
        homeId: UUID,
        generateThrough: Date,
        timezone: String,
        failure: ChoreRecurringEditPartialFailure,
        progress: @escaping (ChoreRecurringEditProgress) -> Void = { _ in }
    ) async throws {
        if failure.stage == .replaceOccurrences { throw failure }

        if failure.stage == .deleteObsoleteCalendarEvents {
            for (index, eventId) in failure.remainingCalendarEventIds.enumerated() {
                do {
                    progress(.updatingCalendar)
                    try await calendarService.deleteEvent(eventId: eventId)
                } catch {
                    throw partialFailure(
                        failure.templateId,
                        .deleteObsoleteCalendarEvents,
                        Array(failure.remainingCalendarEventIds[index...]),
                        [],
                        error
                    )
                }
            }
        }

        let generated: [ChoreCalendarOccurrence]
        if failure.stage == .synchronizeCalendar {
            do {
                generated = try await repository.fetchOccurrences(ids: failure.generatedOccurrenceIds)
            } catch {
                throw partialFailure(
                    failure.templateId,
                    .synchronizeCalendar,
                    [],
                    failure.generatedOccurrenceIds,
                    error
                )
            }
        } else {
            do {
                progress(.replacingOccurrences)
                generated = try await repository.generateOccurrences(
                    templateId: failure.templateId,
                    through: generateThrough,
                    timezone: timezone
                )
            } catch {
                throw partialFailure(failure.templateId, .generateOccurrences, [], [], error)
            }
        }

        do {
            progress(.updatingCalendar)
            _ = try await syncService.syncMissingCalendarEvents(
                homeId: homeId,
                occurrences: generated,
                timezone: timezone
            )
        } catch {
            throw partialFailure(failure.templateId, .synchronizeCalendar, [], generated.map(\.id), error)
        }
        NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
        progress(.refreshing)
    }

    private func partialFailure(
        _ templateId: UUID,
        _ stage: ChoreRecurringEditStage,
        _ remainingIds: [UUID],
        _ generatedOccurrenceIds: [UUID],
        _ error: Error
    ) -> ChoreRecurringEditPartialFailure {
        ChoreRecurringEditPartialFailure(
            templateId: templateId,
            stage: stage,
            remainingCalendarEventIds: remainingIds,
            generatedOccurrenceIds: generatedOccurrenceIds,
            underlyingDescription: String(reflecting: error)
        )
    }
}
