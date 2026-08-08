import Foundation

enum ChoreAssignmentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case assigned
    case open

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .assigned:
            return "Assigned"
        case .open:
            return "Open"
        }
    }
}

enum ChoreCompletionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case anyAssignee = "any_assignee"
    case everyone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .single:
            return "Single"
        case .anyAssignee:
            return "Any Assignee"
        case .everyone:
            return "Everyone"
        }
    }
}

enum ChoreFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "One Time"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }
}

enum ChoreRecurrenceEndType: String, Codable, CaseIterable, Identifiable, Sendable {
    case never
    case onDate = "on_date"
    case afterCount = "after_count"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never:
            return "Never"
        case .onDate:
            return "On Date"
        case .afterCount:
            return "After Count"
        }
    }
}

enum ChoreOccurrenceStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case awaitingApproval = "awaiting_approval"
    case completed
    case needsRedo = "needs_redo"
    case skipped
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .inProgress:
            return "In Progress"
        case .awaitingApproval:
            return "Pending Approval"
        case .completed:
            return "Approved"
        case .needsRedo:
            return "Needs Redo"
        case .skipped:
            return "Skipped"
        case .cancelled:
            return "Cancelled"
        }
    }

    var isTerminalForOverdue: Bool {
        switch self {
        case .completed, .skipped, .cancelled:
            return true
        case .notStarted, .inProgress, .awaitingApproval, .needsRedo:
            return false
        }
    }
}

enum ChoreAssigneeStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case assigned
    case inProgress = "in_progress"
    case awaitingApproval = "awaiting_approval"
    case completed
    case needsRedo = "needs_redo"
    case skipped
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .assigned:
            return "Assigned"
        case .inProgress:
            return "In Progress"
        case .awaitingApproval:
            return "Pending Approval"
        case .completed:
            return "Approved"
        case .needsRedo:
            return "Needs Redo"
        case .skipped:
            return "Skipped"
        case .cancelled:
            return "Cancelled"
        }
    }
}

enum ChoreSubmissionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case approved
    case needsRedo = "needs_redo"
    case withdrawn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .approved:
            return "Approved"
        case .needsRedo:
            return "Needs Redo"
        case .withdrawn:
            return "Withdrawn"
        }
    }
}

enum ChoreApprovalDecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case approved
    case needsRedo = "needs_redo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .approved:
            return "Approved"
        case .needsRedo:
            return "Needs Redo"
        }
    }
}

enum ChorePointTransactionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case choreEarned = "chore_earned"
    case adminAdjustment = "admin_adjustment"
    case rewardRedemption = "reward_redemption"
    case rewardRefund = "reward_refund"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .choreEarned:
            return "Chore Earned"
        case .adminAdjustment:
            return "Admin Adjustment"
        case .rewardRedemption:
            return "Reward Redemption"
        case .rewardRefund:
            return "Reward Refund"
        }
    }
}

enum ChoreHistoryActivityType: String, Codable, CaseIterable, Identifiable, Sendable {
    case choreAssigned = "chore_assigned"
    case choreStarted = "chore_started"
    case choreSubmitted = "chore_submitted"
    case choreApproved = "chore_approved"
    case choreNeedsRedo = "chore_needs_redo"
    case choreCompleted = "chore_completed"
    case choreClaimed = "chore_claimed"
    case choreSkipped = "chore_skipped"
    case choreCancelled = "chore_cancelled"
    case pointsEarned = "points_earned"
    case pointsAdjustment = "points_adjustment"
    case rewardRedeemed = "reward_redeemed"
    case rewardRefunded = "reward_refunded"
    case rewardFulfilled = "reward_fulfilled"

    var id: String { rawValue }
}

enum ChoreOccurrenceDisplayStatus: Equatable, Sendable {
    case stored(ChoreOccurrenceStatus)
    case overdue

    var displayName: String {
        switch self {
        case .stored(let status):
            return status.displayName
        case .overdue:
            return "Overdue"
        }
    }
}
