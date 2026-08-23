import Combine
import SwiftUI

struct ChoreOccurrenceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel: ChoreOccurrenceDetailViewModel
    @State private var isPresentingManageChore = false

    private let homeTimezone: String

    init(initialOccurrence: ChoreOccurrence, homeTimezone: String) {
        self.homeTimezone = homeTimezone
        _viewModel = StateObject(wrappedValue: ChoreOccurrenceDetailViewModel(initialOccurrence: initialOccurrence))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if viewModel.isLoading {
                            ChoreLoadingState(message: "Loading chore...")
                        } else if let errorMessage = viewModel.errorMessage, viewModel.occurrence == nil {
                            ChoreMessageState(
                                title: "Unable to Open Chore",
                                message: errorMessage,
                                systemImage: "exclamationmark.triangle.fill",
                                buttonTitle: "Try Again"
                            ) {
                                Task { await viewModel.reload() }
                            }
                        } else if let occurrence = viewModel.occurrence {
                            header(for: occurrence)
                            detailSection(for: occurrence)
                            assignmentSection(for: occurrence)
                            requirementsSection(for: occurrence)
                            instructionsSection(for: occurrence)
                            actionsSection(for: occurrence)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(viewModel.isPerformingAction)
                    .accessibilityLabel("Close")
                }
            }
        }
        .task(id: viewModel.occurrence?.id) {
            await loadMembersIfNeeded()
            await viewModel.load(homeId: homeService.selectedHomeID, currentUserId: currentUserId)
        }
        .sheet(isPresented: $isPresentingManageChore) {
            if let occurrence = viewModel.occurrence {
                ChoreEditorView(
                    mode: .edit(templateId: occurrence.templateId),
                    homeId: homeService.selectedHomeID,
                    timezone: homeTimezone
                )
            }
        }
    }

    private var currentUserId: UUID? {
        authenticationService.currentUser?.id
    }

    private var currentRole: HomeMemberRole? {
        guard case .resolved = homeService.permissionResolutionState(currentUser: authenticationService.currentUser) else {
            return nil
        }

        return homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private var canManageChores: Bool {
        switch currentRole {
        case .owner, .admin:
            return true
        case .member, nil:
            return false
        }
    }

    private func header(for occurrence: ChoreOccurrence) -> some View {
        let statusStyle = ChoreOccurrenceStatusStyle(displayStatus: personalDisplayStatus(for: occurrence))

        return VStack(alignment: .leading, spacing: 10) {
            Text(occurrence.titleSnapshot)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                metadataPill(statusStyle.title, color: statusStyle.color)
                metadataPill("\(occurrence.pointsValue) \(occurrence.pointsValue == 1 ? "point" : "points")", color: HomeyDashboardTheme.warmBrown)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 28)
    }

    private func detailSection(for occurrence: ChoreOccurrence) -> some View {
        ChoreOccurrenceDetailSection(title: "Schedule") {
            detailRow("Due", value: dueText(for: occurrence), systemImage: "calendar")
            detailRow("Time", value: timeText(for: occurrence), systemImage: "clock")
            if let recurrenceSummary = viewModel.recurrenceSummary {
                detailRow("Repeats", value: recurrenceSummary, systemImage: "repeat")
            }
            if let categoryName = viewModel.categoryName {
                detailRow("Category", value: categoryName, systemImage: "tag")
            }
            if let roomName = viewModel.roomName {
                detailRow("Room", value: roomName, systemImage: "house")
            }
        }
    }

    private func assignmentSection(for occurrence: ChoreOccurrence) -> some View {
        ChoreOccurrenceDetailSection(title: "Assignment") {
            detailRow("Assigned", value: assignmentText(for: occurrence), systemImage: "person.2")
            if occurrence.assignmentMode == .open {
                Text(openClaimText(for: occurrence))
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requirementsSection(for occurrence: ChoreOccurrence) -> some View {
        ChoreOccurrenceDetailSection(title: "Requirements") {
            detailRow("Approval", value: occurrence.requiresApproval ? "Required" : "Not Required", systemImage: "checkmark.seal")
        }
    }

    @ViewBuilder
    private func instructionsSection(for occurrence: ChoreOccurrence) -> some View {
        if let instructions = occurrence.instructionsSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines), !instructions.isEmpty {
            ChoreOccurrenceDetailSection(title: "Instructions") {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let description = occurrence.descriptionSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            ChoreOccurrenceDetailSection(title: "Details") {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionsSection(for occurrence: ChoreOccurrence) -> some View {
        ChoreOccurrenceDetailSection(title: "Actions") {
            if let actionErrorMessage = viewModel.actionErrorMessage {
                Text(actionErrorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if occurrence.status == .cancelled || occurrence.status == .skipped {
                Text("This chore is read-only.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            } else if canManageChores, viewModel.pendingSubmission != nil {
                reviewActions(for: occurrence)
            } else if personalStatus(for: occurrence) == .completed {
                completedSummary(for: occurrence, assignee: currentUserAssignee(for: occurrence))
            } else {
                availableMemberActions(for: occurrence)
            }

            if canManageChores {
                Button {
                    isPresentingManageChore = true
                } label: {
                    Label("Manage Chore", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(viewModel.isPerformingAction)
                .accessibilityLabel("Manage Chore")
            }
        }
    }

    @ViewBuilder
    private func availableMemberActions(for occurrence: ChoreOccurrence) -> some View {
        if occurrence.assignmentMode == .open, occurrence.claimedBy == nil {
            Button {
                Task { await viewModel.claimChore() }
            } label: {
                actionLabel("Claim Chore", systemImage: "hand.raised")
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(viewModel.isPerformingAction)
            .accessibilityLabel("Claim Chore")
        } else if currentUserCanAct(on: occurrence) {
            let personalStatus = personalStatus(for: occurrence)

            if personalStatus == .notStarted || personalStatus == .inProgress || personalStatus == .needsRedo {
                TextField("Completion note", text: $viewModel.completionNote, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityLabel("Completion note")

                Button {
                    Task { await viewModel.submitChore() }
                } label: {
                    actionLabel("Submit Chore", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(viewModel.isPerformingAction)
                .accessibilityLabel("Submit Chore")
            } else if personalStatus == .awaitingApproval {
                Text("This chore is pending approval.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            } else if personalStatus == .completed {
                completedSummary(for: occurrence, assignee: currentUserAssignee(for: occurrence))
            }
        } else {
            Text("You can view this chore, but there are no actions available for your account.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func completedSummary(for occurrence: ChoreOccurrence, assignee: ChoreOccurrenceAssignee?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let completedAt = assignee?.completedAt ?? occurrence.completedAt {
                detailRow("Completed", value: ChoreOccurrenceDetailFormatters.fullDateTime.string(from: completedAt), systemImage: "checkmark.circle")
            }
            if let approvedAt = occurrence.approvedAt {
                detailRow("Approved", value: ChoreOccurrenceDetailFormatters.fullDateTime.string(from: approvedAt), systemImage: "checkmark.seal")
            } else if occurrence.requiresApproval, let completedAt = assignee?.completedAt {
                detailRow("Approved", value: ChoreOccurrenceDetailFormatters.fullDateTime.string(from: completedAt), systemImage: "checkmark.seal")
            }
            detailRow("Points Awarded", value: "\(occurrence.pointsValue) \(occurrence.pointsValue == 1 ? "point" : "points")", systemImage: "star")
        }
    }

    private func reviewActions(for occurrence: ChoreOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review Completion")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            if let pendingSubmission = viewModel.pendingSubmission {
                detailRow(
                    "Submitted",
                    value: ChoreOccurrenceDetailFormatters.fullDateTime.string(from: pendingSubmission.submittedAt),
                    systemImage: "tray.and.arrow.up"
                )

                if let note = pendingSubmission.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    detailRow("Completion Note", value: note, systemImage: "text.alignleft")
                }

                if pendingSubmission.photoPath != nil {
                    detailRow("Photo Proof", value: "Attached", systemImage: "photo")
                }

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        Task { await viewModel.reviewChore(decision: .needsRedo) }
                    } label: {
                        Label("Needs Redo", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isPerformingAction)
                    .accessibilityLabel("Needs Redo")

                    Button {
                        Task { await viewModel.reviewChore(decision: .approved) }
                    } label: {
                        actionLabel("Approve Chore", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(viewModel.isPerformingAction)
                    .accessibilityLabel("Approve Chore")
                }
            } else {
                Text("No pending submission was found for this chore.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 9) {
            if viewModel.isPerformingAction {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metadataPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func dueText(for occurrence: ChoreOccurrence) -> String {
        ChoreOccurrenceDetailFormatters.fullDate.string(from: occurrence.dueAt)
    }

    private func timeText(for occurrence: ChoreOccurrence) -> String {
        if occurrence.isAllDay {
            return "All Day"
        }
        return "\(ChoreOccurrenceDetailFormatters.time.string(from: occurrence.dueAt)) - \(ChoreOccurrenceDetailFormatters.time.string(from: occurrence.endAt))"
    }

    private func assignmentText(for occurrence: ChoreOccurrence) -> String {
        if occurrence.assignmentMode == .open {
            return "Anyone can claim"
        }

        let names = viewModel.assignedMembers.map(\.displayName)
        switch names.count {
        case 0:
            return "No assigned members found"
        case 1:
            return "Assigned to \(names[0])"
        case 2:
            return "\(names[0]) + \(names[1])"
        default:
            return "\(names.count) people assigned"
        }
    }

    private func openClaimText(for occurrence: ChoreOccurrence) -> String {
        if let claimedBy = occurrence.claimedBy,
           let member = viewModel.member(withUserId: claimedBy) {
            return "Claimed by \(member.displayName)."
        }

        if occurrence.claimedBy != nil {
            return "Already claimed."
        }

        return "This chore is available for any household member to claim."
    }

    private func currentUserCanAct(on occurrence: ChoreOccurrence) -> Bool {
        guard let currentUserId else {
            return false
        }

        if occurrence.assignmentMode == .open {
            return occurrence.claimedBy == currentUserId
        }

        return viewModel.assignees.contains { $0.userId == currentUserId }
    }

    private func currentUserAssignee(for occurrence: ChoreOccurrence) -> ChoreOccurrenceAssignee? {
        guard occurrence.assignmentMode != .open, let currentUserId else {
            return nil
        }

        return viewModel.assignees.first { $0.userId == currentUserId }
    }

    private func personalStatus(for occurrence: ChoreOccurrence) -> ChoreOccurrenceStatus {
        currentUserAssignee(for: occurrence)?.status.personalOccurrenceStatus ?? occurrence.status
    }

    private func personalDisplayStatus(for occurrence: ChoreOccurrence) -> ChoreOccurrenceDisplayStatus {
        let status = personalStatus(for: occurrence)
        return .stored(status)
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHome = homeService.selectedHome(),
              let currentUser = authenticationService.currentUser else {
            return
        }

        if !homeService.hasLoadedMembersForSelectedHome() {
            await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
        }
        viewModel.updateMembers(homeService.membersForSelectedHome())
    }
}

private struct ChoreOccurrenceDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            VStack(alignment: .leading, spacing: 13) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 24)
    }
}

@MainActor
private final class ChoreOccurrenceDetailViewModel: ObservableObject {
    @Published private(set) var occurrence: ChoreOccurrence?
    @Published private(set) var assignees: [ChoreOccurrenceAssignee] = []
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var categories: [ChoreCategory] = []
    @Published private(set) var rooms: [ChoreRoom] = []
    @Published private(set) var recurrenceRule: ChoreRecurrenceRule?
    @Published private(set) var pendingSubmission: ChoreSubmission?
    @Published private(set) var isLoading = false
    @Published private(set) var isPerformingAction = false
    @Published private(set) var errorMessage: String?
    @Published var actionErrorMessage: String?
    @Published var completionNote = ""

    private let repository: ChoresRepository
    private let occurrenceId: UUID
    private var activeHomeId: UUID?
    private var activeCurrentUserId: UUID?

    init(initialOccurrence: ChoreOccurrence, repository: ChoresRepository? = nil) {
        self.occurrence = initialOccurrence
        self.occurrenceId = initialOccurrence.id
        self.repository = repository ?? ChoresRepository()
    }

    var assignedMembers: [HomeMemberDisplay] {
        let users = Set(assignees.map(\.userId))
        return members.filter { users.contains($0.userId) }
    }

    var categoryName: String? {
        guard let categoryId = occurrence?.categoryIdSnapshot else {
            return nil
        }
        return categories.first { $0.id == categoryId }?.name
    }

    var roomName: String? {
        guard let roomId = occurrence?.roomIdSnapshot else {
            return nil
        }
        return rooms.first { $0.id == roomId }?.name
    }

    var recurrenceSummary: String? {
        guard let recurrenceRule else {
            return nil
        }

        switch recurrenceRule.frequency {
        case .none:
            return "One Time"
        case .daily:
            return recurrenceRule.intervalValue == 1 ? "Daily" : "Every \(recurrenceRule.intervalValue) Days"
        case .weekly:
            let dayText = recurrenceRule.weekdays.sorted().compactMap { ChoreOccurrenceDetailFormatters.weekdayNames[$0] }.joined(separator: ", ")
            let prefix = recurrenceRule.intervalValue == 1 ? "Weekly" : "Every \(recurrenceRule.intervalValue) Weeks"
            return dayText.isEmpty ? prefix : "\(prefix) • \(dayText)"
        case .monthly:
            if recurrenceRule.intervalValue == 6 {
                return "Every 6 Months"
            }
            if let day = recurrenceRule.dayOfMonth {
                return recurrenceRule.intervalValue == 1 ? "Monthly • Day \(day)" : "Every \(recurrenceRule.intervalValue) Months • Day \(day)"
            }
            return recurrenceRule.intervalValue == 1 ? "Monthly" : "Every \(recurrenceRule.intervalValue) Months"
        case .yearly:
            if let month = recurrenceRule.monthOfYear, let day = recurrenceRule.dayOfMonth {
                return "Annually • \(ChoreOccurrenceDetailFormatters.monthDay(month: month, day: day))"
            }
            return "Annually"
        }
    }

    func load(homeId: UUID?, currentUserId: UUID?) async {
        activeHomeId = homeId
        activeCurrentUserId = currentUserId
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        actionErrorMessage = nil
        defer { isLoading = false }

        do {
            guard let refreshedOccurrence = try await repository.fetchOccurrence(id: occurrenceId) else {
                occurrence = nil
                errorMessage = "Unable to find the linked chore."
                return
            }

            occurrence = refreshedOccurrence
            async let loadedAssignees = repository.fetchOccurrenceAssignees(occurrenceId: refreshedOccurrence.id)
            async let loadedRule = repository.fetchRecurrenceRule(templateId: refreshedOccurrence.templateId)
            async let loadedPendingSubmission = repository.fetchPendingSubmission(occurrenceId: refreshedOccurrence.id)

            if let activeHomeId {
                async let loadedCategories = repository.fetchCategories(homeId: activeHomeId)
                async let loadedRooms = repository.fetchRooms(homeId: activeHomeId)
                categories = try await loadedCategories
                rooms = try await loadedRooms
            }

            assignees = try await loadedAssignees
            recurrenceRule = try await loadedRule
            pendingSubmission = try await loadedPendingSubmission
            logChoreMemberState(for: refreshedOccurrence)
        } catch {
            errorMessage = "Unable to open this chore."
        }
    }

    func updateMembers(_ loadedMembers: [HomeMemberDisplay]) {
        members = HomeMemberDisplay.sorted(loadedMembers)
    }

    func member(withUserId userId: UUID) -> HomeMemberDisplay? {
        members.first { $0.userId == userId }
    }

    func claimChore() async {
        await performAction(failureMessage: "Unable to claim chore.") {
            try await repository.claimOpenChore(occurrenceId: occurrenceId)
        }
    }

    func submitChore() async {
        await performAction(failureMessage: "Unable to submit chore.") {
            _ = try await repository.submitChore(occurrenceId: occurrenceId, note: completionNote, photoPath: nil)
            completionNote = ""
        }
    }

    func reviewChore(decision: ChoreApprovalDecision) async {
        guard let occurrence else {
            actionErrorMessage = "Unable to find this chore."
            return
        }

        guard let pendingSubmission else {
            actionErrorMessage = "Unable to find the pending submission."
            return
        }

        await performAction(
            failureMessage: decision == .approved ? "Unable to approve this chore. Please try again." : "Unable to request redo. Please try again.",
            permissionMessage: "Only Home owners and admins can approve chores."
        ) {
            try await repository.reviewSubmission(
                submissionId: pendingSubmission.id,
                decision: decision,
                adminNote: nil,
                pointsAwarded: decision == .approved ? max(0, occurrence.pointsValue) : 0
            )
        }
    }

    private func performAction(
        failureMessage: String,
        permissionMessage: String? = nil,
        _ action: () async throws -> Void
    ) async {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        actionErrorMessage = nil
        defer { isPerformingAction = false }

        do {
            try await action()
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            await reload()
        } catch ChoreRepositoryError.ownerOrAdminRequired {
            actionErrorMessage = permissionMessage ?? ChoreRepositoryError.ownerOrAdminRequired.localizedDescription
        } catch ChoreRepositoryError.submissionAlreadyReviewed {
            await reload()
            actionErrorMessage = ChoreRepositoryError.submissionAlreadyReviewed.localizedDescription
        } catch {
            actionErrorMessage = failureMessage
        }
    }

    private func logChoreMemberState(for occurrence: ChoreOccurrence) {
        #if DEBUG
        guard let activeCurrentUserId else {
            return
        }

        let assigneeStatus = assignees.first { $0.userId == activeCurrentUserId }?.status
        print("========== CHORE MEMBER STATE ==========")
        print("occurrence_id: \(occurrence.id.uuidString)")
        print("parent_status: \(occurrence.status.rawValue)")
        print("current_user_id: \(activeCurrentUserId.uuidString)")
        print("assignee_status: \(assigneeStatus?.rawValue ?? "nil")")
        print("can_start: \(assigneeStatus?.canStartChore == true)")
        print("can_submit: \(assigneeStatus?.canSubmitChore == true)")
        print("========================================")
        #endif
    }
}

private enum ChoreOccurrenceDetailFormatters {
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let weekdayNames = [
        0: "Sunday",
        1: "Monday",
        2: "Tuesday",
        3: "Wednesday",
        4: "Thursday",
        5: "Friday",
        6: "Saturday"
    ]

    static func monthDay(month: Int, day: Int) -> String {
        var components = DateComponents()
        components.calendar = .autoupdatingCurrent
        components.year = 2026
        components.month = month
        components.day = day

        guard let date = components.date else {
            return "Month \(month) Day \(day)"
        }

        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
