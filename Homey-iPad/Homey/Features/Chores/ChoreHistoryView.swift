import Combine
import SwiftUI

struct ChoreHistoryView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = ChoreHistoryViewModel()
    @State private var selectedOccurrence: ChoreOccurrence?

    var body: some View {
        ChoreShellCard(title: "Chore History", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 18) {
                ChoreSectionDescriptionHeader(
                    title: "Chore History",
                    description: "Review completed chores, approvals, point activity, and household task history."
                )

                if let errorMessage = viewModel.errorMessage, viewModel.activities.isEmpty, !viewModel.isLoading {
                    ChoreMessageState(
                        title: "Unable to Load History",
                        message: errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        buttonTitle: "Try Again"
                    ) {
                        viewModel.reload()
                    }
                } else {
                    historyContent
                }
            }
        }
        .task(id: homeService.selectedHomeID) {
            await loadMembersIfNeeded()
            await configureViewModel()
        }
        .onChange(of: authenticationService.currentUser?.id) { _, _ in
            Task {
                await loadMembersIfNeeded()
                await configureViewModel()
            }
        }
        .onChange(of: homeService.membersForSelectedHome()) { _, _ in
            Task { await configureViewModel() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
        .sheet(item: $selectedOccurrence) { occurrence in
            ChoreOccurrenceDetailView(
                initialOccurrence: occurrence,
                homeTimezone: homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
            )
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if viewModel.canSelectMembers {
                ChoreHistoryMemberSelector(
                    members: viewModel.members,
                    selectedMemberId: viewModel.selectedMemberId
                ) { memberId in
                    viewModel.selectMember(memberId)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Activity")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                if viewModel.isLoading && viewModel.activities.isEmpty {
                    ChoreHistoryLoadingView()
                } else if viewModel.activities.isEmpty {
                    ChoreMessageState(
                        title: "No Chore Activity Yet",
                        message: viewModel.canSelectMembers ? "No activity for this member yet." : "Completed chores, rewards, and point activity will appear here.",
                        systemImage: "clock"
                    )
                } else {
                    ChoreHistoryActivityList(activities: viewModel.activities) { activity in
                        openOccurrence(for: activity)
                    }
                }

                if viewModel.hasMoreActivities {
                    Button {
                        viewModel.loadMore()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(HomeyDashboardTheme.warmBrown)
                            }

                            Text(viewModel.isLoadingMore ? "Loading..." : "Load More")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingMore)
                }
            }
        }
    }

    private var currentRole: HomeMemberRole? {
        homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHomeID = homeService.selectedHomeID,
              let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHomeID, currentUser: currentUser)
    }

    private func configureViewModel() async {
        await viewModel.configure(
            homeId: homeService.selectedHomeID,
            currentUserId: authenticationService.currentUser?.id,
            currentRole: currentRole,
            members: homeService.membersForSelectedHome()
        )
    }

    private func openOccurrence(for activity: ChoreHistoryActivity) {
        guard activity.occurrenceId != nil else { return }

        Task {
            selectedOccurrence = await viewModel.occurrence(for: activity)
        }
    }
}

private struct ChoreHistoryMemberSelector: View {
    let members: [HomeMemberDisplay]
    let selectedMemberId: UUID?
    let onSelect: (UUID) -> Void

