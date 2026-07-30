import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    @State private var selectedDestination: DashboardDestination = .home
    @State private var isShowingSettingsMenu = false
    @State private var calendarFocusDate: Date?

    var body: some View {
        NavigationSplitView {
            HomeSidebarView(selectedDestination: $selectedDestination)
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } detail: {
            ZStack(alignment: .topTrailing) {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                selectedContent

                SettingsGearButton(
                    selectedDestination: $selectedDestination,
                    isShowingSettingsMenu: $isShowingSettingsMenu
                )
                .padding(.top, 28)
                .padding(.trailing, 34)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: homeService.selectedHomeID) {
            await loadMembersForSelectedHome()
        }
        .task(id: authenticationService.currentUser?.id) {
            await loadInvitationsForAuthenticatedUser()
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedDestination {
        case .home:
            DashboardContentView { focusDate in
                calendarFocusDate = focusDate
                selectedDestination = .calendar
            }
        case .chores:
            ChoresView()
        case .calendar:
            CalendarView(focusDate: calendarFocusDate)
        case .lists:
            ListsView()
        case .meals:
            MealsView()
        case .groceries:
            GroceriesView()
        case .messages:
            MessagesView()
        case .settings:
            SettingsView()
        case .homeSettings:
            HomeSettingsView(
                onClose: {
                    selectedDestination = .home
                },
                onShowCalendarCategories: {
                    selectedDestination = .calendarCategories
                }
            )
        case .calendarCategories:
            CalendarCategoriesView {
                selectedDestination = .homeSettings
            }
        case .members:
            HomeMembersView {
                selectedDestination = .home
            }
        case .myAccount:
            MyAccountView(
                onClose: {
                    selectedDestination = .home
                },
                onShowInvitations: {
                    selectedDestination = .homeInvitations
                }
            )
        case .homeInvitations:
            HomeInvitationsView(
                onClose: {
                    selectedDestination = .myAccount
                },
                onSwitchHome: {
                    selectedDestination = .home
                }
            )
        case .manageHome:
            ManageHomeView()
        case .changeHome:
            NavigationStack {
                HomeSelectionView(restoresStoredSelectionOnAppear: false) {
                    selectedDestination = .home
                }
            }
        }
    }

    private func loadMembersForSelectedHome() async {
        guard let selectedHome = homeService.selectedHome(),
              let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
    }

    private func loadInvitationsForAuthenticatedUser() async {
        guard let userID = authenticationService.currentUser?.id else {
            return
        }

        await homeService.loadMyPendingInvitations(for: userID)
    }
}

private struct DashboardContentView: View {
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var calendarViewModel = DashboardCalendarViewModel()

    var onOpenCalendar: (Date?) -> Void = { _ in }

    private var dashboardMetrics: [DashboardMetric] {
        [
            DashboardMetric(
                title: "Calendar",
                value: "\(calendarViewModel.eventsTodayCount)",
                subtitle: calendarViewModel.eventsTodayCount == 0 ? "No Events Today" : "Events Today",
                systemImage: "calendar",
                accentColor: HomeyDashboardTheme.lavenderAccent
            ),
            DashboardPlaceholderData.metrics[1],
            DashboardPlaceholderData.metrics[2],
            DashboardPlaceholderData.metrics[3]
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DashboardHeader()
                    .padding(.trailing, 78)

                HomeHeroCard()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
                    ForEach(dashboardMetrics) { metric in
                        DashboardMetricCard(metric: metric) {
                            if metric.title == "Calendar" {
                                onOpenCalendar(Date())
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    UpcomingEventsCard(
                        events: calendarViewModel.upcomingEvents,
                        isLoading: calendarViewModel.isLoading,
                        onOpenCalendar: onOpenCalendar
                    )
                    DashboardChoresCard()
                    DashboardGroceriesCard()
                }
            }
            .padding(.leading, 34)
            .padding(.trailing, 34)
            .padding(.top, 34)
            .padding(.bottom, 38)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            calendarViewModel.load(homeId: homeService.selectedHomeID)
        }
        .task(id: homeService.selectedHomeID) {
            calendarViewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                calendarViewModel.reload()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                calendarViewModel.reload()
            }
        }
        .onDisappear {
            Task {
                await calendarViewModel.clear()
            }
        }
    }
}

private struct DashboardHeader: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeGreeting = TimeOfDayGreeting.greeting()

    private var dashboardGreeting: String {
        guard let currentUser = authenticationService.currentUser else {
            return "\(timeGreeting)!"
        }

        return "\(timeGreeting), \(currentUser.preferredDisplayName)!"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dashboardGreeting)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityLabel(dashboardGreeting)

            Text("Here’s what’s happening in your home.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshTimeGreeting()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshTimeGreeting()
            }
        }
    }

    private func refreshTimeGreeting() {
        timeGreeting = TimeOfDayGreeting.greeting()
    }
}

