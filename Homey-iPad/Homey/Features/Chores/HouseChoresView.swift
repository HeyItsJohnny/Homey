import Combine
import SwiftUI

struct HouseChoresView: View {
    @EnvironmentObject private var attentionStore: ChoresAttentionStore
    @State private var selectedSection: HouseChoresSection = .activeChores

    var body: some View {
        ChoreShellCard(title: "House Chores", systemImage: "house.and.flag.fill") {
            ChoreSectionDescriptionHeader(
                title: "House Chores",
                description: "Manage your home's chores, assignments, schedules, and recurring tasks."
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(HouseChoresSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.systemImage)
                                .font(.headline.weight(.semibold))
                                .frame(width: 28)

                            HStack(spacing: 7) {
                                Text(section.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                AttentionBadge(count: badgeCount(for: section))
                            }
                        }
                        .foregroundStyle(selectedSection == section ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.primaryText)
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .background(
                            selectedSection == section ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            selectedSectionContent
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .activeChores:
            HouseChoresActiveView()
        case .approvals:
            HouseChoresApprovalsView()
        case .rooms:
            HouseChoresRoomsView()
        case .settings:
            HouseChoresSettingsView()
        }
    }

    private func badgeCount(for section: HouseChoresSection) -> Int? {
        switch section {
        case .approvals:
            return attentionStore.pendingChoreApprovalCount
        case .activeChores, .rooms, .settings:
            return nil
        }
    }
}

private enum HouseChoresSection: String, CaseIterable, Identifiable {
    case activeChores
    case approvals
    case rooms
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeChores:
            return "Active Chores"
        case .approvals:
            return "Approvals"
        case .rooms:
            return "Rooms"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .activeChores:
            return "checklist"
        case .approvals:
            return "checkmark.seal"
        case .rooms:
            return "house.lodge"
        case .settings:
            return "gearshape"
        }
    }
}

struct HouseChoresActiveView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = HouseChoresActiveViewModel()
    @State private var editingChore: ChoreTemplate?
    @State private var shouldRefreshAfterEdit = false

    var body: some View {
        HouseChoresSectionCard(title: "Active Chores") {
            if viewModel.isLoading && viewModel.summaries.isEmpty {
                ChoreLoadingState(message: "Loading active chores...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load Active Chores",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else if viewModel.summaries.isEmpty {
                ChoreMessageState(
                    title: "No active chores yet.",
                    message: "Use Add Chore to create your first household chore.",
                    systemImage: "checklist"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.summaries) { summary in
                        ChoreSummaryCard(summary: summary, members: homeService.membersForSelectedHome()) {
                            editingChore = summary.chore
                        }
                    }
                }
            }
        }
        .task(id: homeService.selectedHomeID) {
            await loadMembersIfNeeded()
            await viewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                if editingChore == nil {
                    viewModel.reload()
                } else {
                    shouldRefreshAfterEdit = true
                }
            }
        }
        .sheet(
            item: $editingChore,
            onDismiss: refreshAfterSuccessfulEditIfNeeded
        ) { chore in
            ChoreEditorView(
                mode: .edit(templateId: chore.id),
                homeId: homeService.selectedHomeID,
                timezone: homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
            ) {
                shouldRefreshAfterEdit = true
            }
        }
    }

    private func refreshAfterSuccessfulEditIfNeeded() {
        guard shouldRefreshAfterEdit else {
            return
        }

        shouldRefreshAfterEdit = false
        viewModel.reload()
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHome = homeService.selectedHome(),
              let currentUser = authenticationService.currentUser else {
            return
        }

        if !homeService.hasLoadedMembersForSelectedHome() {
            await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
        }
    }
}