    private var selectedMember: HomeMemberDisplay? {
        members.first { $0.userId == selectedMemberId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Member")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .textCase(.uppercase)

            Menu {
                ForEach(members) { member in
                    Button {
                        onSelect(member.userId)
                    } label: {
                        Label(member.displayName, systemImage: member.userId == selectedMemberId ? "checkmark" : "person")
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    if let selectedMember {
                        AvatarView(
                            imageURL: selectedMember.avatarURL,
                            initials: selectedMember.initials,
                            size: 36,
                            accentColor: HomeyDashboardTheme.sageAccent,
                            borderColor: HomeyDashboardTheme.appBackground,
                            borderWidth: 2,
                            showsShadow: false,
                            accessibilityLabel: "\(selectedMember.displayName) avatar"
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedMember.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)
                                .lineLimit(1)

                            if let email = selectedMember.email, !email.isEmpty {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("Select Member")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 58, alignment: .center)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Viewing chore history for \(selectedMember?.displayName ?? "selected member")")
        }
    }
}

private struct ChoreHistoryLoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(HomeyDashboardTheme.warmBrown)

            Text("Loading activity...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct ChoreHistoryActivityList: View {
    let activities: [ChoreHistoryActivity]
    let onOpenOccurrence: (ChoreHistoryActivity) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(activities) { activity in
                ChoreHistoryActivityRow(activity: activity) {
                    onOpenOccurrence(activity)
                }

                if activity.id != activities.last?.id {
                    Divider()
                        .overlay(HomeyDashboardTheme.softBorder)
                        .padding(.leading, 58)
                }
            }
        }
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct ChoreHistoryActivityRow: View {
    let activity: ChoreHistoryActivity
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: activity.activityType.historyIconName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(activity.activityType.historyAccentColor)
                    .frame(width: 34, height: 34)
                    .background(activity.activityType.historyAccentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(activity.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)

                    if let subtitle = activity.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .lineLimit(2)
                    }

                    Text(activity.occurredAt.historyFormattedDate)
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer(minLength: 10)

                if let pointsDelta = activity.pointsDelta {
                    Text(pointsDelta.historyPointsText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(pointsDelta >= 0 ? HomeyDashboardTheme.sageAccent : HomeyDashboardTheme.destructiveRed)
                        .lineLimit(1)
                        .accessibilityLabel(pointsDelta >= 0 ? "plus \(pointsDelta) points" : "minus \(abs(pointsDelta)) points")
                }

                if activity.occurrenceId != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.7))
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(activity.occurrenceId == nil)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private final class ChoreHistoryViewModel: ObservableObject {
    @Published private(set) var activities: [ChoreHistoryActivity] = []
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var selectedMemberId: UUID?
    @Published private(set) var canSelectMembers = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreActivities = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private let pageSize = 10
    private var activeHomeId: UUID?
    private var currentUserId: UUID?
    private var currentRole: HomeMemberRole?
    private var activeLoadId: UUID?
    private var nextOffset = 0

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    func configure(homeId: UUID?, currentUserId: UUID?, currentRole: HomeMemberRole?, members: [HomeMemberDisplay]) async {
        guard let homeId, let currentUserId else {
            reset()
            return
        }

        let sortedMembers = HomeMemberDisplay.sorted(members)
        let canSelectMembers = (currentRole == .owner || currentRole == .admin) && !sortedMembers.isEmpty
        let previousHomeId = activeHomeId
        let previousSelectedMemberId = selectedMemberId

        activeHomeId = homeId
        self.currentUserId = currentUserId
        self.currentRole = currentRole
        self.members = sortedMembers
        self.canSelectMembers = canSelectMembers

        let validSelection = selectedMemberId.flatMap { selectedId in
            sortedMembers.contains { $0.userId == selectedId } ? selectedId : nil
        }
        let nextSelectedMemberId = canSelectMembers ? (validSelection ?? currentUserId) : currentUserId
        selectedMemberId = nextSelectedMemberId

        if previousHomeId != homeId || previousSelectedMemberId != nextSelectedMemberId || activities.isEmpty {
            await loadSelectedMember(resetActivities: true)
        }
    }

    func selectMember(_ memberId: UUID) {
        guard canSelectMembers,
              members.contains(where: { $0.userId == memberId }),
              selectedMemberId != memberId else {
            return
        }

        selectedMemberId = memberId
        Task {
            await loadSelectedMember(resetActivities: true)
        }
    }

    func loadMore() {
        guard let activeHomeId,
              let selectedMemberId,
              !isLoading,
              !isLoadingMore,
              hasMoreActivities else {
            return
        }

        let loadingMemberId = selectedMemberId
        let loadingRole = currentRole
        isLoadingMore = true
        errorMessage = nil

        Task {
            defer { isLoadingMore = false }

            do {
                let nextPage = try await repository.fetchChoreHistoryActivities(
                    homeId: activeHomeId,
                    userId: loadingMemberId,
                    limit: pageSize,
                    offset: nextOffset,
                    currentRole: loadingRole
                )
                guard self.selectedMemberId == loadingMemberId else { return }
                activities.append(contentsOf: nextPage)
                nextOffset += pageSize
                hasMoreActivities = nextPage.count == pageSize
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func reload() {
        Task {
            await loadSelectedMember(resetActivities: true)
        }
    }

    func occurrence(for activity: ChoreHistoryActivity) async -> ChoreOccurrence? {
        guard let occurrenceId = activity.occurrenceId else { return nil }

        do {
            return try await repository.fetchOccurrence(id: occurrenceId)
        } catch {
            errorMessage = "Unable to open chore."
            return nil
        }
    }

    private func reset() {
        activeHomeId = nil
        currentUserId = nil
        currentRole = nil
        members = []
        selectedMemberId = nil
        canSelectMembers = false
        activities = []
        errorMessage = nil
        hasMoreActivities = false
        isLoading = false
        isLoadingMore = false
        nextOffset = 0
    }

    private func loadSelectedMember(resetActivities: Bool) async {
        guard let activeHomeId, let selectedMemberId else {
            reset()
            return
        }

        let loadId = UUID()
        activeLoadId = loadId
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        if resetActivities {
            activities = []
            hasMoreActivities = false
            nextOffset = 0
        }

        do {
            let firstPage = try await repository.fetchChoreHistoryActivities(
                homeId: activeHomeId,
                userId: selectedMemberId,
                limit: pageSize,
                offset: 0,
                currentRole: currentRole
            )
            guard activeLoadId == loadId, self.selectedMemberId == selectedMemberId else { return }
            activities = firstPage
            nextOffset = pageSize
            hasMoreActivities = firstPage.count == pageSize
        } catch {
            guard activeLoadId == loadId, self.selectedMemberId == selectedMemberId else { return }
            activities = []
            hasMoreActivities = false
            nextOffset = 0
            errorMessage = error.localizedDescription
        }

        if activeLoadId == loadId {
            isLoading = false
        }
    }
}

private extension Date {
    var historyFormattedDate: String {
        formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

private extension Int {
    var historyPointsText: String {
        "\(self >= 0 ? "+" : "-")\(abs(self)) points"
    }
}

private extension ChoreHistoryActivityType {
    var historyIconName: String {
        switch self {
        case .choreAssigned:
            return "person.crop.circle.badge.checkmark"
        case .choreStarted:
            return "play.fill"
        case .choreSubmitted:
            return "paperplane.fill"
        case .choreApproved, .choreCompleted, .pointsEarned:
            return "checkmark.circle.fill"
        case .choreNeedsRedo:
            return "arrow.counterclockwise.circle.fill"
        case .choreClaimed:
            return "hand.raised.fill"
        case .choreSkipped:
            return "forward.fill"
        case .choreCancelled:
            return "xmark.circle.fill"
        case .pointsAdjustment:
            return "plusminus.circle.fill"
        case .rewardRedeemed:
            return "gift.fill"
        case .rewardRefunded:
            return "arrow.uturn.backward.circle.fill"
        case .rewardFulfilled:
            return "shippingbox.fill"
        case .rewardCancelled:
            return "xmark.circle.fill"
        }
    }

    var historyAccentColor: Color {
        switch self {
        case .choreApproved, .choreCompleted, .pointsEarned, .rewardRefunded:
            return HomeyDashboardTheme.sageAccent
        case .choreNeedsRedo, .choreCancelled:
            return HomeyDashboardTheme.destructiveRed
        case .choreSubmitted:
            return HomeyDashboardTheme.orangeAccent
        case .rewardRedeemed:
            return HomeyDashboardTheme.warmBrown
        case .choreAssigned, .choreStarted, .choreClaimed, .choreSkipped, .pointsAdjustment, .rewardFulfilled, .rewardCancelled:
            return HomeyDashboardTheme.secondaryText
        }
    }
}
