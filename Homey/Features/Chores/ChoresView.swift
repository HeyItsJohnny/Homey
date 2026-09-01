import Combine
import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @EnvironmentObject private var attentionStore: ChoresAttentionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var firstRunViewModel = ChoresFirstRunViewModel()
    @State private var selectedTab: ChoresTab = .myChores
    @State private var activeCreationSheet: ChoreCreationSheet?
    @State private var isPresentingSearch = false
    @State private var isPresentingQuickSetup = false
    @State private var isSetupHeroDismissed = false

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

                    if firstRunViewModel.isResolvingInitialState {
                        ChoreLoadingState(message: "Loading chores and rewards...")
                            .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
                    } else if firstRunViewModel.shouldShowSetupHero && !isSetupHeroDismissed {
                        ChoresFirstRunSetupHero {
                            isPresentingQuickSetup = true
                        } onManualSetup: {
                            isSetupHeroDismissed = true
                        }
                        .frame(maxWidth: .infinity, minHeight: 520, alignment: .center)
                    } else {
                        ChoresTabSelector(
                            tabs: visibleTabs,
                            selectedTab: $selectedTab,
                            title: title(for:)
                        ) { tab in
                            badgeCount(for: tab)
                        }
                        selectedTabContent
                            .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
                    }
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
        .task(id: ChoresFirstRunLoadKey(homeId: selectedHomeID, role: currentRole)) {
            await firstRunViewModel.load(homeId: selectedHomeID, currentRole: currentRole)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                attentionStore.refresh()
                await firstRunViewModel.reload()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                attentionStore.refresh()
                Task {
                    await firstRunViewModel.reload()
                }
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
        .sheet(isPresented: $isPresentingQuickSetup) {
            ChoreQuickSetupView(
                homeId: selectedHomeID,
                currentRole: currentRole,
                timezone: selectedHomeTimezone,
                members: homeService.membersForSelectedHome()
            ) {
                selectedTab = .myChores
                firstRunViewModel.markCreatedContent()
                attentionStore.refresh()
            } onShowRewards: {
                selectedTab = .rewardCenter
                firstRunViewModel.markCreatedContent()
                attentionStore.refresh()
            }
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

    private func title(for tab: ChoresTab) -> String {
        if tab == .myChores && canManageChores {
            return "All Chores"
        }

        return tab.title
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

private struct ChoresFirstRunLoadKey: Equatable {
    let homeId: UUID?
    let role: HomeMemberRole?
}

@MainActor
private final class ChoresFirstRunViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var canEvaluateSetupState = false
    @Published private(set) var choreCount = 0
    @Published private(set) var rewardCount = 0

    private let repository = ChoresRepository()
    private var currentHomeID: UUID?
    private var currentRole: HomeMemberRole?

    var isResolvingInitialState: Bool {
        isLoading && !hasLoaded
    }

    var shouldShowSetupHero: Bool {
        hasLoaded && canEvaluateSetupState && choreCount == 0 && rewardCount == 0
    }

    func load(homeId: UUID?, currentRole: HomeMemberRole?) async {
        currentHomeID = homeId
        self.currentRole = currentRole

        guard let homeId else {
            hasLoaded = true
            canEvaluateSetupState = false
            choreCount = 0
            rewardCount = 0
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            async let chores = repository.fetchTemplates(homeId: homeId, includeArchived: false)
            async let rewards = repository.fetchRewards(homeId: homeId, currentRole: currentRole)
            let loadedCounts = try await (chores.count, rewards.count)
            choreCount = loadedCounts.0
            rewardCount = loadedCounts.1
            hasLoaded = true
            canEvaluateSetupState = true
        } catch {
            hasLoaded = true
            canEvaluateSetupState = false
        }
    }

    func reload() async {
        await load(homeId: currentHomeID, currentRole: currentRole)
    }

    func markCreatedContent() {
        choreCount = max(choreCount, 1)
        hasLoaded = true
        canEvaluateSetupState = true
    }
}

private struct ChoresFirstRunSetupHero: View {
    let onStartSetup: () -> Void
    let onManualSetup: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(HomeyDashboardTheme.selectedSidebarBackground)
                    .frame(width: 118, height: 118)

                Circle()
                    .stroke(HomeyDashboardTheme.warmBrown.opacity(0.18), lineWidth: 1)
                    .frame(width: 148, height: 148)

                Image(systemName: "house.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)

                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.orangeAccent)
                    .offset(x: 50, y: -44)

                Image(systemName: "gift.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.sageAccent)
                    .offset(x: -52, y: 44)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Welcome to Chores")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)

                Text("Ready to set up your home?")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .multilineTextAlignment(.center)

                Text("Homey can help you organize rooms, choose cleaning days, create recurring chores, and set up rewards.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 660)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    benefitItems
                }
                VStack(spacing: 12) {
                    benefitItems
                }
            }
            .frame(maxWidth: 760)

            VStack(spacing: 12) {
                Button {
                    onStartSetup()
                } label: {
                    Label("Set Up Chores & Rewards", systemImage: "sparkles")
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(maxWidth: 360)

                Button {
                    onManualSetup()
                } label: {
                    Text("I'll Set It Up Myself")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(maxWidth: 360, minHeight: 52)
                        .background(HomeyDashboardTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 42)
        .frame(maxWidth: 900)
        .background(
            LinearGradient(
                colors: [
                    HomeyDashboardTheme.cardBackground,
                    HomeyDashboardTheme.selectedSidebarBackground.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.14), radius: 24, x: 0, y: 16)
    }

    @ViewBuilder
    private var benefitItems: some View {
        ChoresFirstRunBenefit(title: "Organize by Room", systemImage: "square.grid.2x2.fill")
        ChoresFirstRunBenefit(title: "Build Cleaning Schedules", systemImage: "calendar.badge.clock")
        ChoresFirstRunBenefit(title: "Create Rewards", systemImage: "gift.fill")
    }
}

private struct ChoresFirstRunBenefit: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 42, height: 42)
                .background(HomeyDashboardTheme.appBackground.opacity(0.72), in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1)
        }
    }
}
