import Combine
import Supabase
import SwiftUI

struct ChoreHistoryView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var model = PhoneChoreHistoryViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.canViewAllUsers {
                    memberFilter
                }

                if model.isLoading && model.activities.isEmpty {
                    ProgressView("Loading history…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if let errorMessage = model.errorMessage, model.activities.isEmpty {
                    errorState(errorMessage)
                } else if model.activities.isEmpty {
                    emptyState
                } else {
                    activityList

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(HomeyColors.danger)
                    }

                    if model.hasMoreActivities {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isLoadingMore { ProgressView().controlSize(.small) }
                                Text(model.isLoadingMore ? "Loading…" : "Load More")
                            }
                        }
                        .buttonStyle(HomeyButtonStyle(secondary: true))
                        .disabled(model.isLoadingMore)
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await load(force: true) }
        .task(id: historyContext) { await load(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyChoresDidChange"))) { _ in
            Task { await load(force: true) }
        }
    }

    private var historyContext: String {
        "\(appSession.activeHome?.id.uuidString ?? "no-home")-\(appSession.currentUser?.id.uuidString ?? "no-user")-\(appSession.activeRole?.rawValue ?? "no-role")"
    }

    private var memberFilter: some View {
        Menu {
            Button {
                Task { await model.selectMember(nil) }
            } label: {
                Label("All Users", systemImage: model.selectedMemberID == nil ? "checkmark" : "person.2")
            }

            Divider()

            ForEach(model.members) { member in
                Button {
                    Task { await model.selectMember(member.userID) }
                } label: {
                    Label(member.displayName, systemImage: model.selectedMemberID == member.userID ? "checkmark" : "person")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(HomeyColors.primary)
                Text(model.selectedMemberName ?? "All Users")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyColors.text)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyColors.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
            .overlay {
                RoundedRectangle(cornerRadius: HomeyCornerRadius.field)
                    .stroke(HomeyColors.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter history by user")
        .accessibilityValue(model.selectedMemberName ?? "All Users")
    }

    private var activityList: some View {
        VStack(spacing: 0) {
            ForEach(model.activities) { item in
                PhoneChoreHistoryRow(item: item, timezone: appSession.activeTimezone)

                if item.id != model.activities.last?.id {
                    Divider().padding(.leading, 58)
                }
            }
        }
        .padding(.vertical, 2)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: HomeyCornerRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HomeyCornerRadius.card, style: .continuous)
                .stroke(HomeyColors.border.opacity(0.7), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        ChorePlaceholderView(
            title: "No history yet",
            message: model.selectedMemberName.map { "No history for \($0) yet." } ?? "Chore, Task, and Reward activity will appear here.",
            symbol: "clock.arrow.circlepath"
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            HomeyErrorView(message: message)
            Button("Try Again") { Task { await load(force: true) } }
                .buttonStyle(HomeyButtonStyle())
        }
        .homeyCard()
    }

    private func load(force: Bool) async {
        await model.configure(
            homeID: appSession.activeHome?.id,
            currentUser: appSession.currentUser,
            role: appSession.activeRole,
            force: force
        )
    }
}

private struct PhoneChoreHistoryRow: View {
    let item: PhoneChoreHistoryItem
    let timezone: TimeZone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.activity.activityType.iconName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(item.activity.activityType.tint)
                .frame(width: 34, height: 34)
                .background(item.activity.activityType.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.activity.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyColors.text)
                    .lineLimit(2)

                Text(item.attribution)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyColors.secondaryText)

                Text(item.activity.occurredAt.choreHistoryFormatted(in: timezone))
                    .font(.caption)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .lineLimit(1)

                if !item.isDailyTask, let subtitle = item.activity.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(HomeyColors.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let points = item.activity.pointsDelta, points != 0 {
                Text("\(points >= 0 ? "+" : "−")\(abs(points)) pts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(points >= 0 ? HomeyColors.success : HomeyColors.danger)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

private struct PhoneChoreHistoryItem: Identifiable, Hashable {
    let source: PhoneHistorySource
    let activity: PhoneChoreHistoryActivity
    let memberName: String
    var id: String { "\(source.rawValue):\(activity.id):\(memberName)" }
    var isDailyTask: Bool { source == .dailyTask }
    var attribution: String {
        guard isDailyTask else { return memberName }
        let type = activity.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(memberName) • \((type?.isEmpty == false ? type : nil) ?? "Daily Task")"
    }
}

private enum PhoneHistorySource: String, Hashable {
    case chore
    case dailyTask
}

private struct PhoneHomeMember: Decodable, Identifiable, Hashable {
    let membershipID: UUID
    let homeID: UUID
    let userID: UUID
    let role: HomeMemberRole
    let firstName: String?
    let lastName: String?
    let profileDisplayName: String?
    let email: String?

    var id: UUID { membershipID }
    var displayName: String {
        let custom = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        let emailName = email?.split(separator: "@").first.map(String.init) ?? ""
        return emailName.isEmpty ? "Home Member" : emailName
    }

    enum CodingKeys: String, CodingKey {
        case membershipID = "membership_id"
        case homeID = "home_id"
        case userID = "user_id"
        case role
        case firstName = "first_name"
        case lastName = "last_name"
        case profileDisplayName = "display_name"
        case email
    }
}

private struct PhoneChoreHistoryActivity: Decodable, Hashable {
    let id: String
    let activityType: PhoneChoreHistoryActivityType
    let userID: UUID
    let title: String
    let subtitle: String?
    let occurredAt: Date
    let pointsDelta: Int?

    enum CodingKeys: String, CodingKey {
        case id = "activity_id"
        case activityType = "activity_type"
        case userID = "user_id"
        case title, subtitle
        case occurredAt = "occurred_at"
        case pointsDelta = "points_delta"
    }
}

private enum PhoneChoreHistoryActivityType: String, Decodable, Hashable {
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
    case rewardCancelled = "reward_cancelled"
    case taskCompleted = "task_completed"

    var iconName: String {
        switch self {
        case .choreApproved, .choreCompleted, .pointsEarned, .taskCompleted: "checkmark"
        case .choreSubmitted: "paperplane.fill"
        case .choreNeedsRedo: "arrow.counterclockwise"
        case .choreAssigned: "person.crop.circle.badge.checkmark"
        case .choreStarted: "play.fill"
        case .choreClaimed: "hand.raised.fill"
        case .choreSkipped, .choreCancelled: "forward.end.fill"
        case .pointsAdjustment: "plusminus"
        case .rewardRedeemed, .rewardFulfilled: "gift.fill"
        case .rewardRefunded, .rewardCancelled: "arrow.uturn.backward"
        }
    }

    var tint: Color {
        switch self {
        case .choreApproved, .choreCompleted, .pointsEarned, .taskCompleted, .rewardRefunded, .rewardFulfilled: HomeyColors.success
        case .choreNeedsRedo, .choreCancelled, .rewardCancelled: HomeyColors.danger
        case .choreSubmitted: .orange
        default: HomeyColors.secondaryText
        }
    }
}

private struct PhoneGetHomeMembersParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "target_home_id" }
}

private struct PhoneChoreHistoryParameters: Encodable {
    let homeID: UUID
    let userID: UUID
    let limit: Int
    let offset: Int
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case userID = "requested_user_id"
        case limit = "requested_limit"
        case offset = "requested_offset"
    }
}

private struct PhoneHomeChoreHistoryParameters: Encodable {
    let homeID: UUID
    let limit: Int
    let offset: Int
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case limit = "requested_limit"
        case offset = "requested_offset"
    }
}

private final class PhoneChoreHistoryRepository {
    private let client = SupabaseManager.shared.client

    func fetchMembers(homeID: UUID) async throws -> [PhoneHomeMember] {
        try await client
            .rpc("get_home_members", params: PhoneGetHomeMembersParameters(homeID: homeID))
            .execute()
            .value
    }

    func fetchHistory(homeID: UUID, userID: UUID, limit: Int, offset: Int) async throws -> [PhoneChoreHistoryActivity] {
        try await client
            .rpc(
                "get_chore_history",
                params: PhoneChoreHistoryParameters(homeID: homeID, userID: userID, limit: max(limit, 1), offset: max(offset, 0))
            )
            .execute()
            .value
    }

    func fetchHomeHistory(homeID: UUID, limit: Int, offset: Int) async throws -> [PhoneChoreHistoryActivity] {
        try await client
            .rpc(
                "get_home_chore_history",
                params: PhoneHomeChoreHistoryParameters(homeID: homeID, limit: max(limit, 1), offset: max(offset, 0))
            )
            .execute()
            .value
    }

    func fetchTaskHistory(homeID: UUID, userID: UUID, limit: Int, offset: Int) async throws -> [PhoneChoreHistoryActivity] {
        try await client
            .rpc(
                "get_daily_task_history",
                params: PhoneChoreHistoryParameters(homeID: homeID, userID: userID, limit: max(limit, 1), offset: max(offset, 0))
            )
            .execute()
            .value
    }

    func fetchHomeTaskHistory(homeID: UUID, limit: Int, offset: Int) async throws -> [PhoneChoreHistoryActivity] {
        try await client
            .rpc(
                "get_home_daily_task_history",
                params: PhoneHomeChoreHistoryParameters(homeID: homeID, limit: max(limit, 1), offset: max(offset, 0))
            )
            .execute()
            .value
    }
}

@MainActor
private final class PhoneChoreHistoryViewModel: ObservableObject {
    @Published private(set) var activities: [PhoneChoreHistoryItem] = []
    @Published private(set) var members: [PhoneHomeMember] = []
    @Published private(set) var selectedMemberID: UUID?
    @Published private(set) var canViewAllUsers = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreActivities = false
    @Published private(set) var errorMessage: String?

    private let repository = PhoneChoreHistoryRepository()
    private let individualPageSize = 25
    private let homePageSize = 100
    private var activeHomeID: UUID?
    private var currentUserID: UUID?
    private var activeRole: HomeMemberRole?
    private var choreActivities: [PhoneChoreHistoryActivity] = []
    private var taskActivities: [PhoneChoreHistoryActivity] = []
    private var choreHasMore = true
    private var taskHasMore = true
    private var displayLimit = 0
    private var loadID = UUID()

    var selectedMemberName: String? {
        guard let selectedMemberID else { return nil }
        return members.first { $0.userID == selectedMemberID }?.displayName
    }

    func configure(homeID: UUID?, currentUser: UserProfile?, role: HomeMemberRole?, force: Bool) async {
        guard let homeID, let currentUser else {
            reset()
            return
        }

        let nextCanViewAllUsers = Self.hasHouseholdHistoryAccess(role)
        let homeChanged = activeHomeID != homeID
        let contextChanged = homeChanged || currentUserID != currentUser.id || canViewAllUsers != nextCanViewAllUsers

        if contextChanged {
            loadID = UUID()
            activities = []
            resetPagination()
            errorMessage = nil
            selectedMemberID = nextCanViewAllUsers ? nil : currentUser.id
        }

        activeHomeID = homeID
        currentUserID = currentUser.id
        activeRole = role
        canViewAllUsers = nextCanViewAllUsers

        if canViewAllUsers {
            do {
                let loadedMembers = try await repository.fetchMembers(homeID: homeID)
                guard activeHomeID == homeID else { return }
                members = loadedMembers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                if let selectedMemberID, !members.contains(where: { $0.userID == selectedMemberID }) {
                    self.selectedMemberID = nil
                }
            } catch {
                if isCancellation(error) { return }
                fail(error, message: "We couldn't load the members for this Home.")
                return
            }
        } else {
            selectedMemberID = currentUser.id
            members = [PhoneHomeMember(
                membershipID: currentUser.id,
                homeID: homeID,
                userID: currentUser.id,
                role: role ?? .member,
                firstName: currentUser.firstName,
                lastName: currentUser.lastName,
                profileDisplayName: currentUser.displayName,
                email: currentUser.email
            )]
        }

        if contextChanged || force || activities.isEmpty {
            await reload()
        }
    }

    func selectMember(_ userID: UUID?) async {
        guard canViewAllUsers else { return }
        guard userID == nil || members.contains(where: { $0.userID == userID }) else { return }
        guard selectedMemberID != userID else { return }
        selectedMemberID = userID
        await reload()
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMoreActivities else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }
        let pageSize = currentPageSize
        let previousDisplayLimit = displayLimit
        displayLimit += pageSize
        if !(await fetchToDisplayLimit()) {
            displayLimit = previousDisplayLimit
        }
    }

    private func reload() async {
        loadID = UUID()
        resetPagination()
        displayLimit = currentPageSize
        activities = []
        hasMoreActivities = false
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        _ = await fetchToDisplayLimit()
    }

    private var currentPageSize: Int {
        let isAllUsersRequest = Self.hasHouseholdHistoryAccess(activeRole) && selectedMemberID == nil
        return isAllUsersRequest ? homePageSize : individualPageSize
    }

    private func fetchToDisplayLimit() async -> Bool {
        guard let homeID = activeHomeID, let currentUserID else { return false }
        let requestedLoadID = loadID

        do {
            // Role is Home-specific. Evaluate it again at request time so a
            // member can never reach the household RPC through stale filter state.
            let hasHouseholdAccess = Self.hasHouseholdHistoryAccess(activeRole)
            let isAllUsersRequest = hasHouseholdAccess && selectedMemberID == nil
            let pageSize = isAllUsersRequest ? homePageSize : individualPageSize
            let requestedUserID = isAllUsersRequest ? nil : (hasHouseholdAccess ? selectedMemberID : currentUserID)
            if !isAllUsersRequest, requestedUserID == nil { return false }

            var nextChoreActivities = choreActivities
            var nextTaskActivities = taskActivities
            var nextChoreHasMore = choreHasMore
            var nextTaskHasMore = taskHasMore

            while nextChoreActivities.count < displayLimit && nextChoreHasMore {
                let page: [PhoneChoreHistoryActivity]
                if isAllUsersRequest {
                    page = try await repository.fetchHomeHistory(
                        homeID: homeID,
                        limit: pageSize,
                        offset: nextChoreActivities.count
                    )
                } else {
                    page = try await repository.fetchHistory(
                        homeID: homeID,
                        userID: requestedUserID!,
                        limit: pageSize,
                        offset: nextChoreActivities.count
                    )
                }
                nextChoreActivities.append(contentsOf: page)
                nextChoreHasMore = page.count == pageSize
            }

            while nextTaskActivities.count < displayLimit && nextTaskHasMore {
                let page: [PhoneChoreHistoryActivity]
                if isAllUsersRequest {
                    page = try await repository.fetchHomeTaskHistory(
                        homeID: homeID,
                        limit: pageSize,
                        offset: nextTaskActivities.count
                    )
                } else {
                    page = try await repository.fetchTaskHistory(
                        homeID: homeID,
                        userID: requestedUserID!,
                        limit: pageSize,
                        offset: nextTaskActivities.count
                    )
                }
                nextTaskActivities.append(contentsOf: page)
                nextTaskHasMore = page.count == pageSize
            }

            guard loadID == requestedLoadID, activeHomeID == homeID else { return false }
            choreActivities = nextChoreActivities
            taskActivities = nextTaskActivities
            choreHasMore = nextChoreHasMore
            taskHasMore = nextTaskHasMore

            let namesByUserID = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.displayName) })
            let choreItems = choreActivities.map { activity in
                PhoneChoreHistoryItem(
                    source: .chore,
                    activity: activity,
                    memberName: namesByUserID[activity.userID] ?? "Home Member"
                )
            }
            let taskItems = taskActivities.map { activity in
                PhoneChoreHistoryItem(
                    source: .dailyTask,
                    activity: activity,
                    memberName: namesByUserID[activity.userID] ?? "Home Member"
                )
            }
            let merged = (choreItems + taskItems).sorted(by: Self.historyOrder)
            activities = Array(merged.prefix(displayLimit))
            hasMoreActivities = merged.count > displayLimit || choreHasMore || taskHasMore
            return true
        } catch is CancellationError {
            return false
        } catch {
            if isCancellation(error) { return false }
            fail(error, message: "We couldn't load History.")
            return false
        }
    }

    private static func historyOrder(_ lhs: PhoneChoreHistoryItem, _ rhs: PhoneChoreHistoryItem) -> Bool {
        if lhs.activity.occurredAt != rhs.activity.occurredAt {
            return lhs.activity.occurredAt > rhs.activity.occurredAt
        }
        return lhs.id > rhs.id
    }

    private func fail(_ error: Error, message: String) {
        errorMessage = message
        #if DEBUG
        print("[Homey] CHORE HISTORY ERROR home=\(activeHomeID?.uuidString ?? "none") role=\(activeRole?.rawValue ?? "unknown") filter=\(selectedMemberID?.uuidString ?? (canViewAllUsers ? "all" : "self")): \(String(reflecting: error))")
        #endif
    }

    private static func hasHouseholdHistoryAccess(_ role: HomeMemberRole?) -> Bool {
        role == .owner || role == .admin
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error { return isCancellation(underlying) }
        return false
    }

    private func resetPagination() {
        choreActivities = []
        taskActivities = []
        choreHasMore = true
        taskHasMore = true
        displayLimit = 0
    }

    private func reset() {
        activeHomeID = nil
        currentUserID = nil
        activeRole = nil
        activities = []
        members = []
        selectedMemberID = nil
        canViewAllUsers = false
        isLoading = false
        isLoadingMore = false
        hasMoreActivities = false
        errorMessage = nil
        resetPagination()
    }
}

private extension Date {
    func choreHistoryFormatted(in timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timezone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