struct HomeSidebarView: View {
    @Binding var selectedDestination: DashboardDestination

    var body: some View {
        ZStack {
            HomeyDashboardTheme.sidebarBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                SidebarLogoView()
                    .padding(.top, 22)

                VStack(spacing: 8) {
                    ForEach(DashboardDestination.sidebarItems) { item in
                        SidebarNavigationRow(
                            item: item,
                            isSelected: selectedDestination == item
                        ) {
                            selectedDestination = item
                        }
                    }
                }

                Spacer(minLength: 24)

                CurrentHomeSidebarCard()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

private struct SidebarLogoView: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HomeyDashboardTheme.warmBeige)
                    .frame(width: 48, height: 48)

                Image(systemName: "house.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }

            Text("homey")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
    }
}

private struct SidebarNavigationRow: View {
    let item: DashboardDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 24)

                Text(item.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))

                Spacer()
            }
            .foregroundStyle(isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(HomeyDashboardTheme.selectedSidebarBackground)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CurrentHomeSidebarCard: View {
    @EnvironmentObject private var homeService: HomeService

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var memberCountText: String {
        guard let selectedHome else {
            return "Choose a Home"
        }

        let count = homeService.memberCountForSelectedHome() ?? selectedHome.memberCount
        return "\(count) \(count == 1 ? "Member" : "Members")"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HomeyDashboardTheme.cardBackground)
                    .frame(width: 46, height: 46)

                Image(systemName: "house.fill")
                    .foregroundStyle(HomeyDashboardTheme.sageAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedHome?.name ?? "No Home Selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(memberCountText)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(12)
        .background(HomeyDashboardTheme.currentHomeBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct SettingsGearButton: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @Binding var selectedDestination: DashboardDestination
    @Binding var isShowingSettingsMenu: Bool
    @State private var isSigningOut = false

    var body: some View {
        Button {
            isShowingSettingsMenu.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 50, height: 50)
                .background(HomeyDashboardTheme.cardBackground, in: Circle())
                .overlay {
                    Circle()
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
                .shadow(color: HomeyDashboardTheme.shadow, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingSettingsMenu, arrowEdge: .top) {
            SettingsMenuView(
                isSigningOut: isSigningOut,
                onHomeSettings: showHomeSettings,
                onMembers: showMembers,
                onMyAccount: showMyAccount,
                onChangeHome: changeHome,
                onSignOut: signOut
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func showHomeSettings() {
        isShowingSettingsMenu = false
        selectedDestination = .homeSettings
    }

    private func showMembers() {
        isShowingSettingsMenu = false
        selectedDestination = .members
    }

    private func showMyAccount() {
        isShowingSettingsMenu = false
        selectedDestination = .myAccount
    }

    private func changeHome() {
        isShowingSettingsMenu = false
        selectedDestination = .changeHome
    }

    private func signOut() {
        guard !isSigningOut else {
            return
        }

        isShowingSettingsMenu = false
        isSigningOut = true

        Task {
            // Reuse the central authentication service and let RootView react to the signed-out session state.
            await authenticationService.signOut()
            isSigningOut = false
        }
    }
}

struct HomeHeroCard: View {
    @EnvironmentObject private var homeService: HomeService

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var members: [HomeMemberDisplay] {
        homeService.membersForSelectedHome()
    }

    private var memberCountText: String {
        guard let selectedHome else {
            return "Choose a Home"
        }

        let count = homeService.memberCountForSelectedHome() ?? selectedHome.memberCount
        return "\(count) \(count == 1 ? "Member" : "Members")"
    }

    var body: some View {
        HStack(spacing: 28) {
            HomeHeroHouseArtwork()

            VStack(alignment: .leading, spacing: 12) {
                Text(selectedHome?.name ?? "No Home Selected")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(memberCountText)
                    .font(.headline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                DashboardMemberAvatarStack(members: members)
                .padding(.top, 2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.7))
        }
        .padding(26)
        .dashboardCard(cornerRadius: 34)
    }
}

private struct HomeHeroHouseArtwork: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Image("home_dashboard_house")
            .resizable()
            .scaledToFit()
            .frame(
                width: horizontalSizeClass == .compact ? 170 : 240,
                height: horizontalSizeClass == .compact ? 125 : 170
            )
            .accessibilityLabel("Laroco Family home")
    }
}

struct DashboardMetricCard: View {
    let metric: DashboardMetric
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(metric.accentColor.opacity(0.20))
                    .frame(width: 46, height: 46)

                Image(systemName: metric.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(metric.accentColor)
            }

            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Text(metric.value)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(metric.subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .dashboardCard(cornerRadius: 26)
        }
        .buttonStyle(.plain)
    }
}

struct DashboardSectionCard<Content: View>: View {
    let title: String
    let actionTitle: String
    var action: () -> Void = {}
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Spacer()

                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .buttonStyle(.plain)
            }

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 360, alignment: .topLeading)
        .dashboardCard(cornerRadius: 28)
    }
}

struct UpcomingEventsCard: View {
    var events: [CalendarEvent] = []
    var isLoading = false
    var onOpenCalendar: (Date?) -> Void = { _ in }

    var body: some View {
        DashboardSectionCard(title: "Upcoming", actionTitle: "View Calendar", action: {
            onOpenCalendar(nil)
        }) {
            VStack(spacing: 0) {
                if isLoading && events.isEmpty {
                    ProgressView()
                        .tint(HomeyDashboardTheme.warmBrown)
                        .frame(maxWidth: .infinity, minHeight: 190)
                        .accessibilityLabel("Loading upcoming events")
                } else if events.isEmpty {
                    UpcomingEventsEmptyState()
                } else {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            onOpenCalendar(event.occurrenceStartsAt)
                        } label: {
                            UpcomingEventRow(event: event)
                        }
                        .buttonStyle(.plain)

                        if index < events.count - 1 {
                            Divider()
                                .overlay(HomeyDashboardTheme.softBorder)
                        }
                    }
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "calendar", title: "View Full Calendar") {
                    onOpenCalendar(nil)
                }
            }
        }
    }
}

