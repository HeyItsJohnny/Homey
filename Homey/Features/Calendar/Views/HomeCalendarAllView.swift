import SwiftUI

struct HomeCalendarAllView: View {
    let homeId: UUID?
    let role: HomeMemberRole?
    let weekStartsOn: Int?
    let timezone: String?
    let members: [HomeMemberDisplay]
    let currentUserId: UUID?
    let onOpenMeals: () -> Void
    let onOpenChores: () -> Void
    let onOpenCalendar: () -> Void
    let onOpenMeal: (PlannedMeal) -> Void

    @StateObject private var viewModel = HomeCalendarAllViewModel()
    @State private var selectedChoreItem: HomeChoreChecklistItemModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Here's what's happening this week")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                if viewModel.isLoading {
                    ProgressView()
                        .tint(HomeyDashboardTheme.warmBrown)
                        .accessibilityLabel("Loading dashboard")
                }
            }

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .padding(12)
                    .dashboardCard(cornerRadius: 16)
            }

            summaryCards
            mainPanels
        }
        .task(id: configurationKey) {
            await viewModel.configure(
                homeId: homeId,
                role: role,
                weekStartsOn: weekStartsOn,
                timezone: timezone,
                members: members,
                currentUserId: currentUserId
            )
        }
        .sheet(item: $selectedChoreItem) { item in
            HomeChoreSubmissionView(
                item: item,
                members: members,
                isSubmitting: viewModel.isSubmitting,
                errorMessage: viewModel.errorMessage,
                onCancel: {
                    selectedChoreItem = nil
                },
                onSubmit: { assigneeUserId in
                    Task {
                        let didSubmit = await viewModel.submitFromHomeBoard(item: item, assigneeUserId: assigneeUserId)
                        if didSubmit {
                            selectedChoreItem = nil
                        }
                    }
                }
            )
        }
    }

    private var configurationKey: String {
        [
            homeId?.uuidString ?? "none",
            role?.rawValue ?? "none",
            "\(weekStartsOn ?? -1)",
            timezone ?? "auto",
            currentUserId?.uuidString ?? "none",
            members.map(\.id.uuidString).joined(separator: ",")
        ].joined(separator: "|")
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                summaryCardViews
            }

            LazyVGrid(columns: compactSummaryColumns, spacing: 14) {
                summaryCardViews
            }
        }
    }

    @ViewBuilder
    private var summaryCardViews: some View {
        HomeAllSummaryCard(
            title: "Meals Planned",
            value: "\(viewModel.mealsPlannedCount)",
            subtitle: "this week",
            systemImage: "fork.knife",
            accentColor: HomeyDashboardTheme.orangeAccent,
            action: onOpenMeals
        )
        .frame(maxWidth: .infinity)

        HomeAllSummaryCard(
            title: "Chores To Do",
            value: "\(viewModel.choresToDoCount)",
            subtitle: "assigned",
            systemImage: "checklist",
            accentColor: HomeyDashboardTheme.softRed,
            action: onOpenChores
        )
        .frame(maxWidth: .infinity)

        HomeAllSummaryCard(
            title: "Events",
            value: "\(viewModel.eventsCount)",
            subtitle: "this week",
            systemImage: "calendar",
            accentColor: HomeyDashboardTheme.lavenderAccent,
            action: onOpenCalendar
        )
        .frame(maxWidth: .infinity)

        HomeAllSummaryCard(
            title: "Points Available",
            value: "\(viewModel.pointBalance)",
            subtitle: "pts",
            systemImage: "star.fill",
            accentColor: HomeyDashboardTheme.sageAccent,
            action: nil
        )
        .frame(maxWidth: .infinity)
    }

    private var compactSummaryColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }

    private var mainPanels: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                HomeAllTodayPanel(
                    title: viewModel.todayTitle,
                    items: viewModel.todayTimelineItems,
                    onOpenMeal: onOpenMeal,
                    onOpenCalendar: onOpenCalendar
                )
                .frame(maxWidth: .infinity, alignment: .top)

                HomeAllChoresPanel(
                    items: viewModel.todayChores,
                    onSelectItem: { selectedChoreItem = $0 },
                    onOpenChores: onOpenChores
                )
                .frame(maxWidth: .infinity, alignment: .top)

                HomeAllWeekOverviewPanel(
                    weekTitle: viewModel.weekTitle,
                    days: viewModel.weekDays(),
                    activity: { viewModel.activity(for: $0) },
                    onOpenCalendar: onOpenCalendar
                )
                .frame(width: 285, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 14) {
                HomeAllTodayPanel(
                    title: viewModel.todayTitle,
                    items: viewModel.todayTimelineItems,
                    onOpenMeal: onOpenMeal,
                    onOpenCalendar: onOpenCalendar
                )

                HomeAllChoresPanel(
                    items: viewModel.todayChores,
                    onSelectItem: { selectedChoreItem = $0 },
                    onOpenChores: onOpenChores
                )

                HomeAllWeekOverviewPanel(
                    weekTitle: viewModel.weekTitle,
                    days: viewModel.weekDays(),
                    activity: { viewModel.activity(for: $0) },
                    onOpenCalendar: onOpenCalendar
                )
            }
        }
    }
}

private struct HomeAllSummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(accentColor)
                .frame(width: 34, height: 34)
                .background(accentColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 112, alignment: .topLeading)
        .dashboardCard(cornerRadius: 22)
    }
}

