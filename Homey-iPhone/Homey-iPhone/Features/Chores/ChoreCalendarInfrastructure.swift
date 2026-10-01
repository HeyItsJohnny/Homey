import Foundation
import Supabase

struct ChoreOccurrenceReplacementResult: Sendable {
    let removedOccurrenceIDs: [UUID]
}

struct ChoreAssignmentRefreshResult: Sendable {
    let futureOccurrencesUpdated: Int
    let newAssigneeCount: Int
}

enum ChoreScheduleInfrastructureError: LocalizedError {
    case authenticationRequired
    case invalidDateRange
    case repositoryOperationFailed

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "Your session has expired. Please sign in again."
        case .invalidDateRange: "Choose a valid date range."
        case .repositoryOperationFailed: "We could not update this chore."
        }
    }
}

@MainActor
final class ChoreScheduleRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseManager.shared.client
    }

    func replaceFutureOccurrences(
        templateID: UUID,
        effectiveFrom: Date,
        generateThrough: Date,
        timezone: String
    ) async throws -> ChoreOccurrenceReplacementResult {
        guard generateThrough >= effectiveFrom else {
            throw ChoreScheduleInfrastructureError.invalidDateRange
        }
        do {
            try await requireAuthenticatedSession()
            let rows: [ReplacedChoreOccurrenceRow] = try await client.rpc(
                "replace_future_chore_occurrences",
                params: ReplaceFutureOccurrencesParameters(
                    templateID: templateID,
                    effectiveFrom: effectiveFrom,
                    generateThrough: generateThrough,
                    timezone: timezone
                )
            ).execute().value
            return ChoreOccurrenceReplacementResult(removedOccurrenceIDs: rows.map(\.occurrenceID))
        } catch let error as ChoreScheduleInfrastructureError {
            throw error
        } catch {
            log(error, operation: "replace_future_chore_occurrences", identifier: templateID)
            throw ChoreScheduleInfrastructureError.repositoryOperationFailed
        }
    }

    func generateOccurrences(templateID: UUID, through: Date, timezone: String) async throws -> [UUID] {
        do {
            try await requireAuthenticatedSession()
            return try await client.rpc(
                "generate_chore_occurrences",
                params: GenerateOccurrencesParameters(templateID: templateID, through: through, timezone: timezone)
            ).execute().value
        } catch let error as ChoreScheduleInfrastructureError {
            throw error
        } catch {
            log(error, operation: "generate_chore_occurrences", identifier: templateID)
            throw ChoreScheduleInfrastructureError.repositoryOperationFailed
        }
    }

    func refreshFutureOccurrenceAssignees(templateID: UUID, effectiveFrom: Date) async throws -> ChoreAssignmentRefreshResult {
        do {
            try await requireAuthenticatedSession()
            let rows: [AssignmentRefreshRow] = try await client.rpc(
                "refresh_future_chore_occurrence_assignees",
                params: RefreshAssigneesParameters(templateID: templateID, effectiveFrom: effectiveFrom)
            ).execute().value
            guard let row = rows.first else {
                return ChoreAssignmentRefreshResult(futureOccurrencesUpdated: 0, newAssigneeCount: 0)
            }
            return ChoreAssignmentRefreshResult(
                futureOccurrencesUpdated: row.futureOccurrencesUpdated,
                newAssigneeCount: row.newAssigneeCount
            )
        } catch {
            log(error, operation: "refresh_future_chore_occurrence_assignees", identifier: templateID)
            throw ChoreScheduleInfrastructureError.repositoryOperationFailed
        }
    }

    private func requireAuthenticatedSession() async throws {
        do { _ = try await client.auth.session }
        catch { throw ChoreScheduleInfrastructureError.authenticationRequired }
    }

    private func log(_ error: Error, operation: String, identifier: UUID) {
        #if DEBUG
        print("[ChoreScheduleRepository] operation=\(operation) id=\(identifier.uuidString) error=\(String(reflecting: error))")
        #endif
    }
}

private struct ReplaceFutureOccurrencesParameters: Encodable {
    let templateID: UUID
    let effectiveFrom: String
    let generateThrough: String

    init(templateID: UUID, effectiveFrom: Date, generateThrough: Date, timezone: String) {
        self.templateID = templateID
        self.effectiveFrom = ChoreScheduleDateFormatting.timestamp(effectiveFrom)
        self.generateThrough = ChoreScheduleDateFormatting.date(generateThrough, timezone: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case templateID = "requested_template_id"
        case effectiveFrom = "effective_from"
        case generateThrough = "generate_through"
    }
}

private struct ReplacedChoreOccurrenceRow: Decodable {
    let occurrenceID: UUID
    enum CodingKeys: String, CodingKey { case occurrenceID = "occurrence_id" }
}

private struct GenerateOccurrencesParameters: Encodable {
    let templateID: UUID
    let generateThrough: String

    init(templateID: UUID, through: Date, timezone: String) {
        self.templateID = templateID
        generateThrough = ChoreScheduleDateFormatting.date(through, timezone: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case templateID = "requested_template_id"
        case generateThrough = "generate_through"
    }
}

private struct RefreshAssigneesParameters: Encodable {
    let templateID: UUID
    let effectiveFrom: String

    init(templateID: UUID, effectiveFrom: Date) {
        self.templateID = templateID
        self.effectiveFrom = ChoreScheduleDateFormatting.timestamp(effectiveFrom)
    }

    enum CodingKeys: String, CodingKey {
        case templateID = "requested_template_id"
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

enum ChoreScheduleDateFormatting {
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
