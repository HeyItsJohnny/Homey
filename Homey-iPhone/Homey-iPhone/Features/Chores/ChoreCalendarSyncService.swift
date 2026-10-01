import Foundation

enum ChoreRecurringEditStage: String, Sendable {
    case replaceOccurrences
    case generateOccurrences
}

enum ChoreRecurringEditProgress: Sendable {
    case savingTemplate
    case replacingOccurrences
    case refreshing
}

struct ChoreRecurringEditPartialFailure: LocalizedError, Sendable {
    let templateID: UUID
    let stage: ChoreRecurringEditStage
    let underlyingDescription: String

    var errorDescription: String? {
        switch stage {
        case .replaceOccurrences:
            "The chore was saved, but Homey could not confirm that future chores were updated. Your changes may already be present. Close this editor and try again later."
        case .generateOccurrences:
            "The chore was saved, but future chores could not be generated. Tap Save to safely retry."
        }
    }
}

struct ChoreRecurringEditResult: Sendable {
    let templateID: UUID
    let replacement: ChoreOccurrenceReplacementResult
    let generatedOccurrenceIDs: [UUID]
}

@MainActor
final class ChoreRecurringEditCoordinator {
    private let repository: ChoreScheduleRepository

    init(repository: ChoreScheduleRepository? = nil) {
        self.repository = repository ?? ChoreScheduleRepository()
    }

    func replaceRecurringSchedule(
        effectiveFrom: Date,
        generateThrough: Date,
        timezone: String,
        progress: @escaping (ChoreRecurringEditProgress) -> Void = { _ in },
        saveTemplate: () async throws -> UUID
    ) async throws -> ChoreRecurringEditResult {
        progress(.savingTemplate)
        let templateID = try await saveTemplate()

        let replacement: ChoreOccurrenceReplacementResult
        do {
            progress(.replacingOccurrences)
            replacement = try await repository.replaceFutureOccurrences(
                templateID: templateID,
                effectiveFrom: effectiveFrom,
                generateThrough: generateThrough,
                timezone: timezone
            )
        } catch {
            throw partialFailure(templateID, .replaceOccurrences, error)
        }

        let generatedOccurrenceIDs: [UUID]
        do {
            generatedOccurrenceIDs = try await repository.generateOccurrences(
                templateID: templateID,
                through: generateThrough,
                timezone: timezone
            )
        } catch {
            throw partialFailure(templateID, .generateOccurrences, error)
        }

        progress(.refreshing)
        return ChoreRecurringEditResult(
            templateID: templateID,
            replacement: replacement,
            generatedOccurrenceIDs: generatedOccurrenceIDs
        )
    }

    func refreshAssignmentsOnly(templateID: UUID, effectiveFrom: Date) async throws -> ChoreAssignmentRefreshResult {
        try await repository.refreshFutureOccurrenceAssignees(
            templateID: templateID,
            effectiveFrom: effectiveFrom
        )
    }

    func resumeRecurringSchedule(
        generateThrough: Date,
        timezone: String,
        failure: ChoreRecurringEditPartialFailure,
        progress: @escaping (ChoreRecurringEditProgress) -> Void = { _ in }
    ) async throws {
        guard failure.stage == .generateOccurrences else { throw failure }
        do {
            progress(.replacingOccurrences)
            _ = try await repository.generateOccurrences(
                templateID: failure.templateID,
                through: generateThrough,
                timezone: timezone
            )
        } catch {
            throw partialFailure(failure.templateID, .generateOccurrences, error)
        }
        progress(.refreshing)
    }

    private func partialFailure(
        _ templateID: UUID,
        _ stage: ChoreRecurringEditStage,
        _ error: Error
    ) -> ChoreRecurringEditPartialFailure {
        ChoreRecurringEditPartialFailure(
            templateID: templateID,
            stage: stage,
            underlyingDescription: String(reflecting: error)
        )
    }
}
