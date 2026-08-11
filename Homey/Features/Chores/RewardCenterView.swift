import Combine
import SwiftUI

struct RewardCenterView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = RewardCenterViewModel()
    @State private var isPresentingAddReward = false
    @State private var editingReward: ChoreReward?
    @State private var selectedSection: RewardCenterSection = .rewards
    @State private var redeemingReward: ChoreReward?
    @State private var fulfillingRedemption: ChoreRewardRedemption?
    @State private var cancellingRedemption: ChoreRewardRedemption?

    init(initialSection: RewardCenterSection = .rewards) {
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        ChoreShellCard(title: "Rewards Center", systemImage: "gift.fill") {
            VStack(alignment: .leading, spacing: 18) {
                if selectedSection == .rewards {
                    header
                }
                if allowedSections.count > 1 {
                    sectionPicker
                }
                statusMessages
                sectionContent
            }
        }
        .task(id: RewardCenterLoadKey(homeId: homeService.selectedHomeID, role: currentRole, currentUserId: authenticationService.currentUser?.id)) {
            await loadMembersIfNeeded()
            await viewModel.load(
                homeId: homeService.selectedHomeID,
                role: currentRole,
                currentUserId: authenticationService.currentUser?.id,
                members: homeService.membersForSelectedHome()
            )
        }
        .onChange(of: homeService.membersForSelectedHome()) { _, _ in
            Task {
                await viewModel.load(
                    homeId: homeService.selectedHomeID,
                    role: currentRole,
                    currentUserId: authenticationService.currentUser?.id,
                    members: homeService.membersForSelectedHome()
                )
            }
        }
        .onAppear(perform: enforceAllowedSection)
        .onChange(of: canManageRewards) { _, canManage in
            enforceAllowedSection()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
        .sheet(isPresented: $isPresentingAddReward) {
            if let homeId = homeService.selectedHomeID {
                RewardEditorView(
                    mode: .add(homeId: homeId),
                    currentRole: currentRole,
                    repository: viewModel.repository
                ) {
                    viewModel.reload()
                }
            }
        }
        .sheet(item: $editingReward) { reward in
            RewardEditorView(
                mode: .edit(reward),
                currentRole: currentRole,
                repository: viewModel.repository
            ) {
                viewModel.reload()
            }
        }
        .sheet(item: $cancellingRedemption) { redemption in
            CancelRewardRedemptionView(
                redemption: redemption,
                memberName: viewModel.memberName(for: redemption.userId),
                currentRole: currentRole,
                repository: viewModel.repository
            ) {
                viewModel.handleCancelledRedemption()
            }
        }
        .confirmationDialog(
            "Redeem Reward?",
            isPresented: redeemConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Redeem") {
                if let reward = redeemingReward {
                    Task {
                        await viewModel.redeem(reward)
                        redeemingReward = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                redeemingReward = nil
            }
        } message: {
            if let reward = redeemingReward {
                Text("Redeem \(reward.name) for \(reward.pointCost.formatted(.number)) points?")
            }
        }
        .confirmationDialog(
            "Mark Reward Redeemed?",
            isPresented: fulfillConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Mark Redeemed") {
                if let redemption = fulfillingRedemption {
                    Task {
                        await viewModel.markRedeemed(redemption)
                        fulfillingRedemption = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                fulfillingRedemption = nil
            }
        } message: {
            Text("This confirms the reward has been fulfilled.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rewards")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("Create rewards household members can work toward.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            if canManageRewards, selectedSection == .rewards {
                Button {
                    isPresentingAddReward = true
                } label: {
                    Label("Add Reward", systemImage: "plus")
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 160)
                .accessibilityLabel("Add Reward")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.appBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .rewards:
            rewardCatalog
        case .myRewards:
            MyRewardsView(showsShellCard: false)
        case .pendingRedemptions:
            if canManageRewards {
                pendingRedemptions
            } else {
                rewardCatalog
            }
        case .redemptionHistory:
            if canManageRewards {
                redemptionHistory
            } else {
                rewardCatalog
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 8) {
            ForEach(allowedSections) { section in
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 7) {
                        Text(section.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)

                        AttentionBadge(count: section == .pendingRedemptions ? viewModel.pendingRedemptions.count : nil)
                    }
                    .foregroundStyle(selectedSection == section ? Color.white : HomeyDashboardTheme.primaryText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .frame(maxWidth: .infinity)
                    .background(section == selectedSection ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sectionAccessibilityLabel(section))
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let successMessage = viewModel.successMessage {
            Text(successMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HomeyDashboardTheme.sageAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if let actionErrorMessage = viewModel.actionErrorMessage {
            Text(actionErrorMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var rewardCatalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            RewardAvailablePointsCard(pointBalance: viewModel.pointBalance, isLoading: viewModel.isLoading)

            RewardCatalogControls(
                selectedFilter: viewModel.selectedRewardFilter,
                selectedSort: viewModel.selectedRewardSort
            ) { filter in
                viewModel.selectRewardFilter(filter)
            } onSortSelect: { sort in
                viewModel.selectRewardSort(sort)
            }

            if viewModel.isLoading && viewModel.rewards.isEmpty {
                ChoreLoadingState(message: "Loading rewards...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load Rewards",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else if viewModel.rewards.isEmpty {
                ChoreMessageState(
                    title: "No Rewards Yet",
                    message: canManageRewards ? "Use Add Reward to create the first reward." : "No rewards available right now.",
                    systemImage: "gift"
                )
            } else if viewModel.displayedRewards.isEmpty {
                ChoreMessageState(
                    title: viewModel.selectedRewardFilter.emptyTitle,
                    message: viewModel.selectedRewardFilter.emptyMessage(canManageRewards: canManageRewards),
                    systemImage: "gift"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.displayedRewards) { reward in
                        RewardTile(
                            reward: reward,
                            canEdit: canManageRewards,
                            pointBalance: viewModel.pointBalance,
                            isBalanceLoading: viewModel.isLoading,
                            isPendingRedemption: viewModel.currentUserPendingRewardIds.contains(reward.id),
                            isRedeeming: viewModel.redeemingRewardId == reward.id
                        ) {
                            if canManageRewards {
                                editingReward = reward
                            }
                        } onRedeem: {
                            redeemingReward = reward
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingRedemptions: some View {
        if viewModel.isLoading && viewModel.pendingRedemptions.isEmpty {
            ChoreLoadingState(message: "Loading pending redemptions...")
        } else if viewModel.pendingRedemptions.isEmpty {
            ChoreMessageState(
                title: "No Pending Redemptions",
                message: "Reward requests will appear here when members redeem rewards.",
                systemImage: "checkmark.circle"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pending Redemptions")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                VStack(spacing: 0) {
                    ForEach(viewModel.pendingRedemptions) { redemption in
                        PendingRewardRedemptionRow(
                            redemption: redemption,
                            memberName: viewModel.memberName(for: redemption.userId),
                            isMarkingRedeemed: viewModel.markingRedemptionId == redemption.id,
                            isCancelling: viewModel.cancellingRedemptionId == redemption.id
                        ) {
                            fulfillingRedemption = redemption
                        } onCancel: {
                            cancellingRedemption = redemption
                        }

                        if redemption.id != viewModel.pendingRedemptions.last?.id {
                            Divider()
                                .padding(.leading, 18)
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
    }

    @ViewBuilder
    private var redemptionHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Redemption History")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            RedemptionHistoryFilters(
                members: viewModel.members,
                selectedUserId: viewModel.selectedHistoryUserId,
                selectedStatus: viewModel.selectedHistoryStatusFilter
            ) { userId in
                viewModel.selectHistoryUser(userId)
            } onStatusSelect: { status in
                viewModel.selectHistoryStatus(status)
            }

            if viewModel.isLoading && viewModel.redemptionHistory.isEmpty {
                ChoreLoadingState(message: "Loading redemption history...")
            } else if viewModel.redemptionHistory.isEmpty {
                ChoreMessageState(
                    title: viewModel.selectedHistoryStatusFilter.emptyTitle,
                    message: "Finalized reward requests will appear here.",
                    systemImage: "clock"
                )
            } else {
                RedemptionHistoryList(redemptions: viewModel.redemptionHistory) { userId in
                    viewModel.memberName(for: userId)
                } handledByName: { userId in
                    viewModel.memberName(for: userId)
                }
            }

            if viewModel.hasMoreRedemptionHistory {
                Button {
                    viewModel.loadMoreRedemptionHistory()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isLoadingMoreRedemptionHistory {
                            ProgressView()
                                .controlSize(.small)
                                .tint(HomeyDashboardTheme.warmBrown)
                        }
                        Text(viewModel.isLoadingMoreRedemptionHistory ? "Loading..." : "Load More")
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
                .disabled(viewModel.isLoadingMoreRedemptionHistory)
            }
        }
    }

    private var currentRole: HomeMemberRole? {
        homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private var canManageRewards: Bool {
        currentRole == .owner || currentRole == .admin
    }

    private var allowedSections: [RewardCenterSection] {
        RewardCenterSection.visibleSections(canManageRewards: canManageRewards)
    }

    private func enforceAllowedSection() {
        guard !allowedSections.contains(selectedSection) else {
            return
        }

        selectedSection = .rewards
    }

    private func sectionAccessibilityLabel(_ section: RewardCenterSection) -> String {
        guard section == .pendingRedemptions, !viewModel.pendingRedemptions.isEmpty else {
            return section.title
        }

        return "\(section.title), \(viewModel.pendingRedemptions.count) redemptions pending"
    }

    private var redeemConfirmationBinding: Binding<Bool> {
        Binding {
            redeemingReward != nil
        } set: { isPresented in
            if !isPresented {
                redeemingReward = nil
            }
        }
    }

    private var fulfillConfirmationBinding: Binding<Bool> {
        Binding {
            fulfillingRedemption != nil
        } set: { isPresented in
            if !isPresented {
                fulfillingRedemption = nil
            }
        }
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHomeID = homeService.selectedHomeID,
              let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHomeID, currentUser: currentUser)
    }
}

private struct RewardAvailablePointsCard: View {
    let pointBalance: Int?
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Available Points")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .textCase(.uppercase)

                if isLoading && pointBalance == nil {
                    Text("Loading...")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                } else {
                    Text((pointBalance ?? 0).formatted(.number))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                }
            }

            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.title2)
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available points, \((pointBalance ?? 0).formatted(.number))")
    }
}

private struct RewardCatalogControls: View {
    let selectedFilter: RewardCatalogFilter
    let selectedSort: RewardCatalogSort
    let onFilterSelect: (RewardCatalogFilter) -> Void
    let onSortSelect: (RewardCatalogSort) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Filter rewards", selection: Binding(
                get: { selectedFilter },
                set: onFilterSelect
            )) {
                ForEach(RewardCatalogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                ForEach(RewardCatalogSort.allCases) { sort in
                    Button {
                        onSortSelect(sort)
                    } label: {
                        Label(sort.title, systemImage: sort == selectedSort ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedSort.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RewardTile: View {
    let reward: ChoreReward
    let canEdit: Bool
    let pointBalance: Int?
    let isBalanceLoading: Bool
    let isPendingRedemption: Bool
    let isRedeeming: Bool
    let onEdit: () -> Void
    let onRedeem: () -> Void

    private var pointsNeeded: Int {
        max(reward.pointCost - (pointBalance ?? 0), 0)
    }

    private var canRedeem: Bool {
        reward.isActive && !reward.isArchived && !isPendingRedemption && pointBalance.map { $0 >= reward.pointCost } == true && !isRedeeming
    }

    private var affordabilityText: String {
        if isPendingRedemption {
            return "Redemption Pending"
        }
        if !reward.isActive {
            return "Inactive"
        }
        if isBalanceLoading && pointBalance == nil {
            return "Checking points"
        }
        if pointsNeeded == 0 {
            return "You can afford this"
        }
        return "You need \(pointsNeeded.formatted(.number)) more points"
    }

    private var affordabilityColor: Color {
        if isPendingRedemption || !reward.isActive || pointsNeeded > 0 {
            return HomeyDashboardTheme.secondaryText
        }
        return HomeyDashboardTheme.sageAccent
    }

    private var accessibilityDescription: String {
        let state: String
        if isPendingRedemption {
            state = "Redemption pending."
        } else if !reward.isActive {
            state = "Inactive."
        } else if pointsNeeded == 0 {
            state = "You have enough points. Redeem available."
        } else {
            state = "You need \(pointsNeeded) more points."
        }
        return "\(reward.name). \(reward.pointCost) points. \(state)"
    }

    var body: some View {
        tileContent
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(reward.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if canEdit, !reward.isActive {
                        Text("Inactive")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(HomeyDashboardTheme.appBackground.opacity(0.9), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                            }
                    }

                    if canEdit {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                .frame(width: 32, height: 32)
                                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(reward.name)")
                    }
                }

                if let description = reward.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 12) {
                Text("\(reward.pointCost.formatted(.number)) Points")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .lineLimit(1)

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    if isPendingRedemption {
                        Text("Pending")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(HomeyDashboardTheme.appBackground, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                            }
                    } else {
                        Button {
                            onRedeem()
                        } label: {
                            HStack(spacing: 6) {
                                if isRedeeming {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(HomeyDashboardTheme.warmBrown)
                                }
                                Text(isRedeeming ? "Redeeming..." : "Redeem")
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(canRedeem ? Color.white : HomeyDashboardTheme.secondaryText)
                        .background(canRedeem ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.appBackground, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(canRedeem ? Color.clear : HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                        .disabled(!canRedeem)
                        .accessibilityLabel("Redeem \(reward.name)")
                    }

                    Text(affordabilityText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(affordabilityColor)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct PendingRewardRedemptionRow: View {
    let redemption: ChoreRewardRedemption
    let memberName: String
    let isMarkingRedeemed: Bool
    let isCancelling: Bool
    let onMarkRedeemed: () -> Void
    let onCancel: () -> Void

    private var requestedDate: String {
        redemption.requestedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(memberName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(redemption.rewardNameSnapshot)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                HStack(spacing: 8) {
                    Text("\(redemption.pointCostSnapshot.formatted(.number)) Points")
                    Text("Requested \(requestedDate)")
                    Text(redemption.status.displayName)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    onMarkRedeemed()
                } label: {
                    HStack(spacing: 6) {
                        if isMarkingRedeemed {
                            ProgressView()
                                .controlSize(.small)
                                .tint(HomeyDashboardTheme.warmBrown)
                        }
                        Text(isMarkingRedeemed ? "Updating..." : "Mark Redeemed")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isMarkingRedeemed || isCancelling)

                Button(role: .destructive) {
                    onCancel()
                } label: {
                    HStack(spacing: 6) {
                        if isCancelling {
                            ProgressView()
                                .controlSize(.small)
                                .tint(HomeyDashboardTheme.destructiveRed)
                        }
                        Text(isCancelling ? "Cancelling..." : "Cancel")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isMarkingRedeemed || isCancelling)
            }
        }
        .padding(18)
    }
}

private struct RewardCenterLoadKey: Equatable {
    let homeId: UUID?
    let role: HomeMemberRole?
    let currentUserId: UUID?
}

enum RewardCenterSection: String, CaseIterable, Identifiable {
    case rewards
    case myRewards
    case pendingRedemptions
    case redemptionHistory

    var id: String { rawValue }

    static func visibleSections(canManageRewards: Bool) -> [RewardCenterSection] {
        if canManageRewards {
            return [.rewards, .myRewards, .pendingRedemptions, .redemptionHistory]
        }
        return [.rewards, .myRewards]
    }

    var title: String {
        switch self {
        case .rewards:
            return "Rewards"
        case .myRewards:
            return "My Rewards"
        case .pendingRedemptions:
            return "Pending Redemptions"
        case .redemptionHistory:
            return "Rewards History"
        }
    }
}

private enum RewardCatalogFilter: String, CaseIterable, Identifiable {
    case all
    case canAfford

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Rewards"
        case .canAfford:
            return "Can Afford"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "No Rewards Available"
        case .canAfford:
            return "No Affordable Rewards"
        }
    }

    func emptyMessage(canManageRewards: Bool) -> String {
        switch self {
        case .all:
            return canManageRewards ? "Use Add Reward to create the first reward." : "No rewards available right now."
        case .canAfford:
            return "You don't have enough points for a reward yet. Keep earning points by completing chores."
        }
    }
}

private enum RewardCatalogSort: String, CaseIterable, Identifiable {
    case name
    case lowestCost
    case highestCost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            return "Name"
        case .lowestCost:
            return "Lowest Cost"
        case .highestCost:
            return "Highest Cost"
        }
    }
}

private enum RedemptionHistoryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case redeemed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .redeemed:
            return "Redeemed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var redemptionStatus: ChoreRewardRedemptionStatus? {
        switch self {
        case .all:
            return nil
        case .redeemed:
            return .redeemed
        case .cancelled:
            return .cancelled
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "No Redemption History Yet"
        case .redeemed:
            return "No Redeemed Rewards Found"
        case .cancelled:
            return "No Cancelled Rewards Found"
        }
    }
}

private struct RedemptionHistoryFilters: View {
    let members: [HomeMemberDisplay]
    let selectedUserId: UUID?
    let selectedStatus: RedemptionHistoryStatusFilter
    let onMemberSelect: (UUID?) -> Void
    let onStatusSelect: (RedemptionHistoryStatusFilter) -> Void

    private var selectedMemberName: String {
        guard let selectedUserId else {
            return "All Members"
        }

        return members.first { $0.userId == selectedUserId }?.displayName ?? "Selected Member"
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    onMemberSelect(nil)
                } label: {
                    Label("All Members", systemImage: selectedUserId == nil ? "checkmark" : "person.2")
                }

                ForEach(members) { member in
                    Button {
                        onMemberSelect(member.userId)
                    } label: {
                        Label(member.displayName, systemImage: member.userId == selectedUserId ? "checkmark" : "person")
                    }
                }
            } label: {
                filterLabel(title: "Member", value: selectedMemberName)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(RedemptionHistoryStatusFilter.allCases) { status in
                    Button {
                        onStatusSelect(status)
                    } label: {
                        Label(status.title, systemImage: status == selectedStatus ? "checkmark" : "line.3.horizontal.decrease.circle")
                    }
                }
            } label: {
                filterLabel(title: "Status", value: selectedStatus.title)
            }
            .buttonStyle(.plain)
        }
    }

    private func filterLabel(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .textCase(.uppercase)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .frame(maxWidth: .infinity)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct RedemptionHistoryList: View {
    let redemptions: [ChoreRewardRedemption]
    let memberName: (UUID) -> String
    let handledByName: (UUID) -> String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(redemptions) { redemption in
                RedemptionHistoryRow(
                    redemption: redemption,
                    memberName: memberName(redemption.userId),
                    handledByName: handlerName(for: redemption)
                )

                if redemption.id != redemptions.last?.id {
                    Divider()
                        .overlay(HomeyDashboardTheme.softBorder)
                        .padding(.leading, 18)
                }
            }
        }
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }

    private func handlerName(for redemption: ChoreRewardRedemption) -> String? {
        switch redemption.status {
        case .redeemed:
            return redemption.redeemedBy.map(handledByName)
        case .cancelled:
            return redemption.cancelledBy.map(handledByName)
        case .pending:
            return nil
        }
    }
}

private struct RedemptionHistoryRow: View {
    let redemption: ChoreRewardRedemption
    let memberName: String
    let handledByName: String?

    private var statusColor: Color {
        switch redemption.status {
        case .redeemed:
            return HomeyDashboardTheme.sageAccent
        case .cancelled:
            return HomeyDashboardTheme.destructiveRed.opacity(0.8)
        case .pending:
            return HomeyDashboardTheme.orangeAccent
        }
    }

    private var requestedText: String {
        "Requested: \(redemption.requestedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

    private var finalizedText: String {
        switch redemption.status {
        case .redeemed:
            return "Redeemed: \((redemption.redeemedAt ?? redemption.updatedAt).formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        case .cancelled:
            return "Cancelled: \((redemption.cancelledAt ?? redemption.updatedAt).formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        case .pending:
            return "Pending"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)
                .clipShape(Capsule())
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 7) {
                Text(memberName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(redemption.rewardNameSnapshot)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                Text("\(redemption.pointCostSnapshot.formatted(.number)) Points")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)

                Text(requestedText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                Text(finalizedText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                if let handledByName {
                    Text("Handled by: \(handledByName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                if redemption.status == .cancelled,
                   let reason = redemption.cancellationReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    Text("Reason: \(reason)")
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(2)
                }

                if redemption.status == .cancelled, redemption.refundTransactionId != nil {
                    Text("\(redemption.pointCostSnapshot.formatted(.number)) Points Refunded")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.sageAccent)
                }
            }

            Spacer(minLength: 10)

            Text(redemption.status.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.12), in: Capsule())
                .lineLimit(1)
        }
        .padding(18)
        .accessibilityElement(children: .combine)
    }
}

private enum RewardEditorMode: Identifiable {
    case add(homeId: UUID)
    case edit(ChoreReward)

    var id: String {
        switch self {
        case .add(let homeId):
            return "add-\(homeId.uuidString)"
        case .edit(let reward):
            return reward.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add:
            return "Add Reward"
        case .edit:
            return "Edit Reward"
        }
    }
}

private struct RewardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: RewardEditorMode
    let currentRole: HomeMemberRole?
    let repository: ChoresRepository
    let onSaved: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var pointCostText = ""
    @State private var isActive = true
    @State private var isSaving = false
    @State private var isArchiving = false
    @State private var errorMessage: String?
    @State private var isShowingArchiveConfirmation = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pointCost: Int? {
        Int(pointCostText)
    }

    private var validationMessage: String? {
        guard !trimmedName.isEmpty else {
            return "Enter a reward name."
        }

        guard let pointCost, pointCost > 0 else {
            return "Enter a point cost greater than 0."
        }

        guard currentRole == .owner || currentRole == .admin else {
            return "Only Home owners and admins can manage rewards."
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil && !isSaving && !isArchiving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    rewardNameField
                    descriptionField
                    pointCostField
                    activeToggle

                    if let visibleMessage = errorMessage ?? validationMessage {
                        Text(visibleMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if case .edit = mode {
                        archiveButton
                            .padding(.top, 8)
                    }
                }
                .padding(22)
            }
            .background(HomeyDashboardTheme.appBackground.ignoresSafeArea())
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving || isArchiving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveReward() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(HomeyDashboardTheme.warmBrown)
                        } else {
                            Text("Save Reward")
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .task {
            populateInitialValues()
        }
        .confirmationDialog(
            "Archive Reward?",
            isPresented: $isShowingArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Reward", role: .destructive) {
                Task { await archiveReward() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived rewards disappear from the normal Reward Center catalog.")
        }
        .presentationDetents([.large])
    }

    private var rewardNameField: some View {
        formField("Reward Name") {
            TextField("Movie Night", text: $name)
                .textInputAutocapitalization(.words)
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(16)
                .background(fieldBackground)
                .accessibilityLabel("Reward name")
        }
    }

    private var descriptionField: some View {
        formField("Description") {
            TextField("Choose Friday's movie.", text: $description, axis: .vertical)
                .lineLimit(3...5)
                .font(.body)
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(16)
                .background(fieldBackground)
                .accessibilityLabel("Description")
        }
    }

    private var pointCostField: some View {
        formField("Point Cost") {
            TextField("150", text: $pointCostText)
                .keyboardType(.numberPad)
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(16)
                .background(fieldBackground)
                .onChange(of: pointCostText) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        pointCostText = filtered
                    }
                }
                .accessibilityLabel("Point cost")
        }
    }

    private var activeToggle: some View {
        Toggle(isOn: $isActive) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("Inactive rewards stay in the catalog for admins but are not ready for redemption.")
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
        }
        .toggleStyle(.switch)
        .tint(HomeyDashboardTheme.sageAccent)
        .padding(16)
        .background(fieldBackground)
    }

    private var archiveButton: some View {
        Button(role: .destructive) {
            isShowingArchiveConfirmation = true
        } label: {
            HStack(spacing: 8) {
                if isArchiving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HomeyDashboardTheme.destructiveRed)
                }
                Text(isArchiving ? "Archiving..." : "Archive Reward")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isArchiving)
    }

    private var fieldBackground: some ShapeStyle {
        HomeyDashboardTheme.cardBackground
    }

    private func formField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            content()
        }
    }

    private func populateInitialValues() {
        guard case .edit(let reward) = mode, name.isEmpty, pointCostText.isEmpty else {
            return
        }

        name = reward.name
        description = reward.description ?? ""
        pointCostText = String(reward.pointCost)
        isActive = reward.isActive
    }

    private func saveReward() async {
        guard !isSaving, let pointCost else { return }
        guard validationMessage == nil else {
            errorMessage = validationMessage
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch mode {
            case .add(let homeId):
                _ = try await repository.createReward(
                    homeId: homeId,
                    name: trimmedName,
                    description: trimmedDescription,
                    pointCost: pointCost,
                    isActive: isActive,
                    currentRole: currentRole
                )
            case .edit(let reward):
                try await repository.updateReward(
                    rewardId: reward.id,
                    name: trimmedName,
                    description: trimmedDescription,
                    pointCost: pointCost,
                    isActive: isActive,
                    currentRole: currentRole
                )
            }

            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Unable to save reward."
        }
    }

    private func archiveReward() async {
        guard case .edit(let reward) = mode, !isArchiving else { return }

        isArchiving = true
        errorMessage = nil
        defer { isArchiving = false }

        do {
            try await repository.archiveReward(rewardId: reward.id, currentRole: currentRole)
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Unable to archive reward."
        }
    }
}

private struct CancelRewardRedemptionView: View {
    @Environment(\.dismiss) private var dismiss
    let redemption: ChoreRewardRedemption
    let memberName: String
    let currentRole: HomeMemberRole?
    let repository: ChoresRepository
    let onCancelled: () -> Void

    @State private var cancellationReason = ""
    @State private var isCancelling = false
    @State private var errorMessage: String?

    private var trimmedReason: String {
        cancellationReason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cancel Redemption?")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)

                        Text("This will cancel the pending reward and refund \(redemption.pointCostSnapshot.formatted(.number)) points to \(memberName).")
                            .font(.subheadline)
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cancellation Reason")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)

                        TextField("Reward unavailable", text: $cancellationReason, axis: .vertical)
                            .lineLimit(3...5)
                            .font(.body)
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                            .padding(16)
                            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                            }
                            .accessibilityLabel("Cancellation reason")

                        Text("Optional")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(role: .destructive) {
                        Task { await cancelAndRefund() }
                    } label: {
                        HStack(spacing: 8) {
                            if isCancelling {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(HomeyDashboardTheme.destructiveRed)
                            }

                            Text(isCancelling ? "Cancelling..." : "Cancel & Refund")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.18), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCancelling)
                }
                .padding(22)
            }
            .background(HomeyDashboardTheme.appBackground.ignoresSafeArea())
            .navigationTitle("Cancel Redemption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Pending") {
                        dismiss()
                    }
                    .disabled(isCancelling)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func cancelAndRefund() async {
        guard !isCancelling else { return }

        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }

        do {
            _ = try await repository.cancelRewardRedemption(
                redemptionId: redemption.id,
                cancellationReason: trimmedReason.isEmpty ? nil : trimmedReason,
                currentRole: currentRole
            )
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            onCancelled()
            dismiss()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        switch ChoreRepositoryError.map(error) {
        case .notFound:
            return "Unable to find this redemption."
        case .redemptionNotPending:
            return "This reward request is no longer pending."
        case .redemptionAlreadyRefunded:
            return "This reward has already been refunded."
        case .ownerOrAdminRequired, .ownerRequired:
            return "You don't have permission to manage this reward request."
        default:
            return error.localizedDescription
        }
    }
}

@MainActor
private final class RewardCenterViewModel: ObservableObject {
    @Published private(set) var rewards: [ChoreReward] = []
    @Published private(set) var pendingRedemptions: [ChoreRewardRedemption] = []
    @Published private(set) var redemptionHistory: [ChoreRewardRedemption] = []
    @Published private(set) var pointBalance: Int?
    @Published private(set) var currentUserPendingRewardIds: Set<UUID> = []
    @Published private(set) var selectedRewardFilter: RewardCatalogFilter = .all
    @Published private(set) var selectedRewardSort: RewardCatalogSort = .name
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var selectedHistoryUserId: UUID?
    @Published private(set) var selectedHistoryStatusFilter: RedemptionHistoryStatusFilter = .all
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMoreRedemptionHistory = false
    @Published private(set) var hasMoreRedemptionHistory = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var redeemingRewardId: UUID?
    @Published private(set) var markingRedemptionId: UUID?
    @Published private(set) var cancellingRedemptionId: UUID?

    let repository: ChoresRepository
    private let pageSize = 10
    private var activeHomeId: UUID?
    private var activeRole: HomeMemberRole?
    private var activeCurrentUserId: UUID?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    var displayedRewards: [ChoreReward] {
        let filteredRewards = rewards.filter { reward in
            switch selectedRewardFilter {
            case .all:
                return true
            case .canAfford:
                return reward.isActive && !reward.isArchived && pointBalance.map { $0 >= reward.pointCost } == true
            }
        }

        return filteredRewards.sorted { lhs, rhs in
            switch selectedRewardSort {
            case .name:
                return sortByName(lhs, rhs)
            case .lowestCost:
                if lhs.pointCost != rhs.pointCost {
                    return lhs.pointCost < rhs.pointCost
                }
                return sortByName(lhs, rhs)
            case .highestCost:
                if lhs.pointCost != rhs.pointCost {
                    return lhs.pointCost > rhs.pointCost
                }
                return sortByName(lhs, rhs)
            }
        }
    }

    func load(homeId: UUID?, role: HomeMemberRole?, currentUserId: UUID?, members: [HomeMemberDisplay]) async {
        guard let homeId, let currentUserId else {
            reset()
            return
        }

        activeHomeId = homeId
        activeRole = role
        activeCurrentUserId = currentUserId
        self.members = HomeMemberDisplay.sorted(members)
        if let selectedHistoryUserId,
           !self.members.contains(where: { $0.userId == selectedHistoryUserId }) {
            self.selectedHistoryUserId = nil
        }
        isLoading = true
        isLoadingMoreRedemptionHistory = false
        errorMessage = nil

        do {
            rewards = try await repository.fetchRewards(homeId: homeId, currentRole: role)
            pointBalance = try await repository.fetchPointBalance(homeId: homeId, userId: currentUserId, currentRole: role)
            let currentUserPendingRedemptions = try await repository.fetchMyPendingRewardRedemptions(homeId: homeId)
            currentUserPendingRewardIds = Set(currentUserPendingRedemptions.map(\.rewardId))

            if role == .owner || role == .admin {
                pendingRedemptions = try await repository.fetchPendingRewardRedemptions(homeId: homeId, currentRole: role)
                redemptionHistory = try await repository.fetchRewardRedemptionHistory(
                    homeId: homeId,
                    userId: selectedHistoryUserId,
                    status: selectedHistoryStatusFilter.redemptionStatus,
                    limit: pageSize,
                    offset: 0,
                    currentRole: role
                )
                hasMoreRedemptionHistory = redemptionHistory.count == pageSize
            } else {
                pendingRedemptions = []
                redemptionHistory = []
                hasMoreRedemptionHistory = false
                selectedHistoryUserId = nil
                selectedHistoryStatusFilter = .all
            }
        } catch {
            rewards = []
            pendingRedemptions = []
            redemptionHistory = []
            currentUserPendingRewardIds = []
            hasMoreRedemptionHistory = false
            pointBalance = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId, role: activeRole, currentUserId: activeCurrentUserId, members: members)
        }
    }

    func redeem(_ reward: ChoreReward) async {
        guard let activeHomeId, redeemingRewardId == nil, !currentUserPendingRewardIds.contains(reward.id) else { return }

        redeemingRewardId = reward.id
        actionErrorMessage = nil
        successMessage = nil
        defer { redeemingRewardId = nil }

        do {
            _ = try await repository.redeemReward(homeId: activeHomeId, rewardId: reward.id)
            successMessage = "Reward redeemed and is pending fulfillment."
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            await load(homeId: activeHomeId, role: activeRole, currentUserId: activeCurrentUserId, members: members)
        } catch {
            actionErrorMessage = Self.userFacingMessage(for: error)
            switch ChoreRepositoryError.map(error) {
            case .rewardAlreadyPending, .notEnoughPoints:
                await load(homeId: activeHomeId, role: activeRole, currentUserId: activeCurrentUserId, members: members)
            default:
                break
            }
        }
    }

    func selectRewardFilter(_ filter: RewardCatalogFilter) {
        selectedRewardFilter = filter
    }

    func selectRewardSort(_ sort: RewardCatalogSort) {
        selectedRewardSort = sort
    }

    func markRedeemed(_ redemption: ChoreRewardRedemption) async {
        guard markingRedemptionId == nil, cancellingRedemptionId == nil else { return }

        markingRedemptionId = redemption.id
        actionErrorMessage = nil
        successMessage = nil
        defer { markingRedemptionId = nil }

        do {
            _ = try await repository.markRewardRedeemed(redemptionId: redemption.id, currentRole: activeRole)
            successMessage = "Reward marked redeemed."
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            await load(homeId: activeHomeId, role: activeRole, currentUserId: activeCurrentUserId, members: members)
        } catch {
            actionErrorMessage = Self.userFacingMessage(for: error)
        }
    }

    func handleCancelledRedemption() {
        successMessage = "Reward cancelled and points refunded."
        actionErrorMessage = nil
        reload()
    }

    func selectHistoryUser(_ userId: UUID?) {
        guard activeRole == .owner || activeRole == .admin else { return }
        guard userId == nil || members.contains(where: { $0.userId == userId }) else { return }
        guard selectedHistoryUserId != userId else { return }

        selectedHistoryUserId = userId
        Task {
            await loadRedemptionHistory(reset: true)
        }
    }

    func selectHistoryStatus(_ status: RedemptionHistoryStatusFilter) {
        guard activeRole == .owner || activeRole == .admin, selectedHistoryStatusFilter != status else { return }

        selectedHistoryStatusFilter = status
        Task {
            await loadRedemptionHistory(reset: true)
        }
    }

    func loadMoreRedemptionHistory() {
        guard activeRole == .owner || activeRole == .admin,
              !isLoading,
              !isLoadingMoreRedemptionHistory,
              hasMoreRedemptionHistory else {
            return
        }

        Task {
            await loadRedemptionHistory(reset: false)
        }
    }

    func memberName(for userId: UUID) -> String {
        members.first { $0.userId == userId }?.displayName ?? "Home Member"
    }

    private static func userFacingMessage(for error: Error) -> String {
        switch ChoreRepositoryError.map(error) {
        case .notEnoughPoints:
            return "You no longer have enough points for this reward."
        case .rewardUnavailable:
            return "Reward is not available."
        case .rewardAlreadyPending:
            return "This reward is already pending."
        case .redemptionNotPending:
            return "This reward request is no longer pending."
        case .redemptionAlreadyRefunded:
            return "This reward has already been refunded."
        case .ownerOrAdminRequired, .ownerRequired:
            return "Owner or admin permission required."
        case .notFound:
            return "Unable to find this redemption."
        default:
            return error.localizedDescription
        }
    }

    private func loadRedemptionHistory(reset: Bool) async {
        guard let activeHomeId, activeRole == .owner || activeRole == .admin else {
            redemptionHistory = []
            hasMoreRedemptionHistory = false
            return
        }

        if reset {
            redemptionHistory = []
            hasMoreRedemptionHistory = false
        }

        isLoadingMoreRedemptionHistory = !reset
        if reset {
            isLoading = true
        }
        errorMessage = nil
        defer {
            isLoadingMoreRedemptionHistory = false
            if reset {
                isLoading = false
            }
        }

        do {
            let nextPage = try await repository.fetchRewardRedemptionHistory(
                homeId: activeHomeId,
                userId: selectedHistoryUserId,
                status: selectedHistoryStatusFilter.redemptionStatus,
                limit: pageSize,
                offset: reset ? 0 : redemptionHistory.count,
                currentRole: activeRole
            )

            if reset {
                redemptionHistory = nextPage
            } else {
                redemptionHistory.append(contentsOf: nextPage)
            }
            hasMoreRedemptionHistory = nextPage.count == pageSize
        } catch {
            if reset {
                redemptionHistory = []
                hasMoreRedemptionHistory = false
            }
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        activeHomeId = nil
        activeRole = nil
        activeCurrentUserId = nil
        rewards = []
        pendingRedemptions = []
        redemptionHistory = []
        pointBalance = nil
        currentUserPendingRewardIds = []
        selectedRewardFilter = .all
        selectedRewardSort = .name
        members = []
        selectedHistoryUserId = nil
        selectedHistoryStatusFilter = .all
        errorMessage = nil
        actionErrorMessage = nil
        successMessage = nil
        redeemingRewardId = nil
        markingRedemptionId = nil
        cancellingRedemptionId = nil
        isLoading = false
        isLoadingMoreRedemptionHistory = false
        hasMoreRedemptionHistory = false
    }

    private func sortByName(_ lhs: ChoreReward, _ rhs: ChoreReward) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
