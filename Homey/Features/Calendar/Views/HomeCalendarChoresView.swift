import SwiftUI

struct HomeCalendarChoresView: View {
    @StateObject private var viewModel = HomeCalendarChoresViewModel()
    @State private var selectedItem: HomeChoreChecklistItemModel?
    @State private var scrollToTodayRequest = 0

    let homeId: UUID?
    let role: HomeMemberRole?
    let weekStartsOn: Int?
    let timezone: String?
    let members: [HomeMemberDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeCalendarChoresHeader(
                weekTitle: viewModel.visibleWeekTitle,
                selectedAssignee: viewModel.selectedAssignee,
                members: members,
                isLoading: viewModel.isLoading,
                onPreviousWeek: viewModel.moveToPreviousWeek,
                onNextWeek: viewModel.moveToNextWeek,
                onToday: {
                    viewModel.moveToToday()
                    scrollToTodayRequest += 1
                },
                onSelectAssignee: viewModel.selectAssignee
            )

            if homeId == nil {
                HomeCalendarChoresMessage(
                    title: "Choose a Home",
                    message: "Select a Home before viewing chores.",
                    systemImage: "house.fill"
                )
            } else {
                if let errorMessage = viewModel.errorMessage {
                    HomeCalendarChoresError(message: errorMessage) {
                        Task { await viewModel.reload() }
                    }
                }

                HomeCalendarChoresWeekBoard(
                    days: viewModel.weekDays(),
                    members: members,
                    selectedAssignee: viewModel.selectedAssignee,
                    scrollToTodayRequest: scrollToTodayRequest,
                    choreItems: { day in
                        viewModel.choreItems(on: day, members: members)
                    },
                    onSelectItem: { item in
                        selectedItem = item
                    }
                )

                HomeCalendarChoresFooter(choreCount: viewModel.choreCount(members: members))
            }
        }
        .task(id: loadTaskId) {
            await viewModel.configure(homeId: homeId, role: role, weekStartsOn: weekStartsOn, timezone: timezone)
        }
        .overlay {
            if viewModel.isLoading && viewModel.occurrences.isEmpty {
                ProgressView()
                    .tint(HomeyDashboardTheme.warmBrown)
                    .padding(14)
                    .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                    .shadow(color: HomeyDashboardTheme.shadow, radius: 10, x: 0, y: 6)
                    .accessibilityLabel("Loading chores")
            }
        }
        .sheet(item: $selectedItem) { item in
            HomeChoreSubmissionView(
                item: item,
                members: members,
                isSubmitting: viewModel.isSubmitting,
                errorMessage: viewModel.errorMessage,
                onCancel: { selectedItem = nil },
                onSubmit: { assigneeUserId in
                    Task {
                        let didSubmit = await viewModel.submitFromHomeBoard(
                            item: item,
                            assigneeUserId: assigneeUserId,
                            note: nil
                        )
                        if didSubmit {
                            selectedItem = nil
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var loadTaskId: String {
        "\(homeId?.uuidString ?? "no-home")-\(role?.rawValue ?? "no-role")-\(weekStartsOn ?? -1)-\(timezone ?? "")"
    }
}

private struct HomeCalendarChoresHeader: View {
    let weekTitle: String
    let selectedAssignee: HomeChoreAssigneeFilter
    let members: [HomeMemberDisplay]
    let isLoading: Bool
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void
    let onSelectAssignee: (HomeChoreAssigneeFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    periodControls
                    Spacer(minLength: 18)
                    actions
                }

                VStack(alignment: .leading, spacing: 14) {
                    periodControls
                    actions
                }
            }

            assigneeStrip
        }
        .padding(18)
        .dashboardCard(cornerRadius: 26)
    }

    private var periodControls: some View {
        HStack(spacing: 10) {
            iconButton(systemImage: "chevron.left", label: "Previous week", action: onPreviousWeek)

            VStack(alignment: .leading, spacing: 3) {
                Text("This Week's Chores")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(weekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            iconButton(systemImage: "chevron.right", label: "Next week", action: onNextWeek)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Today", action: onToday)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to today")

            Menu {
                Button("All Assignees") { onSelectAssignee(.all) }
                ForEach(members) { member in
                    Button(member.displayName) { onSelectAssignee(.member(member.userId)) }
                }
                Button("Anyone") { onSelectAssignee(.anyone) }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedAssigneeTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Assignee filter, \(selectedAssigneeTitle)")

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyDashboardTheme.warmBrown)
            }
        }
    }

    private var assigneeStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                HomeCalendarChoreAssigneeChip(
                    title: "All",
                    initials: "A",
                    avatarURL: nil,
                    isSelected: selectedAssignee == .all
                ) {
                    onSelectAssignee(.all)
                }

                ForEach(members) { member in
                    HomeCalendarChoreAssigneeChip(
                        title: member.displayName,
                        initials: member.initials,
                        avatarURL: member.avatarURL,
                        isSelected: selectedAssignee == .member(member.userId)
                    ) {
                        onSelectAssignee(.member(member.userId))
                    }
                }

                HomeCalendarChoreAssigneeChip(
                    title: "Anyone",
                    initials: "?",
                    avatarURL: nil,
                    isSelected: selectedAssignee == .anyone
                ) {
                    onSelectAssignee(.anyone)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(HomeyDashboardTheme.warmBrown)
        .background(HomeyDashboardTheme.cardBackground, in: Circle())
        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        .accessibilityLabel(label)
    }

    private var selectedAssigneeTitle: String {
        switch selectedAssignee {
        case .all:
            return "All Assignees"
        case .member(let userId):
            return members.first { $0.userId == userId }?.displayName ?? "Assignee"
        case .anyone:
            return "Anyone"
        }
    }
}

private struct HomeCalendarChoreAssigneeChip: View {
    let title: String
    let initials: String
    let avatarURL: URL?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AvatarView(
                    imageURL: avatarURL,
                    initials: initials,
                    size: 42,
                    accentColor: isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText,
                    borderColor: isSelected ? HomeyDashboardTheme.warmBrown.opacity(0.42) : HomeyDashboardTheme.cardBackground,
                    borderWidth: isSelected ? 2 : 1,
                    showsShadow: false,
                    accessibilityLabel: "\(title) avatar"
                )

                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 62)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(isSelected ? HomeyDashboardTheme.selectedSidebarBackground : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter chores by \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HomeCalendarChoresWeekBoard: View {
    let days: [Date]
    let members: [HomeMemberDisplay]
    let selectedAssignee: HomeChoreAssigneeFilter
    let scrollToTodayRequest: Int
    let choreItems: (Date) -> [HomeChoreChecklistItemModel]
    let onSelectItem: (HomeChoreChecklistItemModel) -> Void

    private let dayColumnWidth: CGFloat = 184
    private let dayColumnMinHeight: CGFloat = 520
    private let columnSpacing: CGFloat = 10

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(days, id: \.self) { day in
                        HomeCalendarChoresDayColumn(
                            date: day,
                            items: choreItems(day),
                            onSelectItem: onSelectItem
                        )
                        .frame(width: dayColumnWidth, alignment: .top)
                        .frame(minHeight: dayColumnMinHeight, alignment: .top)
                        .id(day)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                positionWeeklyBoard(proxy: proxy)
            }
            .onChange(of: daysKey) { _, _ in
                positionWeeklyBoard(proxy: proxy)
            }
            .onChange(of: scrollToTodayRequest) { _, _ in
                scrollToToday(proxy: proxy, animated: true)
            }
        }
        .dashboardCard(cornerRadius: 26)
    }

    private var daysKey: String {
        days
            .map { Self.dayIdFormatter.string(from: $0) }
            .joined(separator: "|")
    }

    private func positionWeeklyBoard(proxy: ScrollViewProxy) {
        guard let firstDay = days.first else { return }

        if let target = todayInDisplayedWeek {
            proxy.scrollTo(target.date, anchor: scrollAnchor(forTodayAt: target.index))
        } else {
            proxy.scrollTo(firstDay, anchor: .leading)
        }
    }

    private func scrollToToday(proxy: ScrollViewProxy, animated: Bool) {
        guard let target = todayInDisplayedWeek else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(target.date, anchor: scrollAnchor(forTodayAt: target.index))
            }
        } else {
            proxy.scrollTo(target.date, anchor: scrollAnchor(forTodayAt: target.index))
        }
    }

    private var todayInDisplayedWeek: (date: Date, index: Int)? {
        guard let match = days.enumerated().first(where: { _, day in
            Calendar.autoupdatingCurrent.isDateInToday(day)
        }) else {
            return nil
        }

        return (date: match.element, index: match.offset)
    }

    private func scrollAnchor(forTodayAt index: Int) -> UnitPoint {
        switch index {
        case 0...1:
            return .leading
        case 5...6:
            return .trailing
        default:
            return .center
        }
    }

    private static let dayIdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct HomeCalendarChoresDayColumn: View {
    let date: Date
    let items: [HomeChoreChecklistItemModel]
    let onSelectItem: (HomeChoreChecklistItemModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeCalendarChoresDayHeader(date: date)

            if sections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.65))
                    Text("No chores")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .background(HomeyDashboardTheme.appBackground.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(sections) { section in
                    HomeCalendarChoreAssigneeSection(section: section, onSelectItem: onSelectItem)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(HomeyDashboardTheme.appBackground.opacity(0.38), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.78), lineWidth: 1)
        }
    }

    private var sections: [HomeCalendarChoreAssigneeSectionModel] {
        let grouped = Dictionary(grouping: items, by: \.assigneeName)
        return grouped
            .map { name, items in
                HomeCalendarChoreAssigneeSectionModel(name: name, items: items.sorted())
            }
            .sorted { first, second in
                if first.name == "Anyone" { return false }
                if second.name == "Anyone" { return true }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
    }
}

