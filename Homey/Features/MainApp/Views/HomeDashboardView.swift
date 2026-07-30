import SwiftUI

struct HomeDashboardView: View {
    @State private var selectedDestination: DashboardDestination = .home
    @State private var isShowingSettingsMenu = false

    var body: some View {
        NavigationSplitView {
            HomeSidebarView(selectedDestination: $selectedDestination)
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } detail: {
            ZStack(alignment: .topTrailing) {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                selectedContent

                SettingsGearButton(isShowingSettingsMenu: $isShowingSettingsMenu)
                    .padding(.top, 28)
                    .padding(.trailing, 34)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedDestination {
        case .home:
            DashboardContentView()
        case .chores:
            ChoresView()
        case .calendar:
            CalendarView()
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
            HomeSettingsView()
        case .members:
            MembersView()
        case .manageHome:
            ManageHomeView()
        case .changeHome:
            ChangeHomeView()
        }
    }
}

private struct DashboardContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                DashboardHeader()
                    .padding(.trailing, 78)

                HomeHeroCard()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 4), spacing: 18) {
                    ForEach(DashboardPlaceholderData.metrics) { metric in
                        DashboardMetricCard(metric: metric)
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    UpcomingEventsCard()
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
    }
}

private struct DashboardHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Good morning, Johnny! 👋")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Here’s what’s happening in your home.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Laroco Family")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("4 Members")
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
    @Binding var isShowingSettingsMenu: Bool

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
            SettingsMenuView()
                .presentationCompactAdaptation(.popover)
        }
    }
}

struct HomeHeroCard: View {
    var body: some View {
        HStack(spacing: 26) {
            HomeIllustrationPlaceholder()
                .frame(width: 156, height: 128)

            VStack(alignment: .leading, spacing: 12) {
                Text("Laroco Family")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("4 Members")
                    .font(.headline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                HStack(spacing: -8) {
                    ForEach(DashboardPlaceholderData.members) { member in
                        AvatarPlaceholderView(initials: member.initials, color: member.color)
                    }
                }
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

private struct HomeIllustrationPlaceholder: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(0.85))

            Circle()
                .fill(HomeyDashboardTheme.sageAccent.opacity(0.28))
                .frame(width: 74, height: 74)
                .offset(x: -36, y: -30)

            Circle()
                .fill(HomeyDashboardTheme.orangeAccent.opacity(0.22))
                .frame(width: 62, height: 62)
                .offset(x: 42, y: -18)

            Image(systemName: "house.fill")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .offset(y: -30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

struct DashboardMetricCard: View {
    let metric: DashboardMetric

    var body: some View {
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
}

struct DashboardSectionCard<Content: View>: View {
    let title: String
    let actionTitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Spacer()

                Button(actionTitle) {}
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
    var body: some View {
        DashboardSectionCard(title: "Upcoming", actionTitle: "View Calendar") {
            VStack(spacing: 0) {
                ForEach(DashboardPlaceholderData.events) { event in
                    UpcomingEventRow(event: event)

                    if event.id != DashboardPlaceholderData.events.last?.id {
                        Divider()
                            .overlay(HomeyDashboardTheme.softBorder)
                    }
                }

                Spacer(minLength: 16)

                SoftDashboardButton(systemImage: "calendar", title: "View Full Calendar")
            }
        }
    }
}

private struct UpcomingEventRow: View {
    let event: DashboardEvent

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(event.statusColor)
                .frame(width: 9, height: 9)

            Image(systemName: event.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(event.time)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.7))
        }
        .padding(.vertical, 15)
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

    var body: some View {
        Button {} label: {
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
    var body: some View {
        VStack(spacing: 8) {
            SettingsMenuRow(
                title: "Home Settings",
                subtitle: "Edit home name, timezone, and more",
                systemImage: "gearshape"
            )
            SettingsMenuRow(
                title: "Members",
                subtitle: "View and manage members",
                systemImage: "person.2"
            )
            SettingsMenuRow(
                title: "Manage Home",
                subtitle: "Home preferences and defaults",
                systemImage: "house"
            )

            Divider()
                .padding(.vertical, 4)

            SettingsMenuRow(
                title: "Change Home",
                subtitle: "Switch to a different home",
                systemImage: "arrow.left.arrow.right"
            )

            Divider()
                .padding(.vertical, 4)

            SettingsMenuRow(
                title: "Sign Out",
                subtitle: "Sign out of Homey",
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive
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

    var body: some View {
        Button {} label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(iconColor)
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
    case members
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
        case .members:
            "Members"
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
        case .members:
            "person.2"
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

#Preview("Home Dashboard - iPad Landscape") {
    HomeDashboardView()
        .previewInterfaceOrientation(.landscapeLeft)
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
