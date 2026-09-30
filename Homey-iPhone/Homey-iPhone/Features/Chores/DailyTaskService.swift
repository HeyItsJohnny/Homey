import Foundation
import Supabase

struct PhoneDailyTaskService {
    private let client = SupabaseManager.shared.client

    func fetchTasks(homeID: UUID, date: String) async throws -> [PhoneDailyTaskRow] {
        do {
            return try await client.rpc(
                "get_daily_tasks",
                params: PhoneGetDailyTasksParameters(homeID: homeID, date: date)
            ).execute().value
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "get_daily_tasks", homeID: homeID)
            throw PhoneDailyTaskError.loadFailed
        }
    }

    func fetchMembers(homeID: UUID) async throws -> [PhoneDailyTaskMember] {
        do {
            return try await client.rpc(
                "get_home_members",
                params: PhoneDailyTaskHomeParameters(homeID: homeID)
            ).execute().value
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "get_home_members", homeID: homeID)
            throw PhoneDailyTaskError.membersFailed
        }
    }

    func save(homeID: UUID, taskID: UUID?, name: String, points: Int, assigneeIDs: [UUID]) async throws {
        do {
            try await client.rpc(
                "save_daily_task",
                params: PhoneSaveDailyTaskParameters(
                    homeID: homeID,
                    taskID: taskID,
                    name: name,
                    points: points,
                    assigneeIDs: assigneeIDs
                )
            ).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "save_daily_task", homeID: homeID)
            throw PhoneDailyTaskError.saveFailed
        }
    }

    func retire(homeID: UUID, taskID: UUID) async throws {
        do {
            try await client.rpc(
                "retire_daily_task",
                params: PhoneRetireDailyTaskParameters(homeID: homeID, taskID: taskID)
            ).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "retire_daily_task", homeID: homeID)
            throw PhoneDailyTaskError.deleteFailed
        }
    }

    func complete(homeID: UUID, taskID: UUID, userID: UUID, date: String) async throws {
        do {
            try await client.rpc(
                "complete_daily_task",
                params: PhoneCompleteDailyTaskParameters(homeID: homeID, taskID: taskID, userID: userID, date: date)
            ).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "complete_daily_task", homeID: homeID)
            throw error
        }
    }

    func undo(homeID: UUID, completionID: UUID) async throws {
        do {
            try await client.rpc(
                "undo_daily_task_completion",
                params: PhoneUndoDailyTaskParameters(homeID: homeID, completionID: completionID)
            ).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            log(error, operation: "undo_daily_task_completion", homeID: homeID)
            throw error
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { return isCancellation(underlying) }
        return false
    }

    private func log(_ error: Error, operation: String, homeID: UUID) {
        #if DEBUG
        print("[Homey] DAILY TASKS ERROR operation=\(operation) home=\(homeID.uuidString): \(String(reflecting: error))")
        #endif
    }
}

enum PhoneDailyTaskError: LocalizedError {
    case loadFailed
    case membersFailed
    case invalidName
    case invalidPoints
    case assigneeRequired
    case saveFailed
    case deleteFailed
    case updateFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: "We couldn't load today's tasks."
        case .membersFailed: "We couldn't load the members for this Home."
        case .invalidName: "Enter a task name."
        case .invalidPoints: "Points must be a whole number of zero or greater."
        case .assigneeRequired: "Assign this task to at least one member."
        case .saveFailed: "We couldn't save this task."
        case .deleteFailed: "We couldn't delete this task."
        case .updateFailed: "We couldn't update this task. Please try again."
        }
    }
}

private struct PhoneGetDailyTasksParameters: Encodable {
    let homeID: UUID
    let date: String
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case date = "requested_date"
    }
}

private struct PhoneDailyTaskHomeParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "target_home_id" }
}

private struct PhoneSaveDailyTaskParameters: Encodable {
    let homeID: UUID
    let taskID: UUID?
    let name: String
    let points: Int
    let assigneeIDs: [UUID]
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case taskID = "requested_task_id"
        case name = "requested_name"
        case points = "requested_points"
        case assigneeIDs = "requested_assignee_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        if let taskID {
            try container.encode(taskID, forKey: .taskID)
        } else {
            // The deployed RPC requires the named argument even when creating.
            try container.encodeNil(forKey: .taskID)
        }
        try container.encode(name, forKey: .name)
        try container.encode(points, forKey: .points)
        try container.encode(assigneeIDs, forKey: .assigneeIDs)
    }
}

private struct PhoneRetireDailyTaskParameters: Encodable {
    let homeID: UUID
    let taskID: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case taskID = "requested_task_id"
    }
}

private struct PhoneCompleteDailyTaskParameters: Encodable {
    let homeID: UUID
    let taskID: UUID
    let userID: UUID
    let date: String
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case taskID = "requested_task_id"
        case userID = "requested_user_id"
        case date = "requested_date"
    }
}

private struct PhoneUndoDailyTaskParameters: Encodable {
    let homeID: UUID
    let completionID: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case completionID = "requested_completion_id"
    }
}
