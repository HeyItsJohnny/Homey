import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @EnvironmentObject private var attentionStore: ChoresAttentionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: ChoresTab = .myChores
    @State private var activeCreationSheet: ChoreCreationSheet?
    @State private var isPresentingSearch = false

    private var permissionResolution: PermissionResolutionState {
        homeService.permissionResolutionState(currentUser: authenticationService.currentUser)
    }

    private var currentRole: HomeMemberRole? {
        guard case .resolved = permissionResolution else {
            return nil
        }

        return homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private var visibleTabs: [ChoresTab] {
        switch currentRole {
        case .owner, .admin:
            return ChoresTab.ownerAdminVisibleTabs
        case .member, nil:
            return ChoresTab.memberVisibleTabs
        }
    }

    private var canManageChores: Bool {
        switch currentRole {
        case .owner, .admin:
            return true
        case .member, nil:
            return false
        }
    }

    private var canManageRewards: Bool {
        switch currentRole {
        case .owner, .admin:
            return true
        case .member, nil:
            return false
        }
    }

    private var canShowAddMenu: Bool {
        canManageChores || canManageRewards
    }

    private var selectedHomeID: UUID? {
        homeService.selectedHomeID
    }

    private var selectedHomeWeekStartsOn: Int? {
        homeService.selectedHome()?.weekStartsOn
    }

    private var selectedHomeTimezone: String {
        homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    ChoresTabSelector(tabs: visibleTabs, selectedTab: $selectedTab) { tab in
                        badgeCount(for: tab)
                    }
                    selectedTabContent
                        .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: keepSelectedTabAvailable)
        .onChange(of: visibleTabs) { _, _ in
            keepSelectedTabAvailable()
        }
        .task(id: ChoresAttentionLoadKey(
            homeId: selectedHomeID,
            currentUserId: authenticationService.currentUser?.id,
            role: currentRole,
            weekStartsOn: selectedHomeWeekStartsOn,
            timezone: selectedHomeTimezone
        )) {
            attentionStore.configure(
                homeId: selectedHomeID,
                currentUserId: authenticationService.currentUser?.id,
                role: currentRole,
                weekStartsOn: selectedHomeWeekStartsOn,
                timezone: selectedHomeTimezone
            )
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                attentionStore.refresh()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                attentionStore.refresh()
            }
        }
        .sheet(item: $activeCreationSheet) { sheet in
            switch sheet {
            case .chore:
                ChoreEditorView(homeId: selectedHomeID, timezone: selectedHomeTimezone)
            case .reward:
                if let selectedHomeID {
                    RewardEditorView(
                        mode: .add(homeId: selectedHomeID),
                        currentRole: currentRole,
                        repository: ChoresRepository()
                    ) {
                        attentionStore.refresh()
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingSearch) {
            ChoreSearchView()
        }
    }

    @ViewBuilder
    private var header: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                headerActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 18) {
                titleBlock
                Spacer()
                headerActions
                    .padding(.trailing, 70)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chores")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Keep your home organized, one task at a time.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                isPresentingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: 44, height: 44)
                    .background(HomeyDashboardTheme.cardBackground, in: Circle())
                    .overlay {
                        Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search chores")

            if canShowAddMenu {
                Menu {
                    if canManageChores {
                        Button {
                            activeCreationSheet = .chore
                        } label: {
                            Label("Add Chore", systemImage: "checklist")
                        }
                    }

                    if canManageRewards {
                        Button {
                            activeCreationSheet = .reward
                        } label: {
                            Label("Add Reward", systemImage: "gift")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add")
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 124)
                .accessibilityLabel("Add")
                .accessibilityHint("Shows creation options")
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .myChores:
            MyChoresView()
        case .myRewards:
            RewardCenterView(initialSection: .myRewards)
        case .houseChores:
            HouseChoresView()
        case .rewardCenter:
            RewardCenterView()
        case .choreHistory:
            ChoreHistoryView()
        }
    }

    private func keepSelectedTabAvailable() {
        guard !visibleTabs.contains(selectedTab) else {
            return
        }

        selectedTab = .myChores
    }

    private func badgeCount(for tab: ChoresTab) -> Int? {
        switch tab {
        case .myChores:
            return nil
        case .myRewards:
            return attentionStore.myPendingRewardCount
        case .houseChores:
            guard canManageChores else { return nil }
            return attentionStore.pendingChoreApprovalCount
        case .rewardCenter:
            guard canManageChores else { return nil }
            return attentionStore.pendingRewardRedemptionCount
        case .choreHistory:
            return nil
        }
    }
}

// Future chore records will link to Homey calendar events. The chore record will remain the source of truth for assignment, completion, approval, and points, while the calendar event represents scheduling.

private struct ChoresAttentionLoadKey: Equatable {
    let homeId: UUID?
    let currentUserId: UUID?
    let role: HomeMemberRole?
    let weekStartsOn: Int?
    let timezone: String
}