private struct UpcomingEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Image(systemName: event.categoryIconName ?? "calendar")
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.7))
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        Color(hex: event.categoryColorHex) ?? HomeyDashboardTheme.lavenderAccent
    }

    private var subtitle: String {
        let dateText = DashboardCalendarFormatters.eventDate.string(from: event.occurrenceStartsAt)
        let timeText = event.isAllDay ? "All Day" : "\(DashboardCalendarFormatters.eventTime.string(from: event.occurrenceStartsAt))"
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if location.isEmpty {
            return "\(dateText) • \(timeText)"
        }

        return "\(dateText) • \(timeText) • \(location)"
    }
}

private struct UpcomingEventsEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(HomeyDashboardTheme.selectedSidebarBackground)
                    .frame(width: 54, height: 54)

                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("No Upcoming Events")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("Nothing is scheduled yet.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardChoresCard: View {
    var body: some View {
        DashboardSectionCard(title: "Chores", actionTitle: "View All") {
            VStack(spacing: 0) {
                ForEach(DashboardPlaceholderData.chores) { chore in
                    ChoreDashboardRow(chore: chore)

                    if chore.id != DashboardPlaceholderData.chores.last?.id {
                        Divider()
                            .overlay(HomeyDashboardTheme.softBorder)
                    }
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "checklist", title: "Go to Chores")
            }
        }
    }
}