private struct HomeAllTodayPanel: View {
    let title: String
    let items: [HomeAllTimelineItem]
    let onOpenMeal: (PlannedMeal) -> Void
    let onOpenCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            if items.isEmpty {
                HomeAllEmptyState(systemImage: "sun.max", title: "Nothing scheduled today")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 10) {
                    ForEach(items.prefix(7)) { item in
                        HomeAllTimelineRow(item: item, onOpenMeal: onOpenMeal, onOpenCalendar: onOpenCalendar)
                    }
                }
            }

            Spacer(minLength: 0)

            HomeAllLinkButton(title: "View full day", action: onOpenCalendar)
        }
        .padding(18)
        .frame(minHeight: 380, alignment: .top)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct HomeAllTimelineRow: View {
    let item: HomeAllTimelineItem
    let onOpenMeal: (PlannedMeal) -> Void
    let onOpenCalendar: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                thumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.subtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)

                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(timeText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }
            .padding(10)
            .background(HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accentColor.opacity(0.16))

            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(accentColor)
                    case .failure:
                        icon
                    @unknown default:
                        icon
                    }
                }
            } else {
                icon
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var icon: some View {
        Image(systemName: item.systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(accentColor)
    }

    private var accentColor: Color {
        if let hex = item.accentColorHex, let color = Color(hex: hex) {
            return color
        }

        switch item.kind {
        case .meal:
            return HomeyDashboardTheme.orangeAccent
        case .calendarEvent:
            return HomeyDashboardTheme.lavenderAccent
        }
    }

    private var timeText: String {
        item.isAllDay ? "All day" : Self.timeFormatter.string(from: item.sortDate)
    }

    private func action() {
        switch item.kind {
        case .meal(let plannedMeal):
            onOpenMeal(plannedMeal)
        case .calendarEvent:
            onOpenCalendar()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private struct HomeAllChoresPanel: View {
    let items: [HomeChoreChecklistItemModel]
    let onSelectItem: (HomeChoreChecklistItemModel) -> Void
    let onOpenChores: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chores Due Today")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            if items.isEmpty {
                HomeAllEmptyState(systemImage: "checkmark.circle", title: "No chores due today")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 9) {
                    ForEach(items.prefix(6)) { item in
                        HomeAllChoreRow(item: item) {
                            onSelectItem(item)
                        }
                    }

                    if items.count > 6 {
                        Text("+ \(items.count - 6) more")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }

            Spacer(minLength: 0)

            HomeAllLinkButton(title: "View all chores", action: onOpenChores)
        }
        .padding(18)
        .frame(minHeight: 380, alignment: .top)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct HomeAllChoreRow: View {
    let item: HomeChoreChecklistItemModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                AvatarView(
                    imageURL: item.member?.avatarURL,
                    initials: item.assigneeInitials,
                    size: 34,
                    accentColor: statusColor,
                    borderColor: HomeyDashboardTheme.cardBackground,
                    borderWidth: 2,
                    showsShadow: false,
                    accessibilityLabel: item.assigneeName
                )

                Image(systemName: statusImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(statusColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.assigneeName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)

                    Text(item.occurrence.titleSnapshot)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(statusColor.opacity(0.26), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusImage: String {
        switch item.status {
        case .notStarted:
            return "circle"
        case .needsRedo:
            return "arrow.counterclockwise.circle.fill"
        case .awaitingApproval:
            return "clock.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .notStarted, .needsRedo:
            return HomeyDashboardTheme.softRed
        case .awaitingApproval:
            return HomeyDashboardTheme.orangeAccent
        case .completed:
            return HomeyDashboardTheme.sageAccent
        }
    }
}

private struct HomeAllWeekOverviewPanel: View {
    let weekTitle: String
    let days: [Date]
    let activity: (Date) -> HomeAllDayActivity
    let onOpenCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Upcoming Trips")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(weekTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            HStack(spacing: 7) {
                ForEach(days, id: \.self) { day in
                    HomeAllWeekDayCell(date: day, activity: activity(day))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HomeAllLegendItem(title: "Meals", color: HomeyDashboardTheme.orangeAccent)
                HomeAllLegendItem(title: "Chores", color: HomeyDashboardTheme.softRed)
                HomeAllLegendItem(title: "Events", color: HomeyDashboardTheme.lavenderAccent)
            }

            Spacer(minLength: 0)

            HomeAllLinkButton(title: "Open Calendar", action: onOpenCalendar)
        }
        .padding(18)
        .frame(minHeight: 380, alignment: .top)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct HomeAllWeekDayCell: View {
    let date: Date
    let activity: HomeAllDayActivity

    var body: some View {
        VStack(spacing: 6) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption2.weight(.bold))
                .foregroundStyle(isToday ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Text(Self.dayFormatter.string(from: date))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)

            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    if activity.hasMeals {
                        HomeAllActivityDot(color: HomeyDashboardTheme.orangeAccent)
                    }
                    if activity.hasChores {
                        HomeAllActivityDot(color: HomeyDashboardTheme.softRed)
                    }
                    if activity.hasEvents {
                        HomeAllActivityDot(color: HomeyDashboardTheme.lavenderAccent)
                    }
                }
                .frame(height: 6)
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.vertical, 8)
        .background(isToday ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? HomeyDashboardTheme.warmBrown.opacity(0.32) : HomeyDashboardTheme.softBorder.opacity(0.72), lineWidth: 1)
        }
    }

    private var isToday: Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}

private struct HomeAllActivityDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
    }
}

private struct HomeAllLegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }
}

private struct HomeAllEmptyState: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.65))

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(HomeyDashboardTheme.appBackground.opacity(0.36), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct HomeAllLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "arrow.right")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
        .buttonStyle(.plain)
    }
}