private struct HomeCalendarChoresDayHeader: View {
    let date: Date

    var body: some View {
        VStack(spacing: 3) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Text(Self.dayFormatter.string(from: date))
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)

            Text(isToday ? "Today" : " ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(isToday ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.cardBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? HomeyDashboardTheme.warmBrown.opacity(0.38) : HomeyDashboardTheme.softBorder.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var isToday: Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}

private struct HomeCalendarChoreAssigneeSectionModel: Identifiable {
    let name: String
    let items: [HomeChoreChecklistItemModel]

    var id: String { name }
}

private struct HomeCalendarChoreAssigneeSection: View {
    let section: HomeCalendarChoreAssigneeSectionModel
    let onSelectItem: (HomeChoreChecklistItemModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(section.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.items) { item in
                    HomeCalendarChoreChecklistItem(item: item) {
                        onSelectItem(item)
                    }
                }
            }
        }
    }
}

private struct HomeCalendarChoreChecklistItem: View {
    let item: HomeChoreChecklistItemModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 7) {
                statusIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.occurrence.titleSnapshot)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: false)

                    Text(item.roomName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if item.status.requiresStatusCaption {
                        Text(item.status.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(statusColor.opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(item.status == .completed ? 0.72 : 1)
        .accessibilityLabel("\(item.assigneeName), \(item.occurrence.titleSnapshot), \(item.roomName), \(item.status.title)")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundStyle(statusColor)
        case .needsRedo:
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(statusColor)
        case .awaitingApproval:
            Image(systemName: "clock.fill")
                .foregroundStyle(statusColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(statusColor)
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

private struct HomeCalendarChoresFooter: View {
    let choreCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(choreCountText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Spacer(minLength: 12)

            HomeCalendarChoreLegendItem(systemImage: "circle", title: "Not Started", color: HomeyDashboardTheme.softRed)
            HomeCalendarChoreLegendItem(systemImage: "clock.fill", title: "Awaiting Approval", color: HomeyDashboardTheme.orangeAccent)
            HomeCalendarChoreLegendItem(systemImage: "checkmark.circle.fill", title: "Completed", color: HomeyDashboardTheme.sageAccent)
        }
        .padding(14)
        .dashboardCard(cornerRadius: 22)
    }

    private var choreCountText: String {
        "\(choreCount) \(choreCount == 1 ? "chore" : "chores") this week"
    }
}

private struct HomeCalendarChoreLegendItem: View {
    let systemImage: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .lineLimit(1)
    }
}

struct HomeChoreSubmissionView: View {
    let item: HomeChoreChecklistItemModel
    let members: [HomeMemberDisplay]
    let isSubmitting: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSubmit: (UUID) -> Void

    @State private var selectedOpenAssigneeUserId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .center, spacing: 18) {
                        header

                        if item.assigneeUserId == nil {
                            openAssigneePicker
                        }

                        if item.status.canSubmitFromHomeBoard {
                            submissionForm
                        } else {
                            readOnlyStatus
                        }

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                }
            }
            .onAppear {
                if selectedOpenAssigneeUserId == nil {
                    selectedOpenAssigneeUserId = members.first?.userId
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                statusIcon
                    .font(.title2.weight(.semibold))
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.occurrence.titleSnapshot)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Assigned to \(assigneeName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)

                    Text(Self.dueFormatter.string(from: item.occurrence.dueAt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
            }

            if item.occurrence.pointsValue > 0 {
                Label("\(item.occurrence.pointsValue) \(item.occurrence.pointsValue == 1 ? "point" : "points")", systemImage: "star.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
        }
        .padding(18)
        .dashboardCard(cornerRadius: 22)
        .frame(maxWidth: 430)
    }

    private var submissionForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Completed?")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                Button {
                    guard let assigneeUserId = resolvedAssigneeUserId else {
                        return
                    }
                    onSubmit(assigneeUserId)
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Yes")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(isSubmitting || resolvedAssigneeUserId == nil)
                .accessibilityLabel("Yes, submit chore as completed")

                Button("No", action: onCancel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .accessibilityLabel("No, close")
            }
        }
        .padding(18)
        .dashboardCard(cornerRadius: 22)
        .frame(maxWidth: 430)
    }

    private var openAssigneePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who completed this?")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Picker("Household member", selection: Binding(
                get: { selectedOpenAssigneeUserId ?? members.first?.userId },
                set: { selectedOpenAssigneeUserId = $0 }
            )) {
                ForEach(members) { member in
                    Text(member.displayName).tag(Optional(member.userId))
                }
            }
            .pickerStyle(.menu)
            .disabled(members.isEmpty)
        }
        .padding(18)
        .dashboardCard(cornerRadius: 22)
        .frame(maxWidth: 430)
    }

    private var readOnlyStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.status.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(statusColor)

            Text(readOnlyMessage)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .dashboardCard(cornerRadius: 22)
        .frame(maxWidth: 430)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundStyle(statusColor)
        case .needsRedo:
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(statusColor)
        case .awaitingApproval:
            Image(systemName: "clock.fill")
                .foregroundStyle(statusColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(statusColor)
        }
    }

    private var resolvedAssigneeUserId: UUID? {
        item.assigneeUserId ?? selectedOpenAssigneeUserId
    }

    private var assigneeName: String {
        if let assigneeUserId = resolvedAssigneeUserId,
           let member = members.first(where: { $0.userId == assigneeUserId }) {
            return member.displayName
        }
        return item.assigneeName
    }

    private var navigationTitle: String {
        item.status.canSubmitFromHomeBoard ? "Complete Chore" : "Chore Details"
    }

    private var readOnlyMessage: String {
        switch item.status {
        case .notStarted, .needsRedo:
            return ""
        case .awaitingApproval:
            return "This chore is waiting for approval. Approvals are handled in the Chores module."
        case .completed:
            return "This chore has already been completed."
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

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d, h:mm a")
        return formatter
    }()
}

private struct HomeCalendarChoresMessage: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 42, height: 42)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            Spacer()
        }
        .padding(18)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct HomeCalendarChoresError: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeyDashboardTheme.orangeAccent)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.footnote.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
    }
}
