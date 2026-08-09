import Combine
import Foundation

@MainActor
final class ChoresAttentionStore: ObservableObject {
    @Published private(set) var dashboardChoresBadgeCount: Int?
    @Published private(set) var myActionChoreCount: Int?
    @Published private(set) var myPendingRewardCount: Int?
    @Published private(set) var pendingChoreApprovalCount: Int?
    @Published private(set) var pendingRewardRedemptionCount: Int?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?
    private var activeCurrentUserId: UUID?
    private var activeRole: HomeMemberRole?
    private var activeWeekStartsOn: Int?
    private var activeTimezone: String?
    private var loadGeneration = 0

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    var dashboardAttentionCount: Int {
        dashboardChoresBadgeCount ?? 0
    }

    func configure(homeId: UUID?, currentUserId: UUID?, role: HomeMemberRole?, weekStartsOn: Int?, timezone: String?) {
        guard activeHomeId != homeId ||
                activeCurrentUserId != currentUserId ||
                activeRole != role ||
                activeWeekStartsOn != weekStartsOn ||
                activeTimezone != timezone else {
            return
        }

        activeHomeId = homeId
        activeCurrentUserId = currentUserId
        activeRole = role
        activeWeekStartsOn = weekStartsOn
        activeTimezone = timezone
        resetCounts()
        refresh()
    }

    func refresh() {
        guard let activeHomeId, let activeCurrentUserId else {
            resetCounts()
            return
        }

        loadGeneration += 1
        let generation = loadGeneration
        let role = activeRole
        guard let weekRange = ChoreWeekRange.currentWeek(
            weekStartsOn: activeWeekStartsOn,
            timezone: activeTimezone
        ) else {
            resetCounts()
            return
        }

        Task {
            do {
                async let dashboardChoresBadge = repository.fetchCurrentWeekNotStartedChoreBadgeCount(
                    homeId: activeHomeId,
                    weekStart: weekRange.start,
                    nextWeekStart: weekRange.end
                )
                async let myActionChores = repository.fetchMyActionChoreCount(homeId: activeHomeId)
                async let myPendingRewards = repository.fetchMyPendingRewardCount(homeId: activeHomeId)

                let approvalCountTask: Task<Int?, Never> = Task {
                    guard role == .owner || role == .admin else { return nil }
                    return try? await repository.fetchPendingChoreApprovalCount(homeId: activeHomeId)
                }
                let rewardRedemptionCountTask: Task<Int?, Never> = Task {
                    guard role == .owner || role == .admin else { return nil }
                    return try? await repository.fetchPendingRewardRedemptionCount(homeId: activeHomeId)
                }

                let counts = try await ChoresAttentionCounts(
                    dashboardChoresBadge: dashboardChoresBadge,
                    myActionChoreCount: myActionChores,
                    myPendingRewardCount: myPendingRewards,
                    pendingChoreApprovalCount: approvalCountTask.value,
                    pendingRewardRedemptionCount: rewardRedemptionCountTask.value
                )

                guard generation == loadGeneration,
                      activeHomeId == self.activeHomeId,
                      activeCurrentUserId == self.activeCurrentUserId else {
                    return
                }

                dashboardChoresBadgeCount = counts.dashboardChoresBadge.count
                myActionChoreCount = counts.myActionChoreCount
                myPendingRewardCount = counts.myPendingRewardCount
                pendingChoreApprovalCount = counts.pendingChoreApprovalCount
                pendingRewardRedemptionCount = counts.pendingRewardRedemptionCount
                logChoresBadge(
                    homeId: activeHomeId,
                    currentUserId: activeCurrentUserId,
                    weekRange: weekRange,
                    result: counts.dashboardChoresBadge
                )
            } catch {
                #if DEBUG
                print("========== CHORES ATTENTION LOAD FAILED ==========")
                print("home_id: \(activeHomeId.uuidString)")
                print(String(reflecting: error))
                print("==================================================")
                #endif
            }
        }
    }

    private func resetCounts() {
        loadGeneration += 1
        dashboardChoresBadgeCount = nil
        myActionChoreCount = nil
        myPendingRewardCount = nil
        pendingChoreApprovalCount = nil
        pendingRewardRedemptionCount = nil
    }

    private func logChoresBadge(
        homeId: UUID,
        currentUserId: UUID,
        weekRange: (start: Date, end: Date),
        result: ChoresBadgeCountResult
    ) {
        #if DEBUG
        print("========== CHORES BADGE ==========")
        print("home_id: \(homeId.uuidString)")
        print("current_user_id: \(currentUserId.uuidString)")
        print("week_start: \(ChoreTimestampFormatter.string(from: weekRange.start))")
        print("next_week_start: \(ChoreTimestampFormatter.string(from: weekRange.end))")
        print("not_started_occurrence_count: \(result.count)")
        print("occurrence_ids:")
        result.occurrenceIds.forEach { occurrenceId in
            print("- \(occurrenceId.uuidString)")
        }
        print("==================================")
        #endif
    }
}

private struct ChoresAttentionCounts {
    let dashboardChoresBadge: ChoresBadgeCountResult
    let myActionChoreCount: Int
    let myPendingRewardCount: Int
    let pendingChoreApprovalCount: Int?
    let pendingRewardRedemptionCount: Int?
}