private struct ChoreDashboardRow: View {
    let chore: DashboardChore

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(HomeyDashboardTheme.secondaryText.opacity(0.42), lineWidth: 1.7)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Text(chore.dueText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.softRed)
            }

            Spacer()

            AvatarPlaceholderView(initials: chore.initials, color: chore.color, size: 34)
        }
        .padding(.vertical, 13)
    }
}

struct DashboardGroceriesCard: View {
    var body: some View {
        DashboardSectionCard(title: "Groceries", actionTitle: "View List") {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(DashboardPlaceholderData.groceries) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(HomeyDashboardTheme.orangeAccent.opacity(0.18))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(HomeyDashboardTheme.orangeAccent)
                                    }

                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    GroceryBagPlaceholder()
                        .frame(width: 84, height: 108)
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "cart.fill", title: "Go to Grocery List")
            }
        }
    }
}

private struct GroceryBagPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(0.75))

            Image(systemName: "basket.fill")
                .font(.system(size: 42))
                .foregroundStyle(HomeyDashboardTheme.orangeAccent)
        }
    }
}

private struct SoftDashboardButton: View {
    let systemImage: String
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsMenuView: View {
    var isSigningOut = false
    var onHomeSettings: () -> Void = {}
    var onMembers: () -> Void = {}
    var onMyAccount: () -> Void = {}
    var onChangeHome: () -> Void = {}
    var onSignOut: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            SettingsMenuRow(
                title: "Home Settings",
                subtitle: "Edit home name, timezone, and more",
                systemImage: "gearshape",
                action: onHomeSettings
            )
            SettingsMenuRow(
                title: "Members",
                subtitle: "View and manage members",
                systemImage: "person.2",
                action: onMembers
            )
            SettingsMenuRow(
                title: "My Account",
                subtitle: "Profile and personal preferences",
                systemImage: "person.crop.circle",
                action: onMyAccount
            )

            Divider()
                .padding(.vertical, 4)

            SettingsMenuRow(
                title: "Change Home",
                subtitle: "Switch to a different home",
                systemImage: "arrow.left.arrow.right",
                action: onChangeHome
            )

            Divider()
                .padding(.vertical, 4)

            SettingsMenuRow(
                title: "Sign Out",
                subtitle: "Sign out of Homey",
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive,
                isLoading: isSigningOut,
                action: onSignOut
            )
        }
        .padding(12)
        .frame(width: 360)
        .background(HomeyDashboardTheme.cardBackground)
    }
}

private struct SettingsMenuRow: View {
    enum Role {
        case normal
        case destructive
    }

    let title: String
    let subtitle: String
    let systemImage: String
    var role: Role = .normal
    var isLoading = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                        .frame(width: 42, height: 42)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(iconColor)
                    } else {
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(titleColor)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var iconColor: Color {
        role == .destructive ? HomeyDashboardTheme.destructiveRed : HomeyDashboardTheme.warmBrown
    }

    private var titleColor: Color {
        role == .destructive ? HomeyDashboardTheme.destructiveRed : HomeyDashboardTheme.primaryText
    }
}

struct AvatarPlaceholderView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay {
                Circle()
                    .stroke(HomeyDashboardTheme.cardBackground, lineWidth: 3)
            }
    }
}

struct PlaceholderModuleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .padding(40)
            .frame(maxWidth: 420)
            .dashboardCard(cornerRadius: 30)
        }
    }
}