struct HouseChoresApprovalsView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = HouseChoresApprovalsViewModel()

    var body: some View {
        HouseChoresSectionCard(title: "Approvals") {
            if viewModel.isLoading && viewModel.approvalItems.isEmpty {
                ChoreLoadingState(message: "Loading approvals...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load Approvals",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else if viewModel.approvalItems.isEmpty {
                ChoreMessageState(
                    title: "No Approvals Waiting",
                    message: "Submitted chores that require review will appear here.",
                    systemImage: "checkmark.seal"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.approvalItems) { item in
                        ChoreApprovalRow(
                            item: item,
                            memberName: memberName(for: item.submission.submittedBy),
                            isReviewing: viewModel.reviewingOccurrenceId == item.occurrence.id,
                            onApprove: {
                                Task {
                                    await viewModel.review(item, decision: .approved)
                                }
                            },
                            onNeedsRedo: {
                                Task {
                                    await viewModel.review(item, decision: .needsRedo)
                                }
                            }
                        )

                        if item.id != viewModel.approvalItems.last?.id {
                            Divider()
                                .overlay(HomeyDashboardTheme.softBorder)
                        }
                    }
                }
            }

            if let actionErrorMessage = viewModel.actionErrorMessage {
                Text(actionErrorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: homeService.selectedHomeID) {
            await loadMembersIfNeeded()
            await viewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
    }

    private func memberName(for userId: UUID) -> String {
        homeService.membersForSelectedHome().first { $0.userId == userId }?.displayName ?? "Submitted member"
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHome = homeService.selectedHome(),
              let currentUser = authenticationService.currentUser else {
            return
        }

        if !homeService.hasLoadedMembersForSelectedHome() {
            await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
        }
    }
}

struct HouseChoresRoomsView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = HouseChoresRoomsViewModel()
    @State private var selectedRoom: ChoreRoom?

    var body: some View {
        HouseChoresSectionCard(title: "Rooms") {
            if viewModel.isLoading && viewModel.rooms.isEmpty {
                ChoreLoadingState(message: "Loading rooms...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load Rooms",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else {
                ChoreRoomMetadataList(
                    summaries: viewModel.roomSummaries,
                    onSelect: { selectedRoom = $0.room }
                )
            }
        }
        .task(id: homeService.selectedHomeID) {
            await viewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
        .sheet(item: $selectedRoom) { room in
            ChoreRoomDetailSheet(
                room: room,
                detail: viewModel.roomDetail(for: room)
            )
        }
    }

}

struct HouseChoresSettingsView: View {
    var body: some View {
        HouseChoresSectionCard(title: "Settings") {
            ChoreMessageState(
                title: "Chore Settings",
                message: "House chore settings will be configured here.",
                systemImage: "gearshape"
            )
        }
    }
}

private struct HouseChoresSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(HomeyDashboardTheme.appBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct ChoreRoomMetadataList: View {
    let summaries: [ChoreRoomManagementSummary]
    let onSelect: (ChoreRoomManagementSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rooms")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            if summaries.isEmpty {
                Text("No rooms yet.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(summaries) { summary in
                        ChoreRoomSummaryCard(summary: summary) {
                            onSelect(summary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ChoreRoomSummaryCard: View {
    let summary: ChoreRoomManagementSummary
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .accessibilityHidden(true)
                    
                    Text(summary.room.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer(minLength: 8)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .accessibilityHidden(true)
                }
                
                VStack(alignment: .leading, spacing: 9) {
                    lastCleanedRow
                    Text(summary.choreCountText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: HomeyDashboardTheme.shadow.opacity(0.08), radius: 7, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.room.name), Last Cleaned \(summary.lastCleanedText), \(summary.choreCountText)")
        .accessibilityHint("Opens room overview")
    }
    
    private var lastCleanedRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let weekdayText = summary.preferredCleaningWeekdayText {
                    Text(weekdayText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                }

                Text("Last Cleaned")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Text(summary.lastCleanedText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct ChoreRoomDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let room: ChoreRoom
    let detail: ChoreRoomDetail?
    
    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        assignedChoresList
                    }
                    .padding(22)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(room.name)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            
            VStack(alignment: .leading, spacing: 10) {
                detailRow("Preferred Cleaning Day", value: preferredCleaningDayText)
                detailRow("Last Cleaned", value: roomLastCleanedText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 24)
    }
    
    private var assignedChoresList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assigned Chores")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            
            if detail?.chores.isEmpty ?? true {
                ChoreMessageState(
                    title: "No chores are assigned to this Room.",
                    message: "Chores assigned from Add/Edit Chore will appear here.",
                    systemImage: "tray"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(detail?.chores ?? []) { choreDetail in
                        ChoreRoomAssignedChoreRow(detail: choreDetail)
                        
                        if choreDetail.id != detail?.chores.last?.id {
                            Divider()
                                .overlay(HomeyDashboardTheme.softBorder)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1)
        }
    }

    private var preferredCleaningDayText: String {
        room.preferredCleaningWeekday?.displayName ?? "Not set"
    }

    private var roomLastCleanedText: String {
        guard room.lastCleanedAt != nil else {
            return "Never cleaned"
        }

        return detail?.summary.lastCleanedText ?? "Never cleaned"
    }
    
    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
    }
}

private struct ChoreRoomAssignedChoreRow: View {
    let detail: ChoreRoomChoreDetail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(detail.chore.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(HouseChoreRecurrenceFormatter.text(for: detail.recurrenceRule))
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(detail.lastCompletedText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                if let nextDueText = detail.nextDueText {
                    Text(nextDueText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ChoreApprovalRow: View {
    let item: ChoreApprovalItem
    let memberName: String
    let isReviewing: Bool
    let onApprove: () -> Void
    let onNeedsRedo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChoreOccurrenceRow(occurrence: item.occurrence)

            VStack(alignment: .leading, spacing: 8) {
                approvalDetail("Member", memberName)
                approvalDetail("Due", item.occurrence.dueAt.formatted(date: .abbreviated, time: item.occurrence.isAllDay ? .omitted : .shortened))
                approvalDetail("Submitted", item.submission.submittedAt.formatted(date: .abbreviated, time: .shortened))
                approvalDetail("Points", "\(item.occurrence.pointsValue) points")

                if let note = item.submission.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    approvalDetail("Note", note)
                }

                if item.occurrence.requiresPhoto || item.submission.photoPath != nil {
                    approvalDetail("Photo", item.submission.photoPath == nil ? "Required, not attached" : "Provided")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)

            HStack(spacing: 10) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(isReviewing)

                Button(action: onNeedsRedo) {
                    Label("Needs Redo", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.35), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .disabled(isReviewing)
            }

            if isReviewing {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyDashboardTheme.warmBrown)
            }
        }
        .padding(.vertical, 12)
    }

    private func approvalDetail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChoreSummaryCard: View {
    let summary: HouseChoreSummary
    let members: [HomeMemberDisplay]
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.chore.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(recurrenceText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(summary.roomName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }

                Text(assignmentText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(pointsText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())

                    Spacer(minLength: 8)

                    Text(nextDueText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .dashboardCard(cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Edit Chore")
    }

    private var recurrenceText: String {
        HouseChoreRecurrenceFormatter.text(for: summary.recurrenceRule)
    }

    private var assignmentText: String {
        if summary.chore.assignmentMode == .open {
            return "Anyone can claim"
        }

        let displayNames = summary.assignees.compactMap { assignee in
            members.first { $0.userId == assignee.userId }?.displayName
        }

        if displayNames.count == 1 {
            return "Assigned to \(displayNames[0])"
        }

        if displayNames.count == 2 {
            return "\(displayNames[0]) + \(displayNames[1])"
        }

        if summary.assignees.count > 2 {
            return "\(summary.assignees.count) people assigned"
        }

        return "No assignees"
    }

    private var pointsText: String {
        "\(summary.chore.pointsValue) \(summary.chore.pointsValue == 1 ? "point" : "points")"
    }

    private var nextDueText: String {
        guard let nextOccurrence = summary.nextOccurrence else {
            return "No upcoming date"
        }

        let calendar = Calendar.current
        let dateText: String
        if calendar.isDateInToday(nextOccurrence.dueAt) {
            dateText = "Due today"
        } else if calendar.isDateInTomorrow(nextOccurrence.dueAt) {
            dateText = "Next: Tomorrow"
        } else {
            dateText = "Next: \(nextOccurrence.dueAt.formatted(date: .abbreviated, time: .omitted))"
        }

        guard !nextOccurrence.isAllDay else {
            return dateText
        }

        return "\(dateText) • \(nextOccurrence.dueAt.formatted(date: .omitted, time: .shortened))"
    }

    private var accessibilityLabel: String {
        "\(summary.chore.title). \(recurrenceText). \(summary.roomName). \(assignmentText). \(pointsText). \(nextDueText)."
    }

}

private enum HouseChoreRecurrenceFormatter {
    static func text(for recurrenceRule: ChoreRecurrenceRule?) -> String {
        guard let recurrenceRule else {
            return "Schedule not set"
        }

        switch recurrenceRule.frequency {
        case .none:
            return "One Time"
        case .daily:
            return recurrenceRule.intervalValue == 1 ? "Daily" : "Every \(recurrenceRule.intervalValue) Days"
        case .weekly:
            let interval = recurrenceRule.intervalValue == 1 ? "Weekly" : "Every \(recurrenceRule.intervalValue) Weeks"
            return "\(interval) • \(weekdaySummary(recurrenceRule.weekdays))"
        case .monthly:
            if recurrenceRule.intervalValue == 6 {
                return "Every 6 Months"
            }
            let interval = recurrenceRule.intervalValue == 1 ? "Monthly" : "Every \(recurrenceRule.intervalValue) Months"
            return "\(interval) • Day \(recurrenceRule.dayOfMonth ?? 1)"
        case .yearly:
            let month = monthName(recurrenceRule.monthOfYear)
            let day = recurrenceRule.dayOfMonth ?? 1
            return "Annually • \(month) \(day)"
        }
    }

    private static func weekdaySummary(_ weekdays: [Int]) -> String {
        let names = weekdays
            .sorted()
            .compactMap { weekdayNames[$0] }

        guard !names.isEmpty else {
            return "Weekdays not set"
        }

        if names.count == 1 {
            return names[0]
        }

        if names.count == 2 {
            return "\(names[0]) and \(names[1])"
        }

        return names.joined(separator: ", ")
    }

    private static func monthName(_ month: Int?) -> String {
        guard let month, (1...12).contains(month) else {
            return "Month not set"
        }

        return Calendar.current.shortMonthSymbols[month - 1]
    }

    private static let weekdayNames: [Int: String] = [
        0: "Sunday",
        1: "Monday",
        2: "Tuesday",
        3: "Wednesday",
        4: "Thursday",
        5: "Friday",
        6: "Saturday"
    ]
}

private struct HouseChoreSummary: Identifiable, Hashable {
    let chore: ChoreTemplate
    let recurrenceRule: ChoreRecurrenceRule?
    let assignees: [ChoreTemplateAssignee]
    let nextOccurrence: ChoreOccurrence?
    let roomName: String

    var id: UUID {
        chore.id
    }
}

@MainActor
private final class HouseChoresActiveViewModel: ObservableObject {
    @Published private(set) var summaries: [HouseChoreSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    func load(homeId: UUID?) async {
        guard let homeId else {
            reset()
            return
        }

        activeHomeId = homeId
        isLoading = true
        errorMessage = nil

        do {
            let range = ChoreDateRange.upcoming()
            async let loadedChores = repository.fetchTemplates(homeId: homeId, includeArchived: false)
            async let loadedOccurrences = repository.fetchHouseChoreOccurrences(homeId: homeId, from: range.start, through: range.end)
            async let loadedRooms = repository.fetchRooms(homeId: homeId)
            let chores = try await loadedChores.filter { $0.isActive && $0.archivedAt == nil }
            let occurrences = try await loadedOccurrences
            let rooms = try await loadedRooms
            let roomsById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
            let otherRoomName = rooms.first { $0.archivedAt == nil && $0.roomType == .other }?.name
                ?? rooms.first { $0.archivedAt == nil && $0.name.caseInsensitiveCompare("Other") == .orderedSame }?.name
                ?? "Other"
            var loadedSummaries: [HouseChoreSummary] = []

            for chore in chores {
                let recurrenceRule = try await repository.fetchRecurrenceRule(templateId: chore.id)
                let assignees = try await repository.fetchTemplateAssignees(templateId: chore.id)
                let nextOccurrence = occurrences
                    .filter { $0.templateId == chore.id }
                    .sorted { $0.dueAt < $1.dueAt }
                    .first

                loadedSummaries.append(
                    HouseChoreSummary(
                        chore: chore,
                        recurrenceRule: recurrenceRule,
                        assignees: assignees,
                        nextOccurrence: nextOccurrence,
                        roomName: chore.roomId.flatMap { roomsById[$0]?.name } ?? otherRoomName
                    )
                )
            }

            summaries = loadedSummaries.sorted { lhs, rhs in
                let titleComparison = lhs.chore.title.localizedCaseInsensitiveCompare(rhs.chore.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }

                switch (lhs.nextOccurrence?.dueAt, rhs.nextOccurrence?.dueAt) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.chore.id.uuidString < rhs.chore.id.uuidString
                }
            }
        } catch {
            summaries = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId)
        }
    }

    private func reset() {
        activeHomeId = nil
        summaries = []
        errorMessage = nil
        isLoading = false
    }
}

@MainActor
private final class HouseChoresApprovalsViewModel: ObservableObject {
    @Published private(set) var approvalItems: [ChoreApprovalItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var reviewingOccurrenceId: UUID?
    @Published private(set) var errorMessage: String?
    @Published var actionErrorMessage: String?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    func load(homeId: UUID?) async {
        guard let homeId else {
            reset()
            return
        }

        activeHomeId = homeId
        isLoading = true
        errorMessage = nil
        actionErrorMessage = nil

        do {
            let queueItems = try await repository.fetchPendingChoreApprovals(homeId: homeId)
            let loadedItems = queueItems.map { ChoreApprovalItem(occurrence: $0.occurrence, submission: $0.submission) }

            approvalItems = loadedItems
            logApprovalQueueMismatchIfNeeded(homeId: homeId, listCount: loadedItems.count)
        } catch {
            approvalItems = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func review(_ item: ChoreApprovalItem, decision: ChoreApprovalDecision) async {
        guard reviewingOccurrenceId == nil else {
            return
        }

        let occurrence = item.occurrence
        reviewingOccurrenceId = occurrence.id
        actionErrorMessage = nil
        defer { reviewingOccurrenceId = nil }

        do {
            try await repository.reviewSubmission(
                submissionId: item.submission.id,
                decision: decision,
                adminNote: nil,
                pointsAwarded: decision == .approved ? max(0, occurrence.pointsValue) : 0
            )
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            await load(homeId: activeHomeId)
        } catch {
            actionErrorMessage = decision == .approved ? "Unable to approve chore." : "Unable to request redo."
        }
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId)
        }
    }

    private func reset() {
        activeHomeId = nil
        approvalItems = []
        errorMessage = nil
        actionErrorMessage = nil
        isLoading = false
    }

    private func logApprovalQueueMismatchIfNeeded(homeId: UUID, listCount: Int) {
        #if DEBUG
        Task {
            guard let badgeCount = try? await repository.fetchPendingChoreApprovalCount(homeId: homeId) else { return }
            if badgeCount != listCount {
                print("WARNING: approval badge/list mismatch")
                print("home_id: \(homeId.uuidString)")
                print("pendingApprovalBadgeCount: \(badgeCount)")
                print("pendingApprovalListCount: \(listCount)")
            }
        }
        #endif
    }
}

private struct ChoreApprovalItem: Identifiable, Hashable {
    let occurrence: ChoreOccurrence
    let submission: ChoreSubmission

    var id: UUID { submission.id }
}

private struct ChoreRoomManagementSummary: Identifiable, Hashable {
    let room: ChoreRoom
    let choreCount: Int

    var id: UUID {
        room.id
    }

    var choreCountText: String {
        "\(choreCount) \(choreCount == 1 ? "Chore" : "Chores")"
    }

    var lastCleanedText: String {
        guard let lastCleanedAt = room.lastCleanedAt else {
            return "Never"
        }

        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(lastCleanedAt) {
            return "Today"
        }

        if calendar.isDateInYesterday(lastCleanedAt) {
            return "Yesterday"
        }

        return lastCleanedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var preferredCleaningWeekdayText: String? {
        room.preferredCleaningWeekday?.displayName
    }
}

private struct ChoreRoomDetail: Identifiable, Hashable {
    let summary: ChoreRoomManagementSummary
    let chores: [ChoreRoomChoreDetail]

    var id: UUID {
        summary.id
    }
}

private struct ChoreRoomChoreDetail: Identifiable, Hashable {
    let chore: ChoreTemplate
    let recurrenceRule: ChoreRecurrenceRule?
    let lastCompletedAt: Date?
    let nextOccurrence: ChoreOccurrence?

    var id: UUID {
        chore.id
    }

    var lastCompletedText: String {
        guard let lastCompletedAt else {
            return "Never completed"
        }

        return "Last completed \(lastCompletedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    var nextDueText: String? {
        guard let nextOccurrence else {
            return nil
        }

        let dateText = nextOccurrence.dueAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        guard !nextOccurrence.isAllDay else {
            return "Next due \(dateText)"
        }

        return "Next due \(dateText) at \(nextOccurrence.dueAt.formatted(date: .omitted, time: .shortened))"
    }
}

@MainActor
private final class HouseChoresRoomsViewModel: ObservableObject {
    @Published private(set) var rooms: [ChoreRoom] = []
    @Published private(set) var activeChores: [ChoreTemplate] = []
    @Published private(set) var roomDetailsById: [UUID: ChoreRoomDetail] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    var roomSummaries: [ChoreRoomManagementSummary] {
        rooms.map { room in
            ChoreRoomManagementSummary(
                room: room,
                choreCount: activeChores.filter { $0.roomId == room.id }.count
            )
        }
    }

    func roomDetail(for room: ChoreRoom) -> ChoreRoomDetail? {
        roomDetailsById[room.id] ?? ChoreRoomDetail(
            summary: ChoreRoomManagementSummary(
                room: room,
                choreCount: activeChores.filter { $0.roomId == room.id }.count
            ),
            chores: []
        )
    }

    func load(homeId: UUID?) async {
        guard let homeId else {
            reset()
            return
        }

        activeHomeId = homeId
        isLoading = true
        errorMessage = nil

        do {
            let range = ChoreDateRange.upcoming()
            async let loadedRooms = repository.fetchRooms(homeId: homeId)
            async let loadedTemplates = repository.fetchTemplates(homeId: homeId, includeArchived: false)
            async let loadedOccurrences = repository.fetchHouseChoreOccurrences(homeId: homeId, from: range.start, through: range.end)

            rooms = try await loadedRooms
            activeChores = try await loadedTemplates
                .filter { $0.isActive && $0.archivedAt == nil }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let templateIds = activeChores.map(\.id)
            async let loadedRules = repository.fetchRecurrenceRules(templateIds: templateIds)
            async let loadedCompletedOccurrences = repository.fetchCompletedOccurrences(templateIds: templateIds)
            let upcomingOccurrences = try await loadedOccurrences
            let recurrenceRules = try await loadedRules
            let completedOccurrences = try await loadedCompletedOccurrences

            roomDetailsById = makeRoomDetails(
                rooms: rooms,
                chores: activeChores,
                recurrenceRules: recurrenceRules,
                completedOccurrences: completedOccurrences,
                upcomingOccurrences: upcomingOccurrences
            )
        } catch {
            rooms = []
            activeChores = []
            roomDetailsById = [:]
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId)
        }
    }

    private func reset() {
        activeHomeId = nil
        rooms = []
        activeChores = []
        roomDetailsById = [:]
        errorMessage = nil
        isLoading = false
    }

    private func makeRoomDetails(
        rooms: [ChoreRoom],
        chores: [ChoreTemplate],
        recurrenceRules: [ChoreRecurrenceRule],
        completedOccurrences: [ChoreOccurrence],
        upcomingOccurrences: [ChoreOccurrence]
    ) -> [UUID: ChoreRoomDetail] {
        let rulesByTemplateId = Dictionary(uniqueKeysWithValues: recurrenceRules.map { ($0.templateId, $0) })
        let lastCompletedByTemplateId = latestCompletedOccurrencesByTemplateId(completedOccurrences)
        let nextOccurrenceByTemplateId = nextOccurrencesByTemplateId(upcomingOccurrences)

        return Dictionary(uniqueKeysWithValues: rooms.map { room in
            let assignedChores = chores
                .filter { $0.roomId == room.id }
                .map { chore in
                    ChoreRoomChoreDetail(
                        chore: chore,
                        recurrenceRule: rulesByTemplateId[chore.id],
                        lastCompletedAt: lastCompletedByTemplateId[chore.id]?.completedAt,
                        nextOccurrence: nextOccurrenceByTemplateId[chore.id]
                    )
                }
                .sorted(by: compareRoomChoreDetails)
            let summary = ChoreRoomManagementSummary(room: room, choreCount: assignedChores.count)
            return (room.id, ChoreRoomDetail(summary: summary, chores: assignedChores))
        })
    }

    private func latestCompletedOccurrencesByTemplateId(_ occurrences: [ChoreOccurrence]) -> [UUID: ChoreOccurrence] {
        Dictionary(grouping: occurrences, by: \.templateId).compactMapValues { groupedOccurrences in
            groupedOccurrences
                .filter { $0.status == .completed && $0.completedAt != nil }
                .sorted {
                    guard let lhsCompletedAt = $0.completedAt, let rhsCompletedAt = $1.completedAt else {
                        return $0.completedAt != nil
                    }
                    return lhsCompletedAt > rhsCompletedAt
                }
                .first
        }
    }

    private func nextOccurrencesByTemplateId(_ occurrences: [ChoreOccurrence]) -> [UUID: ChoreOccurrence] {
        let now = Date()
        return Dictionary(grouping: occurrences, by: \.templateId).compactMapValues { groupedOccurrences in
            groupedOccurrences
                .filter { $0.dueAt >= now && $0.status != .cancelled && $0.status != .skipped }
                .sorted { $0.dueAt < $1.dueAt }
                .first
        }
    }

    private func compareRoomChoreDetails(_ lhs: ChoreRoomChoreDetail, _ rhs: ChoreRoomChoreDetail) -> Bool {
        if lhs.chore.isActive != rhs.chore.isActive {
            return lhs.chore.isActive
        }

        switch (lhs.nextOccurrence?.dueAt, rhs.nextOccurrence?.dueAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            let titleComparison = lhs.chore.title.localizedCaseInsensitiveCompare(rhs.chore.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
