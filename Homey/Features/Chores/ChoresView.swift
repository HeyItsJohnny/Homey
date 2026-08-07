import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: ChoresTab = .myChores
    @State private var isPresentingAddChore = false
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

    private var selectedHomeID: UUID? {
        homeService.selectedHomeID
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
                    ChoresTabSelector(tabs: visibleTabs, selectedTab: $selectedTab)
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
        .sheet(isPresented: $isPresentingAddChore) {
            ChoreEditorView(homeId: selectedHomeID, timezone: selectedHomeTimezone)
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

            if canManageChores {
                Button {
                    isPresentingAddChore = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                        Text("Add Chore")
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 150)
                .accessibilityLabel("Add Chore")
                .accessibilityHint("Owner and admin action")
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .myChores:
            MyChoresView()
        case .myRewards:
            MyRewardsView()
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
}

// Future chore records will link to Homey calendar events. The chore record will remain the source of truth for assignment, completion, approval, and points, while the calendar event represents scheduling.
