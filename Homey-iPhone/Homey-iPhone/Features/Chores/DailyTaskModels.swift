import Foundation

struct PhoneDailyTaskMember: Decodable, Identifiable, Hashable {
    let membershipID: UUID
    let userID: UUID
    let firstName: String?
    let lastName: String?
    let profileDisplayName: String?
    let email: String?

    var id: UUID { userID }
    var displayName: String {
        let preferred = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }
        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return email?.split(separator: "@").first.map(String.init) ?? "Home Member"
    }

    enum CodingKeys: String, CodingKey {
        case membershipID = "membership_id"
        case userID = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case profileDisplayName = "display_name"
        case email
    }
}

struct PhoneDailyTaskRow: Decodable, Hashable {
    let taskID: UUID
    let name: String
    let points: Int
    let assignedUserIDs: [UUID]
    let userID: UUID
    let userDisplayName: String
    let completionID: UUID?
    let completedAt: Date?
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case name = "task_name"
        case points
        case assignedUserIDs = "assigned_user_ids"
        case userID = "user_id"
        case userDisplayName = "user_display_name"
        case completionID = "completion_id"
        case completedAt = "completed_at"
        case isCompleted = "is_completed"
    }
}

struct PhoneDailyTaskAssignment: Identifiable, Hashable {
    let userID: UUID
    let completionID: UUID?
    let completedAt: Date?
    let isCompleted: Bool

    var id: UUID { userID }
}

struct PhoneDailyTask: Identifiable, Hashable {
    let id: UUID
    let name: String
    let points: Int
    let assignments: [PhoneDailyTaskAssignment]

    var completedCount: Int { assignments.filter(\.isCompleted).count }
    var assigneeIDs: Set<UUID> { Set(assignments.map(\.userID)) }

    init?(rows: [PhoneDailyTaskRow]) {
        guard let first = rows.first else { return nil }
        id = first.taskID
        name = first.name
        points = first.points

        var latestByUserID: [UUID: PhoneDailyTaskRow] = [:]
        for row in rows {
            if let existing = latestByUserID[row.userID] {
                let existingDate = existing.completedAt ?? .distantPast
                let nextDate = row.completedAt ?? .distantPast
                if nextDate >= existingDate { latestByUserID[row.userID] = row }
            } else {
                latestByUserID[row.userID] = row
            }
        }
        assignments = latestByUserID.values.map {
            PhoneDailyTaskAssignment(
                userID: $0.userID,
                completionID: $0.completionID,
                completedAt: $0.completedAt,
                isCompleted: $0.isCompleted
            )
        }
    }
}

enum PhoneDailyTaskLocalDate {
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
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
