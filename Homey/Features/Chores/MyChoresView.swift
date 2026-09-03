import Combine
import SwiftUI

struct MyChoresView: View {
    @EnvironmentObject private var homeService: HomeService
    @EnvironmentObject private var authenticationService: AuthenticationService
    @StateObject private var viewModel = MyChoresViewModel()
    @State private var selectedOccurrence: MyChoresOccurrenceSelection?
    @State private var scrollToTodayRequest = 0
    @State private var expandedAssigneeSectionKeys: Set<MyChoresDayAssigneeExpansionKey> = []
    @State private var isPresentingReschedule = false

    private var currentRole: HomeMemberRole? {
        homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private var canViewAllChores: Bool {
        currentRole == .owner || currentRole == .admin
    }

    private var moduleTitle: String {
        canViewAllChores ? "All Chores" : "My Chores"
    }

    private var sectionDescription: String {
        canViewAllChores
        ? "View household chores, filter by member, and stay on top of what needs to be completed."
        : "View your assigned chores, track your progress, and stay on top of what needs to be completed."
    }

    private var homeMembers: [HomeMemberDisplay] {
        homeService.membersForSelectedHome()
    }

    var body: some View {
        ChoreShellCard(title: moduleTitle, systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 18) {
                ChoreSectionDescriptionHeader(
                    title: moduleTitle,
                    description: sectionDescription
                )

                VStack(alignment: .leading, spacing: 14) {
                    weeklyHeader

                    if viewModel.isLoading && viewModel.occurrences.isEmpty {
                        ChoreLoadingState(message: "Loading your chores...")
                    } else if let errorMessage = viewModel.errorMessage {
                        ChoreMessageState(
                            title: "Unable to Load Chores",
                            message: errorMessage,
                            systemImage: "exclamationmark.triangle.fill",
                            buttonTitle: "Try Again"
                        ) {
                            viewModel.reload()
                        }
                    } else {
                        if canViewAllChores {
                            MyChoresAssigneeFilterStrip(
                                selectedAssignee: viewModel.selectedAssignee,
                                members: homeMembers,
                                onSelectAssignee: viewModel.selectAssignee
                            )
                        }

                        weeklyPlanner
                        MyChoresWeekSummaryCard(summary: viewModel.summary)
                    }
                }
            }
        }
        .onAppear {
            viewModel.resetAssigneeFilter()
        }
        .gesture(
            DragGesture(minimumDistance: 36)
                .onEnded { value in
                    if value.translation.width < -50 {
                        viewModel.moveToNextWeek()
                    } else if value.translation.width > 50 {
                        viewModel.moveToPreviousWeek()
                    }
                }
        )
        .task(id: loadTaskID) {
            let selectedHome = homeService.selectedHome()
            await viewModel.configure(
                homeId: homeService.selectedHomeID,
                currentUserId: authenticationService.currentUser?.id,
                currentRole: currentRole,
                weekStartsOn: selectedHome?.weekStartsOn,
                timezone: selectedHome?.timezone
            )
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
        .sheet(item: $selectedOccurrence) { selection in
            ChoreOccurrenceDetailView(
                initialOccurrence: selection.occurrence,
                homeTimezone: homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier,
                targetAssigneeUserId: selection.assigneeUserId
            )
        }
        .sheet(isPresented: $isPresentingReschedule) {
            if let sourceWeek = viewModel.rescheduleSourceWeek {
                MyChoresRescheduleSheet(sourceWeek: sourceWeek) { result, destinationStart in
                    isPresentingReschedule = false
                    expandedAssigneeSectionKeys.removeAll()
                    viewModel.moveToWeek(containing: destinationStart)
                    NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
                    NotificationCenter.default.post(
                        name: .homeyCalendarEventsDidChange,
                        object: nil,
                        userInfo: [HomeyCalendarRefreshReason.userInfoKey: HomeyCalendarRefreshReason.choreEditSaved]
                    )
                    _ = result
                }
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
            } else {
                ChoreMessageState(
                    title: "Unable to Reschedule",
                    message: "Choose a Home before rescheduling chores.",
                    systemImage: "calendar.badge.exclamationmark"
                )
                .padding(24)
            }
        }
    }

    private var loadTaskID: String {
        let selectedHome = homeService.selectedHome()
        return "\(homeService.selectedHomeID?.uuidString ?? "no-home")-\(authenticationService.currentUser?.id.uuidString ?? "no-user")-\(currentRole?.rawValue ?? "no-role")-\(selectedHome?.weekStartsOn ?? -1)-\(selectedHome?.timezone ?? "")"
    }

    private var weeklyHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                viewModel.moveToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .background(HomeyDashboardTheme.cardBackground, in: Circle())
            .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            .accessibilityLabel("Previous week")

            VStack(alignment: .leading, spacing: 2) {
                Text("This Week")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(viewModel.visibleWeekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            Button {
                viewModel.moveToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .background(HomeyDashboardTheme.cardBackground, in: Circle())
            .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            .accessibilityLabel("Next week")

            Spacer()

            if canViewAllChores {
                Button {
                    isPresentingReschedule = true
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.clock")
                        .labelStyle(.titleAndIcon)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)
                .accessibilityLabel("Reschedule chores")
            }

            Text("\(viewModel.plannedChoreCount) Chores")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Button("Today") {
                viewModel.moveToToday()
                scrollToTodayRequest += 1
            }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to today")
        }
    }

    private var weeklyPlanner: some View {
        let sections = viewModel.daySections(members: homeMembers)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(sections) { section in
                        MyChoresDayColumn(
                            section: section,
                            isToday: viewModel.isToday(section.date),
                            isSelected: viewModel.isSelectedDay(section.date),
                            expandedAssigneeSectionKeys: $expandedAssigneeSectionKeys,
                            onSelectDay: { viewModel.selectDay(section.date) },
                            onSelectOccurrence: { selectedOccurrence = $0 }
                        )
                        .frame(width: 210, alignment: .top)
                        .id(section.date)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityLabel("Weekly chore planner")
            .onAppear {
                positionWeeklyPlanner(proxy: proxy, sections: sections)
            }
            .onChange(of: weekSectionsKey(sections)) { _, _ in
                expandedAssigneeSectionKeys.removeAll()
                positionWeeklyPlanner(proxy: proxy, sections: sections)
            }
            .onChange(of: scrollToTodayRequest) { _, _ in
                scrollWeeklyPlannerToToday(proxy: proxy, sections: sections, animated: true)
            }
            .onChange(of: viewModel.selectedAssignee) { _, _ in
                expandedAssigneeSectionKeys.removeAll()
            }
        }
    }

    private func positionWeeklyPlanner(proxy: ScrollViewProxy, sections: [MyChoresDaySectionModel]) {
        guard let firstDay = sections.first?.date else { return }

        if let target = todayInWeek(sections) {
            proxy.scrollTo(target.date, anchor: weeklyPlannerAnchor(forTodayAt: target.index))
        } else {
            proxy.scrollTo(firstDay, anchor: .leading)
        }
    }

    private func scrollWeeklyPlannerToToday(proxy: ScrollViewProxy, sections: [MyChoresDaySectionModel], animated: Bool) {
        guard let target = todayInWeek(sections) else {
            return
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(target.date, anchor: weeklyPlannerAnchor(forTodayAt: target.index))
            }
        } else {
            proxy.scrollTo(target.date, anchor: weeklyPlannerAnchor(forTodayAt: target.index))
        }
    }

    private func todayInWeek(_ sections: [MyChoresDaySectionModel]) -> (date: Date, index: Int)? {
        guard let match = sections.enumerated().first(where: { _, section in
            Calendar.autoupdatingCurrent.isDateInToday(section.date)
        }) else {
            return nil
        }

        return (date: match.element.date, index: match.offset)
    }

    private func weeklyPlannerAnchor(forTodayAt index: Int) -> UnitPoint {
        switch index {
        case 0...1:
            return .leading
        case 5...6:
            return .trailing
        default:
            return .center
        }
    }

    private func weekSectionsKey(_ sections: [MyChoresDaySectionModel]) -> String {
        sections
            .map { Self.weekDayIdFormatter.string(from: $0.date) }
            .joined(separator: "|")
    }

    private static let weekDayIdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct MyChoresAssigneeFilterStrip: View {
    let selectedAssignee: HomeChoreAssigneeFilter
    let members: [HomeMemberDisplay]
    let onSelectAssignee: (HomeChoreAssigneeFilter) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                MyChoresAssigneeChip(
                    title: "All",
                    initials: "A",
                    avatarURL: nil,
                    isSelected: selectedAssignee == .all
                ) {
                    onSelectAssignee(.all)
                }

                ForEach(members) { member in
                    MyChoresAssigneeChip(
                        title: member.displayName,
                        initials: member.initials,
                        avatarURL: member.avatarURL,
                        isSelected: selectedAssignee == .member(member.userId)
                    ) {
                        onSelectAssignee(.member(member.userId))
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MyChoresAssigneeChip: View {
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

private struct MyChoresRescheduleSourceWeek {
    let homeId: UUID
    let sourceStart: Date
    let sourceEnd: Date
    let defaultNewStart: Date
    let timezone: String
    let calendar: Calendar

    var sourceRangeText: String {
        Self.rangeText(from: sourceStart, through: sourceEnd, calendar: calendar)
    }

    func generateThrough(for newStart: Date) -> Date {
        let basis = max(Date(), newStart)
        return calendar.date(byAdding: .day, value: ChoresRepository.defaultGenerationWindowDays, to: basis) ?? basis
    }

    static func rangeText(from start: Date, through end: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        if calendar.component(.year, from: start) == calendar.component(.year, from: end) {
            formatter.dateFormat = calendar.component(.month, from: start) == calendar.component(.month, from: end) ? "MMM d" : "MMM d"
            let startText = formatter.string(from: start)
            formatter.dateFormat = "MMM d"
            return "\(startText) - \(formatter.string(from: end))"
        }

        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct MyChoresRescheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sourceWeek: MyChoresRescheduleSourceWeek
    let onComplete: (ChoreRescheduleResult, Date) -> Void

    @State private var selectedMode: ChoreRescheduleMode = .restartSchedule
    @State private var newStartDate: Date
    @State private var preview: ChoreReschedulePreview?
    @State private var errorMessage: String?
    @State private var isPreviewing = false
    @State private var isExecuting = false
    @State private var isConfirmingExecution = false
    @State private var previewRequestId = UUID()

    private let repository: ChoresRepository
    private let calendarSyncService: ChoreCalendarSyncService

    init(
        sourceWeek: MyChoresRescheduleSourceWeek,
        onComplete: @escaping (ChoreRescheduleResult, Date) -> Void
    ) {
        self.sourceWeek = sourceWeek
        self.onComplete = onComplete
        let repository = ChoresRepository()
        self.repository = repository
        self.calendarSyncService = ChoreCalendarSyncService(choresRepository: repository)
        _newStartDate = State(initialValue: sourceWeek.defaultNewStart)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        introSection
                        modeSection
                        sourceSection
                        dateSection
                        explanationSection
                        previewSection
                        actionSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Reschedule Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isPreviewing || isExecuting)
                }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: $isConfirmingExecution,
                titleVisibility: .visible
            ) {
                Button("\(confirmationActionVerb) \(preview?.eligibleCount ?? 0) Chores", role: .destructive) {
                    Task { await executeReschedule() }
                }
                .disabled(isExecuting || preview?.eligibleCount ?? 0 == 0)

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .task(id: previewRequestId) {
                await loadPreviewForCurrentSelection()
            }
        }
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What would you like to do?")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Preview uses the backend reschedule rules, so protected chores stay on their original dates.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeSection: some View {
        VStack(spacing: 10) {
            ForEach(ChoreRescheduleMode.allCases) { mode in
                Button {
                    selectedMode = mode
                    schedulePreviewRefresh()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(selectedMode == mode ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)

                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selectedMode == mode ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.cardBackground,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(selectedMode == mode ? HomeyDashboardTheme.warmBrown.opacity(0.42) : HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Schedule")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .textCase(.uppercase)

            Text(sourceWeek.sourceRangeText)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Start Date")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .textCase(.uppercase)

            DatePicker(
                "New Start Date",
                selection: Binding(
                    get: { newStartDate },
                    set: { date in
                        newStartDate = sourceWeek.calendar.startOfDay(for: date)
                        schedulePreviewRefresh()
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }

    private var explanationSection: some View {
        Text("Chores keep their relative spacing. A Friday chore stays Friday when moving the schedule forward one week.")
            .font(.caption)
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(preview.eligibleCount) \(preview.eligibleCount == 1 ? "chore" : "chores") will move")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("\(preview.protectedCount) \(preview.protectedCount == 1 ? "chore" : "chores") will stay where they are")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                Text("Destination: \(MyChoresRescheduleSourceWeek.rangeText(from: preview.destinationStart, through: preview.destinationEnd, calendar: sourceWeek.calendar))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)

                if preview.eligibleCount == 0 {
                    Text("No untouched chores are available to reschedule in this week.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Chores already started, submitted, awaiting approval, needing redo, completed, skipped, cancelled, or otherwise acted on stay on their original dates.")
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            Button {
                schedulePreviewRefresh()
            } label: {
                HStack(spacing: 8) {
                    if isPreviewing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "eye.fill")
                    }
                    Text(isPreviewing ? "Previewing..." : "Preview Reschedule")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isPreviewing || isExecuting)

            Button {
                isConfirmingExecution = true
            } label: {
                HStack(spacing: 8) {
                    if isExecuting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "calendar.badge.clock")
                    }
                    Text(isExecuting ? "Rescheduling..." : "Continue")
                }
                .frame(maxWidth: .infinity)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(minHeight: 44)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .buttonStyle(.plain)
            .disabled(isPreviewing || isExecuting || preview == nil || preview?.eligibleCount == 0)
        }
    }

    private var confirmationTitle: String {
        switch selectedMode {
        case .moveUnstarted:
            return "Move \(preview?.eligibleCount ?? 0) chores?"
        case .restartSchedule:
            return "Restart \(preview?.eligibleCount ?? 0) chores?"
        }
    }

    private var confirmationActionVerb: String {
        switch selectedMode {
        case .moveUnstarted:
            return "Move"
        case .restartSchedule:
            return "Restart"
        }
    }

    private var confirmationMessage: String {
        let eligibleCount = preview?.eligibleCount ?? 0
        let protectedCount = preview?.protectedCount ?? 0
        let destinationStartText = MyChoresRescheduleSourceWeek.dayText(newStartDate, calendar: sourceWeek.calendar)

        switch selectedMode {
        case .moveUnstarted:
            return "\(eligibleCount) untouched chore occurrences will move. Existing recurring schedules will remain unchanged. \(protectedCount) protected chores will stay where they are."
        case .restartSchedule:
            return "\(eligibleCount) untouched chores will move and their future recurring schedules will continue from \(destinationStartText). \(protectedCount) protected chores will stay where they are."
        }
    }

    private func schedulePreviewRefresh() {
        preview = nil
        errorMessage = nil
        previewRequestId = UUID()
    }

    private func loadPreviewForCurrentSelection() async {
        let requestId = previewRequestId
        guard !isExecuting else { return }
        isPreviewing = true
        errorMessage = nil
        let mode = selectedMode
        let startDate = newStartDate
        defer {
            if requestId == previewRequestId {
                isPreviewing = false
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            let loadedPreview = try await repository.previewChoreReschedule(
                homeId: sourceWeek.homeId,
                sourceStart: sourceWeek.sourceStart,
                sourceEnd: sourceWeek.sourceEnd,
                newStart: startDate,
                mode: mode,
                timezone: sourceWeek.timezone
            )
            guard !Task.isCancelled, requestId == previewRequestId else { return }
            preview = loadedPreview
        } catch where isExpectedCancellation(error) {
        } catch {
            guard requestId == previewRequestId else { return }
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func executeReschedule() async {
        guard let preview, preview.eligibleCount > 0, !isExecuting else { return }
        isExecuting = true
        errorMessage = nil

        do {
            let result = try await repository.rescheduleChoreSchedule(
                homeId: sourceWeek.homeId,
                sourceStart: sourceWeek.sourceStart,
                sourceEnd: sourceWeek.sourceEnd,
                newStart: newStartDate,
                mode: selectedMode,
                generateThrough: sourceWeek.generateThrough(for: preview.destinationStart),
                timezone: sourceWeek.timezone
            )
            let generatedThrough = sourceWeek.generateThrough(for: preview.destinationStart)
            let occurrencesToSync = try await repository.fetchOccurrences(
                homeId: sourceWeek.homeId,
                from: preview.destinationStart,
                through: generatedThrough
            )
            _ = try await calendarSyncService.syncMissingCalendarEvents(
                homeId: sourceWeek.homeId,
                occurrences: occurrencesToSync
            )
            onComplete(result, preview.destinationStart)
        } catch {
            errorMessage = error.localizedDescription
        }

        isExecuting = false
    }

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isExpectedCancellation(underlying)
        }

        return false
    }
}

@MainActor
private final class MyChoresViewModel: ObservableObject {
    @Published private(set) var occurrences: [ChoreOccurrence] = []
    @Published private(set) var weekDays: [Date] = []
    @Published private(set) var selectedDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedAssignee: HomeChoreAssigneeFilter = .all

    private let repository: ChoresRepository
    private var activeHomeId: UUID?
    private var activeCurrentUserId: UUID?
    private var activeCurrentRole: HomeMemberRole?
    private var timezone = TimeZone.autoupdatingCurrent.identifier
    private var calendar = Calendar.autoupdatingCurrent
    private var visibleWeekAnchor = Date()
    private var categoriesById: [UUID: ChoreCategory] = [:]
    private var roomsById: [UUID: ChoreRoom] = [:]
    private var assigneesByOccurrenceId: [UUID: [ChoreOccurrenceAssignee]] = [:]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
        configureCalendar(weekStartsOn: nil, timezone: nil)
        updateWeekDays()
    }

    var visibleWeekTitle: String {
        guard let range = visibleWeekRange,
              let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end) else {
            return "This Week"
        }

        if calendar.isDate(range.start, equalTo: inclusiveEnd, toGranularity: .month) {
            let month = Self.monthYearFormatter.string(from: range.start)
            let startDay = Self.dayFormatter.string(from: range.start)
            let endDay = Self.dayFormatter.string(from: inclusiveEnd)
            return "\(month) \(startDay)-\(endDay)"
        }

        if calendar.component(.year, from: range.start) == calendar.component(.year, from: inclusiveEnd) {
            return "\(Self.monthDayFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
        }

        return "\(Self.monthDayYearFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
    }

    var summary: MyChoresWeekSummary {
        let eligibleOccurrences = summaryDisplayOccurrences.filter { !$0.isExcludedFromWeeklySummary }
        let approved = eligibleOccurrences.filter { $0.personalStatus == .completed }.count
        let pendingApproval = eligibleOccurrences.filter { $0.personalStatus == .awaitingApproval }.count
        let toDo = eligibleOccurrences.filter(\.isPersonalToDo).count
        return MyChoresWeekSummary(toDo: toDo, pendingApproval: pendingApproval, approved: approved, total: eligibleOccurrences.count)
    }

    var plannedChoreCount: Int {
        filteredOccurrences.count
    }

    var rescheduleSourceWeek: MyChoresRescheduleSourceWeek? {
        guard let homeId = activeHomeId,
              let range = visibleWeekRange,
              let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end),
              let defaultNewStart = calendar.date(byAdding: .day, value: 7, to: range.start) else {
            return nil
        }

        return MyChoresRescheduleSourceWeek(
            homeId: homeId,
            sourceStart: range.start,
            sourceEnd: inclusiveEnd,
            defaultNewStart: defaultNewStart,
            timezone: timezone,
            calendar: calendar
        )
    }

    func daySections(members: [HomeMemberDisplay]) -> [MyChoresDaySectionModel] {
        let displayOccurrences = displayOccurrences(members: members)
        return weekDays.map { day in
            let dayOccurrences = displayOccurrences
                .filter { calendar.isDate($0.dueAt, inSameDayAs: day) }
                .sortedForMyChoresWeek()
            return MyChoresDaySectionModel(
                date: day,
                title: Self.weekdayFormatter.string(from: day),
                dayNumber: Self.dayFormatter.string(from: day),
                accessibilityDateTitle: Self.fullDateFormatter.string(from: day),
                occurrences: dayOccurrences
            )
        }
    }

    private var summaryDisplayOccurrences: [MyChoresOccurrenceDisplay] {
        filteredOccurrences.map { occurrence in
            MyChoresOccurrenceDisplay(
                id: occurrence.id.uuidString,
                occurrence: occurrence,
                assigneeStatus: displayAssigneeStatus(for: occurrence),
                roomName: roomName(for: occurrence) ?? "No Room",
                assigneeName: "All",
                assigneeUserId: nil
            )
        }
    }

    private func displayOccurrences(members: [HomeMemberDisplay]) -> [MyChoresOccurrenceDisplay] {
        let memberByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })

        return filteredOccurrences.flatMap { occurrence -> [MyChoresOccurrenceDisplay] in
            let roomName = roomName(for: occurrence) ?? "No Room"
            let assignees = assigneesByOccurrenceId[occurrence.id, default: []]

            if !assignees.isEmpty {
                let visibleAssignees = assignees.filter { assignee in
                    guard assignee.status != .skipped && assignee.status != .cancelled else {
                        return false
                    }

                    guard canViewAllChores else {
                        return assignee.userId == activeCurrentUserId
                    }

                    return selectedAssignee.includes(assignee.userId)
                }

                return visibleAssignees.map { assignee in
                    MyChoresOccurrenceDisplay(
                        id: "\(occurrence.id.uuidString)-\(assignee.userId.uuidString)",
                        occurrence: occurrence,
                        assigneeStatus: assignee.status,
                        roomName: roomName,
                        assigneeName: memberName(for: assignee.userId, memberByUserId: memberByUserId),
                        assigneeUserId: assignee.userId
                    )
                }
            }

            if occurrence.assignmentMode == .open, let claimedBy = occurrence.claimedBy {
                return [
                    MyChoresOccurrenceDisplay(
                        id: "\(occurrence.id.uuidString)-\(claimedBy.uuidString)",
                        occurrence: occurrence,
                        assigneeStatus: nil,
                        roomName: roomName,
                        assigneeName: memberName(for: claimedBy, memberByUserId: memberByUserId),
                        assigneeUserId: claimedBy
                    )
                ]
            }

            return [
                MyChoresOccurrenceDisplay(
                    id: "\(occurrence.id.uuidString)-anyone",
                    occurrence: occurrence,
                    assigneeStatus: nil,
                    roomName: roomName,
                    assigneeName: "Anyone",
                    assigneeUserId: nil
                )
            ]
        }
    }

    private var canViewAllChores: Bool {
        activeCurrentRole == .owner || activeCurrentRole == .admin
    }

    private var filteredOccurrences: [ChoreOccurrence] {
        occurrences.filter { occurrence in
            selectedAssigneeIncludes(occurrence)
        }
    }

    func configure(homeId: UUID?, currentUserId: UUID?, currentRole: HomeMemberRole?, weekStartsOn: Int?, timezone: String?) async {
        let previousHomeId = activeHomeId
        let previousCurrentUserId = activeCurrentUserId
        let previousCurrentRole = activeCurrentRole
        let previousWeekStart = calendar.firstWeekday
        let previousTimezone = self.timezone
        activeHomeId = homeId
        activeCurrentUserId = currentUserId
        activeCurrentRole = currentRole
        configureCalendar(weekStartsOn: weekStartsOn, timezone: timezone)
        if previousHomeId != homeId || previousCurrentUserId != currentUserId || previousCurrentRole != currentRole || previousWeekStart != calendar.firstWeekday || previousTimezone != self.timezone {
            selectedDate = nil
            visibleWeekAnchor = calendar.startOfDay(for: Date())
            selectedAssignee = .all
        }
        updateWeekDays()
        await load()
    }

    func load() async {
        guard let homeId = activeHomeId else {
            activeHomeId = nil
            occurrences = []
            assigneesByOccurrenceId = [:]
            errorMessage = nil
            isLoading = false
            return
        }

        guard let range = visibleWeekRange else {
            occurrences = []
            errorMessage = "Unable to load this week."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let loadedOccurrences = loadOccurrences(homeId: homeId, from: range.start, through: range.end)
            async let loadedCategories = repository.fetchCategories(homeId: homeId)
            async let loadedRooms = repository.fetchRooms(homeId: homeId)
            let (loadedChoreOccurrences, categories, rooms) = try await (loadedOccurrences, loadedCategories, loadedRooms)
            let visibleOccurrences = loadedChoreOccurrences.filter { occurrence in
                occurrence.dueAt >= range.start &&
                occurrence.dueAt < range.end &&
                occurrence.status != .cancelled &&
                occurrence.status != .skipped
            }
            let loadedAssigneesByOccurrenceId = try await loadAssignees(for: visibleOccurrences)
            assigneesByOccurrenceId = loadedAssigneesByOccurrenceId
            self.occurrences = visibleOccurrences
            categoriesById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            roomsById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        } catch {
            occurrences = []
            assigneesByOccurrenceId = [:]
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load()
        }
    }

    func selectAssignee(_ filter: HomeChoreAssigneeFilter) {
        guard canViewAllChores else {
            selectedAssignee = .all
            return
        }

        selectedAssignee = filter
    }

    func resetAssigneeFilter() {
        selectedAssignee = .all
    }

    func moveToPreviousWeek() {
        guard let newAnchor = calendar.date(byAdding: .day, value: -7, to: visibleWeekAnchor) else { return }
        visibleWeekAnchor = newAnchor
        selectedDate = nil
        updateWeekDays()
        reload()
    }

    func moveToNextWeek() {
        guard let newAnchor = calendar.date(byAdding: .day, value: 7, to: visibleWeekAnchor) else { return }
        visibleWeekAnchor = newAnchor
        selectedDate = nil
        updateWeekDays()
        reload()
    }

    func moveToToday() {
        let today = calendar.startOfDay(for: Date())
        visibleWeekAnchor = today
        selectedDate = today
        updateWeekDays()
        reload()
    }

    func moveToWeek(containing date: Date) {
        visibleWeekAnchor = calendar.startOfDay(for: date)
        selectedDate = nil
        updateWeekDays()
        reload()
    }

    func selectDay(_ day: Date) {
        selectedDate = calendar.startOfDay(for: day)
    }

    func isSelectedDay(_ day: Date) -> Bool {
        selectedDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
    }

    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    func weekdaySymbol(for day: Date) -> String {
        Self.weekdayFormatter.string(from: day)
    }

    func dayNumber(for day: Date) -> String {
        Self.dayFormatter.string(from: day)
    }

    func accessibilityLabel(for day: Date) -> String {
        Self.fullDateFormatter.string(from: day)
    }

    func categoryName(for occurrence: ChoreOccurrence) -> String? {
        occurrence.categoryIdSnapshot.flatMap { categoriesById[$0]?.name }
    }

    func roomName(for occurrence: ChoreOccurrence) -> String? {
        occurrence.roomIdSnapshot.flatMap { roomsById[$0]?.name }
    }

    private var visibleWeekRange: (start: Date, end: Date)? {
        ChoreWeekRange.week(containing: visibleWeekAnchor, calendar: calendar)
    }

    private func configureCalendar(weekStartsOn: Int?, timezone: String?) {
        calendar = ChoreWeekRange.makeCalendar(weekStartsOn: weekStartsOn, timezone: timezone)
        self.timezone = calendar.timeZone.identifier
        Self.configureFormatters(calendar: calendar)
    }

    private func updateWeekDays() {
        guard let range = visibleWeekRange else {
            weekDays = []
            return
        }
        weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
    }

    private static func configureFormatters(calendar: Calendar) {
        [dayFormatter, monthYearFormatter, monthDayFormatter, monthDayYearFormatter, weekdayFormatter, fullDateFormatter].forEach { formatter in
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
        }
    }

    private func loadOccurrences(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        if canViewAllChores {
            return try await repository.fetchHouseChoreOccurrences(homeId: homeId, from: startDate, through: endDate)
        }

        return try await repository.fetchMyOccurrences(homeId: homeId, from: startDate, through: endDate)
    }

    private func loadAssignees(for occurrences: [ChoreOccurrence]) async throws -> [UUID: [ChoreOccurrenceAssignee]] {
        let loadedAssignees = try await repository.fetchOccurrenceAssignees(occurrenceIds: occurrences.map(\.id))
        let groupedAssignees = Dictionary(grouping: loadedAssignees, by: \.occurrenceId)

        return groupedAssignees
    }

    private func selectedAssigneeIncludes(_ occurrence: ChoreOccurrence) -> Bool {
        guard canViewAllChores else {
            return true
        }

        switch selectedAssignee {
        case .all:
            return true
        case .member(let userId):
            if occurrence.assignmentMode == .open {
                return occurrence.claimedBy == userId
            }

            return assigneesByOccurrenceId[occurrence.id, default: []].contains { $0.userId == userId }
        case .anyone:
            return occurrence.assignmentMode == .open && occurrence.claimedBy == nil
        }
    }

    private func displayAssigneeStatus(for occurrence: ChoreOccurrence) -> ChoreAssigneeStatus? {
        switch selectedAssignee {
        case .member(let userId):
            return assigneesByOccurrenceId[occurrence.id, default: []].first { $0.userId == userId }?.status
        case .all, .anyone:
            guard !canViewAllChores, let activeCurrentUserId else {
                return nil
            }

            return assigneesByOccurrenceId[occurrence.id, default: []].first { $0.userId == activeCurrentUserId }?.status
        }
    }

    private func memberName(for userId: UUID, memberByUserId: [UUID: HomeMemberDisplay]) -> String {
        memberByUserId[userId]?.displayName ?? "Assigned Member"
    }
}

private struct MyChoresWeekSummary: Equatable {
    let toDo: Int
    let pendingApproval: Int
    let approved: Int
    let total: Int

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(approved) / Double(total)
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }
}

private struct MyChoresDaySectionModel: Identifiable {
    let date: Date
    let title: String
    let dayNumber: String
    let accessibilityDateTitle: String
    let occurrences: [MyChoresOccurrenceDisplay]

    var id: Date { date }
}

private struct MyChoresOccurrenceDisplay: Identifiable {
    let id: String
    let occurrence: ChoreOccurrence
    let assigneeStatus: ChoreAssigneeStatus?
    let roomName: String
    let assigneeName: String
    let assigneeUserId: UUID?

    var dueAt: Date { occurrence.dueAt }
    var isAllDay: Bool { occurrence.isAllDay }
    var titleSnapshot: String { occurrence.titleSnapshot }
    var pointsValue: Int { occurrence.pointsValue }

    var personalStatus: ChoreOccurrenceStatus {
        assigneeStatus?.personalOccurrenceStatus ?? occurrence.status
    }

    var displayStatus: ChoreOccurrenceDisplayStatus {
        return .stored(personalStatus)
    }

    var isExcludedFromWeeklySummary: Bool {
        personalStatus == .skipped || personalStatus == .cancelled
    }

    var isPersonalToDo: Bool {
        personalStatus == .notStarted || personalStatus == .needsRedo
    }
}

private struct MyChoresWeekSummaryCard: View {
    let summary: MyChoresWeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    summaryMetric(title: "To Do", value: summary.toDo, color: HomeyDashboardTheme.softRed)
                    summaryMetric(title: "Pending Approval", value: summary.pendingApproval, color: HomeyDashboardTheme.orangeAccent)
                    summaryMetric(title: "Approved", value: summary.approved, color: HomeyDashboardTheme.sageAccent)
                }

                VStack(spacing: 10) {
                    summaryMetric(title: "To Do", value: summary.toDo, color: HomeyDashboardTheme.softRed)
                    summaryMetric(title: "Pending Approval", value: summary.pendingApproval, color: HomeyDashboardTheme.orangeAccent)
                    summaryMetric(title: "Approved", value: summary.approved, color: HomeyDashboardTheme.sageAccent)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(HomeyDashboardTheme.softBorder.opacity(0.45))
                        Capsule()
                            .fill(HomeyDashboardTheme.sageAccent)
                            .frame(width: proxy.size.width * summary.progress)
                    }
                }
                .frame(height: 9)
                .accessibilityHidden(true)

                Text("\(summary.progressPercent)% Complete")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
        }
        .padding(16)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week. To do \(summary.toDo). Pending approval \(summary.pendingApproval). Approved \(summary.approved). \(summary.progressPercent) percent complete.")
    }

    private func summaryMetric(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(2)
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MyChoresDayColumn: View {
    let section: MyChoresDaySectionModel
    let isToday: Bool
    let isSelected: Bool
    @Binding var expandedAssigneeSectionKeys: Set<MyChoresDayAssigneeExpansionKey>
    let onSelectDay: () -> Void
    let onSelectOccurrence: (MyChoresOccurrenceSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelectDay) {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(section.title)
                            .font(.caption.weight(.bold))
                        if isToday {
                            Text("Today")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                                .overlay { Capsule().stroke(HomeyDashboardTheme.warmBrown.opacity(0.35), lineWidth: 1) }
                        }
                    }

                    Text(section.dayNumber)
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(isSelected || isToday ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    isSelected || isToday ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected || isToday ? HomeyDashboardTheme.warmBrown.opacity(0.42) : Color.clear, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.accessibilityDateTitle), \(section.occurrences.count) chores")

            VStack(alignment: .leading, spacing: 7) {
                if section.occurrences.isEmpty {
                    Text("No chores")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .accessibilityLabel("No chores")
                } else {
                    ForEach(assigneeSections) { assigneeSection in
                        VStack(alignment: .leading, spacing: 7) {
                            MyChoresAssigneeAccordionHeader(
                                section: assigneeSection,
                                isExpanded: isExpanded(assigneeSection)
                            ) {
                                toggle(assigneeSection)
                            }

                            if isExpanded(assigneeSection) {
                                ForEach(assigneeSection.occurrences) { occurrence in
                                    MyChoresOccurrenceCard(
                                        displayOccurrence: occurrence,
                                        dateTitle: section.accessibilityDateTitle,
                                        onTap: {
                                            onSelectOccurrence(MyChoresOccurrenceSelection(
                                                occurrence: occurrence.occurrence,
                                                assigneeUserId: occurrence.assigneeUserId
                                            ))
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1) }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.08), radius: 7, x: 0, y: 4)
    }

    private var assigneeSections: [MyChoresAssigneeSectionModel] {
        let grouped = Dictionary(grouping: section.occurrences) { occurrence in
            MyChoresAssigneeIdentity(
                userId: occurrence.assigneeUserId,
                fallbackKey: occurrence.assigneeName
            )
        }
        return grouped
            .map { identity, occurrences in
                MyChoresAssigneeSectionModel(
                    userId: identity.userId,
                    name: occurrences.first?.assigneeName ?? "Assigned Member",
                    occurrences: occurrences.sortedForMyChoresWeek()
                )
            }
            .sorted { first, second in
                if first.name == "Anyone" { return false }
                if second.name == "Anyone" { return true }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
    }

    private func isExpanded(_ section: MyChoresAssigneeSectionModel) -> Bool {
        expandedAssigneeSectionKeys.contains(expansionKey(for: section))
    }

    private func toggle(_ section: MyChoresAssigneeSectionModel) {
        let key = expansionKey(for: section)
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedAssigneeSectionKeys.contains(key) {
                expandedAssigneeSectionKeys.remove(key)
            } else {
                expandedAssigneeSectionKeys.insert(key)
            }
        }
    }

    private func expansionKey(for section: MyChoresAssigneeSectionModel) -> MyChoresDayAssigneeExpansionKey {
        MyChoresDayAssigneeExpansionKey(day: self.section.date, assigneeUserId: section.userId)
    }
}

private struct MyChoresAssigneeSectionModel: Identifiable {
    let userId: UUID?
    let name: String
    let occurrences: [MyChoresOccurrenceDisplay]

    var id: String { userId?.uuidString ?? "anyone" }
}

private struct MyChoresAssigneeIdentity: Hashable {
    let userId: UUID?
    let fallbackKey: String

    static func == (lhs: MyChoresAssigneeIdentity, rhs: MyChoresAssigneeIdentity) -> Bool {
        switch (lhs.userId, rhs.userId) {
        case let (lhsUserId?, rhsUserId?):
            return lhsUserId == rhsUserId
        case (nil, nil):
            return lhs.fallbackKey == rhs.fallbackKey
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        if let userId {
            hasher.combine(userId)
        } else {
            hasher.combine(fallbackKey)
        }
    }
}

private struct MyChoresDayAssigneeExpansionKey: Hashable {
    let day: Date
    let assigneeUserId: UUID?
}

private struct MyChoresAssigneeAccordionHeader: View {
    let section: MyChoresAssigneeSectionModel
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Text(section.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.8))
                    .frame(width: 10)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.name), \(isExpanded ? "expanded" : "collapsed")")
    }
}

private struct MyChoresOccurrenceSelection: Identifiable {
    let occurrence: ChoreOccurrence
    let assigneeUserId: UUID?

    var id: String {
        "\(occurrence.id.uuidString)-\(assigneeUserId?.uuidString ?? "anyone")"
    }
}

private struct MyChoresOccurrenceCard: View {
    let displayOccurrence: MyChoresOccurrenceDisplay
    let dateTitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayOccurrence.titleSnapshot)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                Text(scheduleText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)

                Text(pointsText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusStyle.color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(statusStyle.backgroundColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(statusStyle.color.opacity(0.62), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusStyle: ChoreOccurrenceStatusStyle {
        ChoreOccurrenceStatusStyle(displayStatus: displayOccurrence.displayStatus)
    }

    private var scheduleText: String {
        displayOccurrence.roomName
    }

    private var pointsText: String {
        "\(displayOccurrence.pointsValue) \(displayOccurrence.pointsValue == 1 ? "point" : "points")"
    }

    private var statusText: String {
        statusStyle.title
    }

    private var accessibilityLabel: String {
        [
            displayOccurrence.titleSnapshot,
            dateTitle,
            scheduleText,
            pointsText,
            statusText
        ].joined(separator: ". ")
    }
}

private extension Array where Element == MyChoresOccurrenceDisplay {
    func sortedForMyChoresWeek() -> [MyChoresOccurrenceDisplay] {
        sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay {
                return !lhs.isAllDay && rhs.isAllDay
            }

            if lhs.dueAt != rhs.dueAt {
                return lhs.dueAt < rhs.dueAt
            }

            return lhs.titleSnapshot.localizedStandardCompare(rhs.titleSnapshot) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum ChoreDateRange {
    static func upcoming(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 30, to: start) ?? now
        return (start, end)
    }

    static func recentHistory(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let now = Date()
        let end = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let start = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        return (start, end)
    }
}

struct ChoreShellCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: 38, height: 38)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: 30)
    }
}

struct ChoreLoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct ChoreMessageState: View {
    let title: String
    let message: String
    let systemImage: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 52, height: 52)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle {
                Button(buttonTitle) {
                    action?()
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 150)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
    }
}

struct ChoreOccurrenceRow: View {
    let occurrence: ChoreOccurrence

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.titleSnapshot)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(statusStyle.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let date = occurrence.dueAt.formatted(date: .abbreviated, time: occurrence.isAllDay ? .omitted : .shortened)
        return "\(date) • \(occurrence.pointsValue) \(occurrence.pointsValue == 1 ? "point" : "points")"
    }

    private var statusColor: Color {
        statusStyle.color
    }

    private var statusStyle: ChoreOccurrenceStatusStyle {
        ChoreOccurrenceStatusStyle(occurrence: occurrence)
    }
}