extension View {
    func dashboardCard(cornerRadius: CGFloat) -> some View {
        background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .shadow(color: HomeyDashboardTheme.shadow, radius: 18, x: 0, y: 10)
    }
}

enum DashboardDestination: String, CaseIterable, Identifiable {
    case home
    case chores
    case calendar
    case lists
    case meals
    case groceries
    case messages
    case settings
    case homeSettings
    case calendarCategories
    case members
    case myAccount
    case homeInvitations
    case manageHome
    case changeHome

    var id: String { rawValue }

    static let sidebarItems: [DashboardDestination] = [
        .home,
        .chores,
        .calendar,
        .lists,
        .meals,
        .groceries,
        .messages,
        .settings
    ]

    var title: String {
        switch self {
        case .home:
            "Home"
        case .chores:
            "Chores"
        case .calendar:
            "Calendar"
        case .lists:
            "Lists"
        case .meals:
            "Meals"
        case .groceries:
            "Groceries"
        case .messages:
            "Messages"
        case .settings:
            "Settings"
        case .homeSettings:
            "Home Settings"
        case .calendarCategories:
            "Calendar Categories"
        case .members:
            "Members"
        case .myAccount:
            "My Account"
        case .homeInvitations:
            "Home Invitations"
        case .manageHome:
            "Manage Home"
        case .changeHome:
            "Change Home"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .chores:
            "checklist"
        case .calendar:
            "calendar"
        case .lists:
            "list.bullet.rectangle"
        case .meals:
            "fork.knife"
        case .groceries:
            "cart.fill"
        case .messages:
            "bubble.left.and.bubble.right.fill"
        case .settings:
            "gearshape.fill"
        case .homeSettings:
            "gearshape"
        case .calendarCategories:
            "tag.fill"
        case .members:
            "person.2"
        case .myAccount:
            "person.crop.circle"
        case .homeInvitations:
            "envelope.badge"
        case .manageHome:
            "house"
        case .changeHome:
            "arrow.left.arrow.right"
        }
    }
}

struct DashboardMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
}

private enum DashboardCalendarFormatters {
    static let eventDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let eventTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

struct DashboardEvent: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let systemImage: String
    let statusColor: Color
}

struct DashboardChore: Identifiable {
    let id = UUID()
    let title: String
    let dueText: String
    let initials: String
    let color: Color
}

struct DashboardGroceryItem: Identifiable {
    let id = UUID()
    let name: String
}

struct DashboardMember: Identifiable {
    let id = UUID()
    let initials: String
    let color: Color
}

enum DashboardPlaceholderData {
    static let members = [
        DashboardMember(initials: "JL", color: HomeyDashboardTheme.warmBrown),
        DashboardMember(initials: "ML", color: HomeyDashboardTheme.sageAccent),
        DashboardMember(initials: "AL", color: HomeyDashboardTheme.orangeAccent),
        DashboardMember(initials: "EL", color: HomeyDashboardTheme.lavenderAccent)
    ]

    static let metrics = [
        DashboardMetric(title: "Calendar", value: "2", subtitle: "Events Today", systemImage: "calendar", accentColor: HomeyDashboardTheme.lavenderAccent),
        DashboardMetric(title: "Chores", value: "3", subtitle: "To Do", systemImage: "checklist", accentColor: HomeyDashboardTheme.sageAccent),
        DashboardMetric(title: "Groceries", value: "12", subtitle: "Items", systemImage: "cart.fill", accentColor: HomeyDashboardTheme.coralAccent),
        DashboardMetric(title: "Meals", value: "1", subtitle: "Planned", systemImage: "fork.knife", accentColor: HomeyDashboardTheme.orangeAccent)
    ]

