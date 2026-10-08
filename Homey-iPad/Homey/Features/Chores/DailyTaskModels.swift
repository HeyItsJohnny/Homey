import Foundation

struct DailyTaskRow: Decodable, Hashable {
    let taskID: UUID
    let name: String
    let points: Int
    let userID: UUID
    let completionID: UUID?
    let completedAt: Date?
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case name = "task_name"
        case points
        case userID = "user_id"
        case completionID = "completion_id"
        case completedAt = "completed_at"
        case isCompleted = "is_completed"
    }
}

struct MemberDailyTask: Identifiable, Hashable {
    let taskID: UUID
    let userID: UUID
    let name: String
    let points: Int
    let completionID: UUID?
    let completedAt: Date?
    let isCompleted: Bool

    var id: String { "\(taskID.uuidString):\(userID.uuidString)" }

    init(row: DailyTaskRow) {
        taskID = row.taskID
        userID = row.userID
        name = row.name
        points = row.points
        completionID = row.completionID
        completedAt = row.completedAt
        isCompleted = row.isCompleted
    }
}

enum DailyTaskLocalDate {
    static func string(for date: Date = Date(), timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func displayString(for date: Date = Date(), timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezone
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter.string(from: date)
    }
}
