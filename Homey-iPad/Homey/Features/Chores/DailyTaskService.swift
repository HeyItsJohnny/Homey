import Foundation
import PostgREST
import Supabase

struct DailyTaskService {
    private let client = SupabaseManager.shared.client

    func fetchTasks(homeID: UUID, date: String) async throws -> [DailyTaskRow] {
        do {
            return try await client.rpc(
                "get_daily_tasks",
                params: GetDailyTasksParameters(homeID: homeID, date: date)
            ).execute().value
        } catch {
            if isCancellation(error) { throw CancellationError() }
            throw DailyTaskError.loadFailed
        }
    }

    func complete(homeID: UUID, taskID: UUID, userID: UUID, date: String) async throws {
        do {
            try await client.rpc(
                "complete_daily_task",
                params: CompleteDailyTaskParameters(homeID: homeID, taskID: taskID, userID: userID, date: date)
            ).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            throw DailyTaskError.updateFailed
        }
    }

    func undo(homeID: UUID, taskID: UUID, completionID: UUID, selectedDate: String) async throws {
        #if DEBUG
        print("[Homey] TASK UNCHECK REQUEST")
        print("home_id: \(homeID.uuidString)")
        print("task_id: \(taskID.uuidString)")
        print("completion_id: \(completionID.uuidString)")
        print("selected_date: \(selectedDate)")
        #endif

        do {
            try await client.rpc(
                "undo_daily_task_completion",
                params: UndoDailyTaskParameters(homeID: homeID, completionID: completionID)
            ).execute()
        } catch {
            if isCancellation(error) { throw CancellationError() }
            #if DEBUG
            print("[Homey] TASK UNCHECK ERROR")
            if let postgrestError = error as? PostgrestError {
                print("code: \(postgrestError.code ?? "nil")")
                print("message: \(postgrestError.message)")
                print("detail: \(postgrestError.detail ?? "nil")")
                print("hint: \(postgrestError.hint ?? "nil")")
            }
            print("raw error: \(String(reflecting: error))")
            #endif
            throw DailyTaskError.updateFailed
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }
}

enum DailyTaskError: LocalizedError {
    case loadFailed
    case updateFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "We couldn't load today's daily tasks."
        case .updateFailed:
            return "We couldn't update that task. Please try again."
        }
    }
}

private struct GetDailyTasksParameters: Encodable {
    let homeID: UUID
    let date: String

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case date = "requested_date"
    }
}

private struct CompleteDailyTaskParameters: Encodable {
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

private struct UndoDailyTaskParameters: Encodable {
    let homeID: UUID
    let completionID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case completionID = "requested_completion_id"
    }
}