    static let events = [
        DashboardEvent(title: "Dinner with Grandma", time: "Today at 6:00 PM", systemImage: "fork.knife", statusColor: HomeyDashboardTheme.lavenderAccent),
        DashboardEvent(title: "Soccer Practice", time: "Today at 5:30 PM", systemImage: "soccerball", statusColor: HomeyDashboardTheme.sageAccent)
    ]

    static let chores = [
        DashboardChore(title: "Take out the trash", dueText: "Due today", initials: "JL", color: HomeyDashboardTheme.warmBrown),
        DashboardChore(title: "Wipe down countertops", dueText: "Due today", initials: "ML", color: HomeyDashboardTheme.sageAccent),
        DashboardChore(title: "Feed the dog", dueText: "Due today", initials: "AL", color: HomeyDashboardTheme.orangeAccent)
    ]

    static let groceries = [
        DashboardGroceryItem(name: "Milk"),
        DashboardGroceryItem(name: "Eggs"),
        DashboardGroceryItem(name: "Chicken"),
        DashboardGroceryItem(name: "Bananas"),
        DashboardGroceryItem(name: "Apples")
    ]
}

enum HomeyDashboardTheme {
    static let appBackground = Color(red: 0.95, green: 0.91, blue: 0.84)
    static let sidebarBackground = Color(red: 0.92, green: 0.86, blue: 0.76)
    static let cardBackground = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let currentHomeBackground = Color(red: 0.96, green: 0.90, blue: 0.80)
    static let selectedSidebarBackground = Color(red: 0.96, green: 0.89, blue: 0.78)
    static let primaryText = Color(red: 0.25, green: 0.17, blue: 0.11)
    static let secondaryText = Color(red: 0.53, green: 0.48, blue: 0.42)
    static let warmBrown = Color(red: 0.55, green: 0.34, blue: 0.18)
    static let warmBeige = Color(red: 0.88, green: 0.78, blue: 0.64)
    static let sageAccent = Color(red: 0.49, green: 0.62, blue: 0.43)
    static let orangeAccent = Color(red: 0.86, green: 0.55, blue: 0.30)
    static let coralAccent = Color(red: 0.87, green: 0.45, blue: 0.39)
    static let lavenderAccent = Color(red: 0.53, green: 0.48, blue: 0.76)
    static let softRed = Color(red: 0.78, green: 0.29, blue: 0.25)
    static let destructiveRed = Color(red: 0.76, green: 0.20, blue: 0.18)
    static let softBorder = Color(red: 0.78, green: 0.70, blue: 0.60).opacity(0.42)
    static let shadow = Color(red: 0.40, green: 0.28, blue: 0.18).opacity(0.08)
}

#Preview("Home Dashboard - iPad Landscape", traits: .landscapeLeft) {
    HomeDashboardView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}

#Preview("Sidebar") {
    HomeSidebarPreview()
}

private struct HomeSidebarPreview: View {
    @State private var selectedDestination: DashboardDestination = .home

    var body: some View {
        HomeSidebarView(selectedDestination: $selectedDestination)
            .frame(width: 280, height: 820)
    }
}

#Preview("Home Hero Card") {
    HomeHeroCard()
        .padding()
        .background(HomeyDashboardTheme.appBackground)
}

#Preview("Metric Card") {
    DashboardMetricCard(metric: DashboardPlaceholderData.metrics[0])
        .frame(width: 220)
        .padding()
        .background(HomeyDashboardTheme.appBackground)
}

#Preview("Settings Menu") {
    SettingsMenuView()
        .environmentObject(AuthenticationService())
}

#Preview("Upcoming Card") {
    UpcomingEventsCard()
        .frame(width: 360)
        .padding()
        .background(HomeyDashboardTheme.appBackground)
}

#Preview("Chores Card") {
    DashboardChoresCard()
        .frame(width: 360)
        .padding()
        .background(HomeyDashboardTheme.appBackground)
}

#Preview("Groceries Card") {
    DashboardGroceriesCard()
        .frame(width: 360)
        .padding()
        .background(HomeyDashboardTheme.appBackground)
}
