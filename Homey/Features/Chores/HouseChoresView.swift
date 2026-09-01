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
                viewModel.reload()
            }
        }
        .sheet(item: $editingChore) { chore in
            ChoreEditorView(
                mode: .edit(templateId: chore.id),
                homeId: homeService.selectedHomeID,
                timezone: homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
            )
        }
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

    private var canManageRooms: Bool {
        switch homeService.selectedHomeRole {
        case .owner, .admin:
            return true
        case .member, nil:
            return false
        }
    }

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
                    rooms: viewModel.rooms,
                    canEdit: canManageRooms,
                    savingRoomId: viewModel.savingRoomId,
                    onSave: { room, roomType, preferredWeekday, preferredFrequency in
                        await viewModel.updateRoomMetadata(
                            room: room,
                            roomType: roomType,
                            preferredCleaningWeekday: preferredWeekday,
                            preferredCleaningFrequency: preferredFrequency
                        )
                    }
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
    let rooms: [ChoreRoom]
    let canEdit: Bool
    let savingRoomId: UUID?
    let onSave: (ChoreRoom, ChoreRoomType?, ChorePreferredCleaningWeekday?, ChoreRoomCleaningFrequency?) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rooms")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            if rooms.isEmpty {
                Text("No rooms yet.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(rooms) { room in
                        ChoreRoomMetadataRow(
                            room: room,
                            canEdit: canEdit,
                            isSaving: savingRoomId == room.id,
                            onSave: onSave
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ChoreRoomMetadataRow: View {
    let room: ChoreRoom
    let canEdit: Bool
    let isSaving: Bool
    let onSave: (ChoreRoom, ChoreRoomType?, ChorePreferredCleaningWeekday?, ChoreRoomCleaningFrequency?) async -> Void

    @State private var roomType: ChoreRoomType?
    @State private var preferredWeekday: ChorePreferredCleaningWeekday?
    @State private var preferredFrequency: ChoreRoomCleaningFrequency?

    init(
        room: ChoreRoom,
        canEdit: Bool,
        isSaving: Bool,
        onSave: @escaping (ChoreRoom, ChoreRoomType?, ChorePreferredCleaningWeekday?, ChoreRoomCleaningFrequency?) async -> Void
    ) {
        self.room = room
        self.canEdit = canEdit
        self.isSaving = isSaving
        self.onSave = onSave
        _roomType = State(initialValue: room.roomType)
        _preferredWeekday = State(initialValue: room.preferredCleaningWeekday)
        _preferredFrequency = State(initialValue: room.preferredCleaningFrequency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoomCleaningSummaryView(
                summary: RoomCleaningSummary(
                    room: room,
                    lastCleanedAt: room.lastCleanedAt,
                    completedChoreCount: 0
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                Picker("Room Type", selection: $roomType) {
                    Text("Other").tag(nil as ChoreRoomType?)
                    ForEach(ChoreRoomType.allCases) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                }

                Picker("Preferred Cleaning Day", selection: $preferredWeekday) {
                    Text("No Preference").tag(nil as ChorePreferredCleaningWeekday?)
                    ForEach(ChorePreferredCleaningWeekday.allCases) { weekday in
                        Text(weekday.displayName).tag(Optional(weekday))
                    }
                }

                Picker("General Cleaning", selection: $preferredFrequency) {
                    Text("Not Set").tag(nil as ChoreRoomCleaningFrequency?)
                    ForEach(ChoreRoomCleaningFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(Optional(frequency))
                    }
                }
            }
            .pickerStyle(.menu)
            .font(.subheadline.weight(.semibold))
            .disabled(!canEdit || isSaving)

            if canEdit {
                Button {
                    Task {
                        await onSave(room, roomType, preferredWeekday, preferredFrequency)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text("Save")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(isSaving || !hasChanges)
            }
        }
        .padding(12)
        .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1)
        }
        .onChange(of: room.id) { _, _ in
            roomType = room.roomType
            preferredWeekday = room.preferredCleaningWeekday
            preferredFrequency = room.preferredCleaningFrequency
        }
    }

    private var hasChanges: Bool {
        roomType != room.roomType
            || preferredWeekday != room.preferredCleaningWeekday
            || preferredFrequency != room.preferredCleaningFrequency
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
        guard let recurrenceRule = summary.recurrenceRule else {
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

    private func weekdaySummary(_ weekdays: [Int]) -> String {
        let names = weekdays
            .sorted()
            .compactMap { Self.weekdayNames[$0] }

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

    private func monthName(_ month: Int?) -> String {
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
                switch (lhs.nextOccurrence?.dueAt, rhs.nextOccurrence?.dueAt) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.chore.title.localizedCaseInsensitiveCompare(rhs.chore.title) == .orderedAscending
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

@MainActor
private final class HouseChoresRoomsViewModel: ObservableObject {
    @Published private(set) var rooms: [ChoreRoom] = []
    @Published private(set) var isLoading = false
    @Published private(set) var savingRoomId: UUID?
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
            rooms = try await repository.fetchRooms(homeId: homeId)
        } catch {
            rooms = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId)
        }
    }

    func updateRoomMetadata(
        room: ChoreRoom,
        roomType: ChoreRoomType?,
        preferredCleaningWeekday: ChorePreferredCleaningWeekday?,
        preferredCleaningFrequency: ChoreRoomCleaningFrequency?
    ) async {
        guard savingRoomId == nil else { return }

        savingRoomId = room.id
        errorMessage = nil
        defer { savingRoomId = nil }

        do {
            try await repository.updateRoom(
                roomId: room.id,
                name: room.name,
                sortOrder: room.sortOrder,
                roomType: roomType,
                preferredCleaningWeekday: preferredCleaningWeekday,
                preferredCleaningFrequency: preferredCleaningFrequency
            )
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        activeHomeId = nil
        rooms = []
        errorMessage = nil
        isLoading = false
        savingRoomId = nil
    }
}
