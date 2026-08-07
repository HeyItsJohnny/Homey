import Combine
import SwiftUI

struct ChoreEditorView: View {
    enum Mode: Equatable {
        case add
        case edit(templateId: UUID)

        var title: String {
            switch self {
            case .add:
                return "Add Chore"
            case .edit:
                return "Edit Chore"
            }
        }

        var saveTitle: String {
            switch self {
            case .add, .edit:
                return "Save"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel: ChoreEditorViewModel
    @State private var isDeleteConfirmationPresented = false

    private let mode: Mode
    private let homeId: UUID?
    private let homeTimezone: String

    init(
        mode: Mode = .add,
        homeId: UUID?,
        timezone: String,
        repository: ChoresRepository? = nil
    ) {
        self.mode = mode
        self.homeId = homeId
        self.homeTimezone = timezone
        _viewModel = StateObject(wrappedValue: ChoreEditorViewModel(repository: repository))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                if !canManageChores {
                    unauthorizedContent
                } else if viewModel.isLoadingChore {
                    ChoreLoadingState(message: "Loading chore...")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            header
                            formContent
                        }
                        .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 28)
                        .padding(.top, 28)
                        .padding(.bottom, 34)
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 980)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving || viewModel.isDeleting)
                    .accessibilityLabel("Cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(HomeyDashboardTheme.warmBrown)
                                .accessibilityLabel("Saving chore")
                        } else {
                            Text(mode.saveTitle)
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(mode.saveTitle)
                }
            }
        }
        .task(id: homeId) {
            await viewModel.configure(homeId: homeId, timezone: homeTimezone, mode: mode)
            await loadMembersIfNeeded()
        }
        .onChange(of: homeService.membersForSelectedHome()) { _, members in
            viewModel.updateMembers(members)
        }
        .confirmationDialog(
            "Delete Chore?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Chore", role: .destructive) {
                Task { await deleteChore() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop this chore from being scheduled again and remove all future calendar events. Past chore history, completed chores, points, approvals, and rewards will be kept.")
        }
        .presentationDetents([.large])
    }

    private var canManageChores: Bool {
        switch currentRole {
        case .owner, .admin:
            return true
        case .member, nil:
            return false
        }
    }

    private var currentRole: HomeMemberRole? {
        guard case .resolved = homeService.permissionResolutionState(currentUser: authenticationService.currentUser) else {
            return nil
        }

        return homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    private var canSave: Bool {
        canManageChores && viewModel.canSave
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(mode == .add ? "Create a scheduled chore for your Home." : "Update this household chore.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var formContent: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 18) {
                leftColumn
                rightColumn
                deleteSection
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    leftColumn
                    rightColumn
                }
                deleteSection
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailsSection
            assignmentSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            scheduleSection
            recurrenceSection
            requirementsSection
            pointsSection
            summarySection
            if let saveErrorMessage = viewModel.saveErrorMessage {
                errorCard(saveErrorMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var detailsSection: some View {
        ChoreEditorSection(title: "Chore Details") {
            editorTextField(
                label: "Chore Name",
                supportingText: "Required",
                text: $viewModel.title,
                axis: .horizontal,
                characterLimit: ChoreEditorViewModel.titleLimit
            )

            editorTextField(
                label: "Description",
                supportingText: "Optional",
                text: $viewModel.choreDescription,
                axis: .vertical,
                characterLimit: ChoreEditorViewModel.descriptionLimit
            )

            editorTextField(
                label: "Instructions",
                supportingText: "Optional",
                text: $viewModel.instructions,
                axis: .vertical,
                characterLimit: ChoreEditorViewModel.instructionsLimit
            )

            lookupPicker(
                title: "Category",
                selectedTitle: viewModel.selectedCategoryName,
                emptyTitle: "No Category",
                isLoading: viewModel.isLoadingLookups,
                errorMessage: viewModel.lookupErrorMessage,
                retry: { Task { await viewModel.loadLookups() } }
            ) {
                Button("No Category") { viewModel.categoryId = nil }
                ForEach(viewModel.categories) { category in
                    Button(category.name) { viewModel.categoryId = category.id }
                }
            }

            lookupPicker(
                title: "Room",
                selectedTitle: viewModel.selectedRoomName,
                emptyTitle: "No Room",
                isLoading: viewModel.isLoadingLookups,
                errorMessage: viewModel.lookupErrorMessage,
                retry: { Task { await viewModel.loadLookups() } }
            ) {
                Button("No Room") { viewModel.roomId = nil }
                ForEach(viewModel.rooms) { room in
                    Button(room.name) { viewModel.roomId = room.id }
                }
            }
        }
    }

    private var assignmentSection: some View {
        ChoreEditorSection(title: "Assignment") {
            Picker("Assignment Type", selection: $viewModel.assignmentMode) {
                Text("Assigned").tag(ChoreAssignmentMode.assigned)
                Text("Open Chore").tag(ChoreAssignmentMode.open)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Assignment type")

            if viewModel.assignmentMode == .open {
                helperText("This chore will be available for any household member to claim.")
            } else {
                memberSelector
                completionModeSelector
            }
        }
    }

    private var memberSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Members", supportingText: "Choose one or more assignees.")

            if viewModel.members.isEmpty {
                helperText("Members will appear here after they load.")
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.members) { member in
                        Button {
                            viewModel.toggleAssignee(member.userId)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    imageURL: member.avatarURL,
                                    initials: member.initials,
                                    size: 38,
                                    accentColor: HomeyDashboardTheme.sageAccent,
                                    borderColor: HomeyDashboardTheme.appBackground,
                                    borderWidth: 2,
                                    showsShadow: false,
                                    accessibilityLabel: "\(member.displayName) avatar"
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                                    if let email = member.email, !email.isEmpty {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: viewModel.assigneeIds.contains(member.userId) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(viewModel.assigneeIds.contains(member.userId) ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(member.displayName), \(viewModel.assigneeIds.contains(member.userId) ? "selected" : "not selected")")

                        if member.id != viewModel.members.last?.id {
                            Divider()
                                .overlay(HomeyDashboardTheme.softBorder)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(fieldBackground)
            }
        }
    }

    private var completionModeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Completion Rule", supportingText: viewModel.completionModeHelpText)

            Picker("Completion Rule", selection: $viewModel.completionMode) {
                ForEach(viewModel.availableCompletionModes, id: \.self) { mode in
                    Text(viewModel.label(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Completion rule")
        }
    }

    private var scheduleSection: some View {
        ChoreEditorSection(title: "Schedule") {
            DatePicker("Due Date", selection: $viewModel.startDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(16)
                .background(fieldBackground)
                .accessibilityLabel("Due date")

            Toggle("All-Day Chore", isOn: $viewModel.isAllDay)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .tint(HomeyDashboardTheme.warmBrown)
                .padding(16)
                .background(fieldBackground)
                .accessibilityLabel("All-day chore")

            if !viewModel.isAllDay {
                DatePicker("Due Time", selection: $viewModel.dueDateTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .padding(16)
                    .background(fieldBackground)
                    .accessibilityLabel("Due time")

                Picker("Duration", selection: $viewModel.durationMinutes) {
                    ForEach(ChoreDurationOption.allCases) { option in
                        Text(option.title).tag(option.minutes)
                    }
                }
                .pickerStyle(.menu)
                .font(.body.weight(.medium))
                .padding(16)
                .background(fieldBackground)
                .accessibilityLabel("Duration")
            }
        }
    }

    private var recurrenceSection: some View {
        ChoreEditorSection(title: "Recurrence") {
            Picker("Recurrence", selection: $viewModel.recurrenceOption) {
                ForEach(ChoreRecurrenceOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(.body.weight(.medium))
            .padding(16)
            .background(fieldBackground)
            .accessibilityLabel("Recurrence")

            recurrenceDetails

            if viewModel.recurrenceOption.isRecurring {
                recurrenceEndingSection
            }
        }
    }

    @ViewBuilder
    private var recurrenceDetails: some View {
        switch viewModel.recurrenceOption {
        case .oneTime:
            EmptyView()
        case .daily:
            intervalStepper(label: "Every \(viewModel.intervalValue) \(viewModel.intervalValue == 1 ? "day" : "days")")
        case .weekly:
            intervalStepper(label: "Every \(viewModel.intervalValue) \(viewModel.intervalValue == 1 ? "week" : "weeks")")
            weekdaySelector
        case .monthly:
            intervalStepper(label: "Every \(viewModel.intervalValue) \(viewModel.intervalValue == 1 ? "month" : "months")")
            dayOfMonthPicker
            helperText("If a month does not contain this date, Homey will use that month's last valid day.")
        case .everySixMonths:
            dayOfMonthPicker
            helperText("Occurs twice per year.")
        case .annually:
            monthPicker
            dayOfMonthPicker
        }
    }

    private var weekdaySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Weekdays", supportingText: "Choose at least one weekday.")

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ChoreWeekday.allCases) { weekday in
                        Button {
                            viewModel.toggleWeekday(weekday.value)
                        } label: {
                            Text(weekday.shortTitle)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(viewModel.weekdays.contains(weekday.value) ? .white : HomeyDashboardTheme.primaryText)
                                .frame(width: 42, height: 38)
                                .background(viewModel.weekdays.contains(weekday.value) ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.appBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(weekday.title), \(viewModel.weekdays.contains(weekday.value) ? "selected" : "not selected")")
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var dayOfMonthPicker: some View {
        Picker("Day of Month", selection: $viewModel.dayOfMonth) {
            ForEach(1...31, id: \.self) { day in
                Text("\(day)").tag(day)
            }
        }
        .pickerStyle(.menu)
        .font(.body.weight(.medium))
        .padding(16)
        .background(fieldBackground)
        .accessibilityLabel("Day of month")
    }

    private var monthPicker: some View {
        Picker("Month", selection: $viewModel.monthOfYear) {
            ForEach(1...12, id: \.self) { month in
                Text(Calendar.current.monthSymbols[month - 1]).tag(month)
            }
        }
        .pickerStyle(.menu)
        .font(.body.weight(.medium))
        .padding(16)
        .background(fieldBackground)
        .accessibilityLabel("Month")
    }

    private var recurrenceEndingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Ending", supportingText: "Choose when this recurrence stops.")

            Picker("Recurrence Ending", selection: $viewModel.endType) {
                Text("Never Ends").tag(ChoreRecurrenceEndType.never)
                Text("End On Date").tag(ChoreRecurrenceEndType.onDate)
                Text("End After Count").tag(ChoreRecurrenceEndType.afterCount)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Recurrence ending")

            switch viewModel.endType {
            case .never:
                EmptyView()
            case .onDate:
                DatePicker("End Date", selection: $viewModel.endsOn, in: viewModel.startDate..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .padding(16)
                    .background(fieldBackground)
                    .accessibilityLabel("End date")
            case .afterCount:
                Stepper(value: $viewModel.occurrenceCount, in: 1...999) {
                    Text("\(viewModel.occurrenceCount) \(viewModel.occurrenceCount == 1 ? "occurrence" : "occurrences")")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                }
                .tint(HomeyDashboardTheme.warmBrown)
                .padding(16)
                .background(fieldBackground)
                .accessibilityLabel("End after number of occurrences")
            }
        }
    }

    private var requirementsSection: some View {
        ChoreEditorSection(title: "Completion Requirements") {
            Toggle("Require Approval", isOn: $viewModel.requiresApproval)
                .tint(HomeyDashboardTheme.warmBrown)
                .accessibilityLabel("Require approval")
            helperText("An owner or admin must approve completion before points are awarded.")

            Toggle("Require Photo Proof", isOn: $viewModel.requiresPhoto)
                .tint(HomeyDashboardTheme.warmBrown)
                .accessibilityLabel("Require photo proof")
            helperText("The member must attach a photo when completing the chore.")
        }
    }

    private var pointsSection: some View {
        ChoreEditorSection(title: "Points") {
            Stepper(value: $viewModel.pointsValue, in: 0...9999) {
                Text("\(viewModel.pointsValue) Points")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
            }
            .tint(HomeyDashboardTheme.warmBrown)
            .padding(16)
            .background(fieldBackground)
            .accessibilityLabel("Points")

            helperText("Points are awarded when the chore is completed and approved, if approval is required.")
        }
    }

    private var summarySection: some View {
        ChoreEditorSection(title: "Calendar Summary") {
            Text(viewModel.calendarSummary)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fieldBackground)
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if mode.isEdit {
            ChoreEditorSection(title: "Delete Chore") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Stops this chore from being scheduled again.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text("Past history, earned points, approvals, and rewards will be kept.")
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let deleteErrorMessage = viewModel.deleteErrorMessage {
                        Text(deleteErrorMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        HStack(spacing: 9) {
                            if viewModel.isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text(viewModel.isDeleting ? "Deleting..." : "Delete Chore")
                        }
                        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 220)
                    }
                    .buttonStyle(ChoreDestructiveButtonStyle())
                    .disabled(!canManageChores || viewModel.isSaving || viewModel.isDeleting || viewModel.isLoadingChore)
                    .accessibilityLabel("Delete Chore")
                }
            }
        }
    }

    private var unauthorizedContent: some View {
        ChoreMessageState(
            title: "Chores Unavailable",
            message: "Only an owner or admin can create chores in this Home.",
            systemImage: "lock.fill"
        )
        .padding(28)
        .frame(maxWidth: 520)
    }

    private var fieldBackground: some ShapeStyle {
        HomeyDashboardTheme.appBackground.opacity(0.62)
    }

    private func intervalStepper(label: String) -> some View {
        Stepper(value: $viewModel.intervalValue, in: 1...99) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .tint(HomeyDashboardTheme.warmBrown)
        .padding(16)
        .background(fieldBackground)
        .accessibilityLabel("Recurrence interval")
    }

    private func editorTextField(label: String, supportingText: String, text: Binding<String>, axis: Axis, characterLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(label, supportingText: supportingText)

            TextField(label, text: limitedBinding(text, limit: characterLimit), axis: axis)
                .textInputAutocapitalization(.sentences)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, axis == .vertical ? 14 : 10)
                .frame(minHeight: axis == .vertical ? 96 : 54, alignment: axis == .vertical ? .topLeading : .center)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
                .disabled(viewModel.isSaving)
                .accessibilityLabel(label)
        }
    }

    private func lookupPicker<Content: View>(
        title: String,
        selectedTitle: String,
        emptyTitle: String,
        isLoading: Bool,
        errorMessage: String?,
        retry: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(title, supportingText: "Optional")

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HomeyDashboardTheme.warmBrown)
                    Text("Loading \(title.lowercased())...")
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    Button("Try Again", action: retry)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Menu {
                    content()
                } label: {
                    HStack(spacing: 12) {
                        Text(selectedTitle.isEmpty ? emptyTitle : selectedTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .background(fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(selectedTitle.isEmpty ? emptyTitle : selectedTitle)")
            }
        }
    }

    private func sectionLabel(_ title: String, supportingText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(supportingText)
                .font(.caption)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyDashboardTheme.destructiveRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.22), lineWidth: 1)
            }
    }

    private func limitedBinding(_ binding: Binding<String>, limit: Int) -> Binding<String> {
        Binding {
            binding.wrappedValue
        } set: { newValue in
            binding.wrappedValue = String(newValue.prefix(limit))
        }
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHome = homeService.selectedHome(),
              let currentUser = authenticationService.currentUser else {
            viewModel.updateMembers([])
            return
        }

        if !homeService.hasLoadedMembersForSelectedHome() {
            await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
        }

        viewModel.updateMembers(homeService.membersForSelectedHome())
    }

    private func save() async {
        await viewModel.save(currentRole: currentRole)
        if viewModel.didCompleteSave {
            dismiss()
        }
    }

    private func deleteChore() async {
        await viewModel.deleteChore(currentRole: currentRole)
        if viewModel.didCompleteDelete {
            dismiss()
        }
    }
}

private extension ChoreEditorView.Mode {
    var isEdit: Bool {
        if case .edit = self {
            return true
        }
        return false
    }
}

private struct ChoreEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: 26)
    }
}

private struct ChoreDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(HomeyDashboardTheme.destructiveRed.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

@MainActor
final class ChoreEditorViewModel: ObservableObject {
    static let titleLimit = 80
    static let descriptionLimit = 240
    static let instructionsLimit = 1_000

    @Published var title = "" { didSet { updateSaveErrorForValidation() } }
    @Published var choreDescription = ""
    @Published var instructions = ""
    @Published var categoryId: UUID?
    @Published var roomId: UUID?
    @Published var assignmentMode: ChoreAssignmentMode = .assigned {
        didSet { normalizeAssignmentMode() }
    }
    @Published var completionMode: ChoreCompletionMode = .single {
        didSet { normalizeCompletionMode() }
    }
    @Published var assigneeIds: Set<UUID> = [] {
        didSet { normalizeAssignees() }
    }
    @Published var startDate = Date() {
        didSet { updateDateDefaults() }
    }
    @Published var isAllDay = true {
        didSet { updateSaveErrorForValidation() }
    }
    @Published var dueDateTime = Date()
    @Published var durationMinutes = 30
    @Published var recurrenceOption: ChoreRecurrenceOption = .oneTime {
        didSet { applyRecurrenceOptionDefaults() }
    }
    @Published var intervalValue = 1
    @Published var weekdays: Set<Int> = []
    @Published var dayOfMonth = Calendar.current.component(.day, from: Date())
    @Published var monthOfYear = Calendar.current.component(.month, from: Date())
    @Published var endType: ChoreRecurrenceEndType = .never
    @Published var endsOn = Date()
    @Published var occurrenceCount = 10
    @Published var requiresApproval = true
    @Published var requiresPhoto = false
    @Published var pointsValue = 0 { didSet { if pointsValue < 0 { pointsValue = 0 } } }
    @Published private(set) var categories: [ChoreCategory] = []
    @Published private(set) var rooms: [ChoreRoom] = []
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var isLoadingLookups = false
    @Published private(set) var lookupErrorMessage: String?
    @Published private(set) var isLoadingChore = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDeleting = false
    @Published private(set) var saveErrorMessage: String?
    @Published private(set) var deleteErrorMessage: String?
    @Published private(set) var didCompleteSave = false
    @Published private(set) var didCompleteDelete = false

    private let repository: ChoresRepository
    private let calendarService: CalendarService
    private var calendarSyncService: ChoreCalendarSyncService?
    private var activeHomeId: UUID?
    private var timezone = TimeZone.autoupdatingCurrent.identifier
    private var savedTemplateId: UUID?
    private var isNormalizing = false
    private var isApplyingLoadedChore = false
    private var isEditingExistingChore = false

    init(repository: ChoresRepository? = nil, calendarService: CalendarService? = nil) {
        self.repository = repository ?? ChoresRepository()
        self.calendarService = calendarService ?? CalendarService()
        self.weekdays = [Self.weekdayValue(for: Date())]
    }

    var selectedCategoryName: String {
        categories.first { $0.id == categoryId }?.name ?? "No Category"
    }

    var selectedRoomName: String {
        rooms.first { $0.id == roomId }?.name ?? "No Room"
    }

    var availableCompletionModes: [ChoreCompletionMode] {
        assigneeIds.count <= 1 ? [.single] : [.anyAssignee, .everyone]
    }

    var completionModeHelpText: String {
        switch completionMode {
        case .single:
            return "Only one assigned person needs to complete this chore."
        case .anyAssignee:
            return "Only one assigned person needs to complete this chore."
        case .everyone:
            return "Every assigned person must complete their part."
        }
    }

    var canSave: Bool {
        validationMessage == nil && !isSaving && !isDeleting
    }

    var calendarSummary: String {
        let name = trimmedTitle.isEmpty ? "This chore" : trimmedTitle
        let timeText = isAllDay ? "" : " at \(dueDateTime.formatted(date: .omitted, time: .shortened))"
        let openText = assignmentMode == .open ? " This will appear as an open chore that any household member can claim." : ""

        switch recurrenceOption {
        case .oneTime:
            let dateText = startDate.formatted(date: .complete, time: .omitted)
            if isAllDay {
                return "\(name) will appear as an all-day chore on \(dateText).\(openText)"
            }
            return "\(name) will appear on the Homey Calendar on \(dateText)\(timeText).\(openText)"
        case .daily:
            return "\(name) will appear every \(intervalValue == 1 ? "day" : "\(intervalValue) days")\(timeText).\(openText)"
        case .weekly:
            let days = ChoreWeekday.summary(for: weekdays)
            return "\(name) will appear every \(intervalValue == 1 ? "week" : "\(intervalValue) weeks") on \(days)\(timeText).\(openText)"
        case .monthly:
            return "\(name) will appear every \(intervalValue == 1 ? "month" : "\(intervalValue) months") on day \(dayOfMonth)\(timeText).\(openText)"
        case .everySixMonths:
            return "\(name) will appear every 6 months on day \(dayOfMonth)\(timeText).\(openText)"
        case .annually:
            let month = Calendar.current.monthSymbols[monthOfYear - 1]
            return "\(name) will appear every year on \(month) \(dayOfMonth)\(timeText).\(openText)"
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        if activeHomeId == nil {
            return "Choose a Home before creating a chore."
        }

        if trimmedTitle.isEmpty {
            return "Enter a chore name."
        }

        if assignmentMode == .assigned && assigneeIds.isEmpty {
            return "Choose at least one assignee or make this an open chore."
        }

        if assignmentMode == .open && !assigneeIds.isEmpty {
            return "Open chores cannot have selected assignees."
        }

        if recurrenceOption == .weekly && weekdays.isEmpty {
            return "Choose at least one weekday."
        }

        if recurrenceOption.isRecurring && endType == .onDate && Calendar.current.startOfDay(for: endsOn) < Calendar.current.startOfDay(for: startDate) {
            return "End date cannot be before the start date."
        }

        if recurrenceOption.isRecurring && endType == .afterCount && occurrenceCount < 1 {
            return "Enter a positive occurrence count."
        }

        if pointsValue < 0 {
            return "Points cannot be negative."
        }

        return nil
    }

    func configure(homeId: UUID?, timezone: String, mode: ChoreEditorView.Mode = .add) async {
        activeHomeId = homeId
        self.timezone = TimeZone(identifier: timezone) == nil ? TimeZone.autoupdatingCurrent.identifier : timezone
        endsOn = Calendar.current.date(byAdding: .month, value: 3, to: startDate) ?? startDate
        updateDateDefaults()
        updateSaveErrorForValidation()
        await loadLookups()

        if case .edit(let templateId) = mode {
            isEditingExistingChore = true
            await loadExistingChore(templateId: templateId)
        } else {
            isEditingExistingChore = false
            savedTemplateId = nil
        }
    }

    func loadExistingChore(templateId: UUID) async {
        isLoadingChore = true
        saveErrorMessage = nil
        deleteErrorMessage = nil
        defer { isLoadingChore = false }

        do {
            guard let chore = try await repository.fetchTemplate(id: templateId) else {
                saveErrorMessage = "Unable to load this chore."
                return
            }

            let recurrenceRule = try await repository.fetchRecurrenceRule(templateId: templateId)
            let assignees = try await repository.fetchTemplateAssignees(templateId: templateId)
            apply(chore: chore, recurrenceRule: recurrenceRule, assignees: assignees)
        } catch {
            saveErrorMessage = "Unable to load this chore."
        }
    }

    func updateMembers(_ loadedMembers: [HomeMemberDisplay]) {
        members = HomeMemberDisplay.sorted(loadedMembers)
        assigneeIds = assigneeIds.filter { userId in
            members.contains { $0.userId == userId }
        }
    }

    func loadLookups() async {
        guard let activeHomeId else {
            categories = []
            rooms = []
            lookupErrorMessage = nil
            return
        }

        isLoadingLookups = true
        lookupErrorMessage = nil

        do {
            async let loadedCategories = repository.fetchCategories(homeId: activeHomeId)
            async let loadedRooms = repository.fetchRooms(homeId: activeHomeId)
            categories = try await loadedCategories.filter { $0.archivedAt == nil }
            rooms = try await loadedRooms.filter { $0.archivedAt == nil }
        } catch {
            categories = []
            rooms = []
            lookupErrorMessage = "Unable to load categories and rooms."
        }

        isLoadingLookups = false
    }

    func toggleAssignee(_ userId: UUID) {
        if assigneeIds.contains(userId) {
            assigneeIds.remove(userId)
        } else {
            assigneeIds.insert(userId)
        }
    }

    func toggleWeekday(_ weekday: Int) {
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        updateSaveErrorForValidation()
    }

    func label(for mode: ChoreCompletionMode) -> String {
        switch mode {
        case .single:
            return "One Person"
        case .anyAssignee:
            return "Any Assigned"
        case .everyone:
            return "Everyone"
        }
    }

    func save(currentRole: HomeMemberRole?) async {
        guard !isSaving else {
            return
        }

        guard currentRole == .owner || currentRole == .admin else {
            saveErrorMessage = "Only an owner or admin can save chores."
            return
        }

        guard validationMessage == nil else {
            updateSaveErrorForValidation()
            return
        }

        isSaving = true
        didCompleteSave = false
        saveErrorMessage = nil
        deleteErrorMessage = nil
        defer { isSaving = false }

        do {
            let draft = try makeDraft()
            let templateId: UUID
            var replacementResult: ChoreOccurrenceReplacementResult?
            var deletedCalendarEventCount = 0
            if isEditingExistingChore {
                templateId = try await repository.saveTemplate(draft: draft)
                savedTemplateId = templateId
                logChoreRecurrenceSaved(choreId: templateId, draft: draft)
            } else if let savedTemplateId {
                templateId = savedTemplateId
            } else {
                templateId = try await repository.saveTemplate(draft: draft)
                savedTemplateId = templateId
            }

            guard let activeHomeId else {
                throw ChoreEditorSaveError.homeUnavailable
            }

            let through = generationEndDate()
            if isEditingExistingChore {
                let effectiveFrom = futureReplacementEffectiveDate()
                let replacement = try await repository.replaceFutureOccurrences(
                    templateId: templateId,
                    effectiveFrom: effectiveFrom,
                    generateThrough: through,
                    timezone: timezone
                )
                replacementResult = replacement
                deletedCalendarEventCount = try await deleteCalendarEvents(replacement.calendarEventIds)
            }

            let occurrences = try await repository.generateOccurrences(templateId: templateId, through: through, timezone: timezone)
            let syncService = calendarSyncService ?? ChoreCalendarSyncService(choresRepository: repository)
            calendarSyncService = syncService
            let calendarEventsToCreate = occurrences.filter { $0.calendarEventId == nil }.count
            _ = try await syncService.syncMissingCalendarEvents(homeId: activeHomeId, occurrences: occurrences)
            if let replacementResult {
                logFutureScheduleReplaced(
                    oldFutureOccurrencesRemoved: replacementResult.removedOccurrenceIds.count,
                    newFutureOccurrencesGenerated: occurrences.count,
                    calendarEventsRemoved: deletedCalendarEventCount,
                    calendarEventsCreated: calendarEventsToCreate
                )
            }

            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            NotificationCenter.default.post(
                name: .homeyCalendarEventsDidChange,
                object: nil,
                userInfo: [HomeyCalendarRefreshReason.userInfoKey: HomeyCalendarRefreshReason.choreEditSaved]
            )
            didCompleteSave = true
        } catch let error as ChoreValidationError {
            saveErrorMessage = error.localizedDescription
        } catch let error as ChoreEditorSaveError {
            saveErrorMessage = error.localizedDescription
        } catch {
            if savedTemplateId != nil {
                saveErrorMessage = "The chore was saved, but Calendar synchronization failed. Try Save again to retry calendar linking without creating a duplicate chore."
            } else {
                saveErrorMessage = "Unable to save this chore. Check the details and try again."
            }
        }
    }

    func deleteChore(currentRole: HomeMemberRole?) async {
        guard !isDeleting, !isSaving else {
            return
        }

        guard currentRole == .owner || currentRole == .admin else {
            deleteErrorMessage = "You no longer have permission to delete this chore."
            return
        }

        guard let savedTemplateId else {
            deleteErrorMessage = "Unable to delete this chore."
            return
        }

        isDeleting = true
        didCompleteDelete = false
        saveErrorMessage = nil
        deleteErrorMessage = nil
        defer { isDeleting = false }

        do {
            let retiredChore = try await repository.retireChore(templateId: savedTemplateId, effectiveFrom: Date())
            var failedCalendarDeletion = false

            for calendarEventId in retiredChore.calendarEventIds {
                do {
                    try await calendarService.deleteEvent(eventId: calendarEventId)
                } catch {
                    failedCalendarDeletion = true
                }
            }

            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)

            if failedCalendarDeletion {
                deleteErrorMessage = "The chore was deleted, but some future calendar events could not be removed. Please retry calendar sync."
                return
            }

            didCompleteDelete = true
        } catch let error as ChoreRepositoryError {
            deleteErrorMessage = deleteMessage(for: error)
        } catch {
            deleteErrorMessage = "Unable to delete this chore."
        }
    }

    private func makeDraft() throws -> ChoreTemplateDraft {
        guard let activeHomeId else {
            throw ChoreEditorSaveError.homeUnavailable
        }

        return try ChoreTemplateDraft(
            id: savedTemplateId,
            homeId: activeHomeId,
            title: title,
            description: choreDescription,
            instructions: instructions,
            categoryId: categoryId,
            roomId: roomId,
            assignmentMode: assignmentMode,
            completionMode: completionMode,
            pointsValue: pointsValue,
            requiresApproval: requiresApproval,
            requiresPhoto: requiresPhoto,
            frequency: recurrenceOption.frequency,
            intervalValue: recurrenceOption == .everySixMonths ? 6 : intervalValue,
            startDate: Calendar.current.startOfDay(for: startDate),
            dueTime: isAllDay ? nil : dueTimeValue(),
            durationMinutes: durationMinutes,
            isAllDay: isAllDay,
            weekdays: recurrenceOption == .weekly ? weekdays : [],
            dayOfMonth: recurrenceOption.usesDayOfMonth ? dayOfMonth : nil,
            monthOfYear: recurrenceOption == .annually ? monthOfYear : nil,
            endType: recurrenceOption == .oneTime ? .afterCount : endType,
            endsOn: recurrenceOption.isRecurring && endType == .onDate ? endsOn : nil,
            occurrenceCount: occurrenceCountValue,
            timezone: timezone,
            assigneeIds: Array(assigneeIds)
        ).validated()
    }

    private var occurrenceCountValue: Int? {
        if recurrenceOption == .oneTime {
            return 1
        }

        return endType == .afterCount ? occurrenceCount : nil
    }

    private func dueTimeValue() -> ChoreLocalTime? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: dueDateTime)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }
        return ChoreLocalTime(hour: hour, minute: minute)
    }

    private func generationEndDate() -> Date {
        let basis = max(Date(), startDate)
        return Calendar.current.date(byAdding: .day, value: ChoresRepository.defaultGenerationWindowDays, to: basis) ?? basis
    }

    private func futureReplacementEffectiveDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
        return calendar.startOfDay(for: Date())
    }

    private func deleteCalendarEvents(_ calendarEventIds: [UUID]) async throws -> Int {
        var deletedCount = 0
        for calendarEventId in calendarEventIds {
            do {
                try await calendarService.deleteEvent(eventId: calendarEventId)
                deletedCount += 1
            } catch {
                #if DEBUG
                print("========== CHORE CALENDAR DELETE FAILED ==========")
                print("calendar_event_id: \(calendarEventId.uuidString)")
                print(String(reflecting: error))
                print("==================================================")
                #endif
                throw ChoreEditorSaveError.calendarCleanupFailed
            }
        }
        return deletedCount
    }

    private func logChoreRecurrenceSaved(choreId: UUID, draft: ChoreTemplateDraft) {
        #if DEBUG
        print("========== CHORE RECURRENCE SAVED ==========")
        print("chore_id: \(choreId.uuidString)")
        print("frequency: \(draft.frequency.rawValue)")
        print("interval: \(draft.intervalValue)")
        print("============================================")
        #endif
    }

    private func logFutureScheduleReplaced(
        oldFutureOccurrencesRemoved: Int,
        newFutureOccurrencesGenerated: Int,
        calendarEventsRemoved: Int,
        calendarEventsCreated: Int
    ) {
        #if DEBUG
        print("========== FUTURE CHORE SCHEDULE REPLACED ==========")
        print("old_future_occurrences_removed: \(oldFutureOccurrencesRemoved)")
        print("new_future_occurrences_generated: \(newFutureOccurrencesGenerated)")
        print("calendar_events_removed: \(calendarEventsRemoved)")
        print("calendar_events_created: \(calendarEventsCreated)")
        print("====================================================")
        #endif
    }

    private func normalizeAssignmentMode() {
        guard !isNormalizing, !isApplyingLoadedChore else {
            return
        }
        isNormalizing = true
        if assignmentMode == .open {
            assigneeIds = []
            completionMode = .single
        }
        isNormalizing = false
        updateSaveErrorForValidation()
    }

    private func normalizeAssignees() {
        guard !isNormalizing, !isApplyingLoadedChore else {
            return
        }
        isNormalizing = true
        if assignmentMode == .assigned {
            if assigneeIds.count <= 1 {
                completionMode = .single
            } else if completionMode == .single {
                completionMode = .anyAssignee
            }
        }
        isNormalizing = false
        updateSaveErrorForValidation()
    }

    private func normalizeCompletionMode() {
        guard !isNormalizing, !isApplyingLoadedChore else {
            return
        }
        isNormalizing = true
        if assignmentMode == .open || assigneeIds.count <= 1 {
            completionMode = .single
        }
        isNormalizing = false
        updateSaveErrorForValidation()
    }

    private func applyRecurrenceOptionDefaults() {
        guard !isApplyingLoadedChore else {
            return
        }

        switch recurrenceOption {
        case .oneTime:
            intervalValue = 1
            endType = .afterCount
            occurrenceCount = 1
        case .daily, .weekly, .monthly, .annually:
            intervalValue = 1
            if endType == .afterCount && occurrenceCount == 1 {
                occurrenceCount = 10
            }
        case .everySixMonths:
            intervalValue = 6
            if endType == .afterCount && occurrenceCount == 1 {
                occurrenceCount = 10
            }
        }
        updateDateDefaults()
        updateSaveErrorForValidation()
    }

    private func updateDateDefaults() {
        guard !isApplyingLoadedChore else {
            return
        }

        dayOfMonth = Calendar.current.component(.day, from: startDate)
        monthOfYear = Calendar.current.component(.month, from: startDate)
        if recurrenceOption == .weekly && weekdays.isEmpty {
            weekdays = [Self.weekdayValue(for: startDate)]
        }
        if endsOn < startDate {
            endsOn = startDate
        }
        updateSaveErrorForValidation()
    }

    private func updateSaveErrorForValidation() {
        guard !isApplyingLoadedChore else {
            return
        }

        if let validationMessage {
            saveErrorMessage = validationMessage
        } else if saveErrorMessage == validationMessage {
            saveErrorMessage = nil
        }
    }

    private static func weekdayValue(for date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    private func deleteMessage(for error: ChoreRepositoryError) -> String {
        switch error {
        case .ownerOrAdminRequired:
            return "You no longer have permission to delete this chore."
        case .authenticationRequired:
            return "Your session has expired. Please sign in again."
        case .notFound:
            return "Unable to find this chore."
        default:
            return "Unable to delete this chore."
        }
    }

    private func apply(chore: ChoreTemplate, recurrenceRule: ChoreRecurrenceRule?, assignees: [ChoreTemplateAssignee]) {
        isApplyingLoadedChore = true
        savedTemplateId = chore.id
        title = chore.title
        choreDescription = chore.description ?? ""
        instructions = chore.instructions ?? ""
        categoryId = chore.categoryId
        roomId = chore.roomId
        assignmentMode = chore.assignmentMode
        completionMode = chore.completionMode
        assigneeIds = Set(assignees.map(\.userId))
        pointsValue = chore.pointsValue
        requiresApproval = chore.requiresApproval
        requiresPhoto = chore.requiresPhoto

        if let recurrenceRule {
            startDate = recurrenceRule.startDate
            isAllDay = recurrenceRule.isAllDay
            dueDateTime = dateTime(on: recurrenceRule.startDate, from: recurrenceRule.dueTime)
            durationMinutes = recurrenceRule.durationMinutes
            recurrenceOption = recurrenceOption(for: recurrenceRule)
            intervalValue = recurrenceRule.intervalValue
            weekdays = Set(recurrenceRule.weekdays)
            dayOfMonth = recurrenceRule.dayOfMonth ?? Calendar.current.component(.day, from: recurrenceRule.startDate)
            monthOfYear = recurrenceRule.monthOfYear ?? Calendar.current.component(.month, from: recurrenceRule.startDate)
            endType = recurrenceRule.frequency == .none ? .afterCount : recurrenceRule.endType
            endsOn = recurrenceRule.endsOn ?? Calendar.current.date(byAdding: .month, value: 3, to: recurrenceRule.startDate) ?? recurrenceRule.startDate
            occurrenceCount = recurrenceRule.occurrenceCount ?? (recurrenceRule.frequency == .none ? 1 : 10)
        }

        isApplyingLoadedChore = false
        normalizeAssignmentMode()
        normalizeAssignees()
        updateSaveErrorForValidation()
    }

    private func recurrenceOption(for rule: ChoreRecurrenceRule) -> ChoreRecurrenceOption {
        switch rule.frequency {
        case .none:
            return .oneTime
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        case .monthly:
            return rule.intervalValue == 6 ? .everySixMonths : .monthly
        case .yearly:
            return .annually
        }
    }

    private func dateTime(on date: Date, from localTime: ChoreLocalTime?) -> Date {
        guard let localTime else {
            return date
        }

        let parts = localTime.rawValue.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else {
            return date
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = parts.count > 2 ? parts[2] : 0
        return Calendar.current.date(from: components) ?? date
    }
}

enum ChoreRecurrenceOption: String, CaseIterable, Identifiable {
    case oneTime
    case daily
    case weekly
    case monthly
    case everySixMonths
    case annually

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneTime:
            return "One Time"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .everySixMonths:
            return "Every 6 Months"
        case .annually:
            return "Annually"
        }
    }

    var frequency: ChoreFrequency {
        switch self {
        case .oneTime:
            return .none
        case .daily:
            return .daily
        case .weekly:
            return .weekly
        case .monthly, .everySixMonths:
            return .monthly
        case .annually:
            return .yearly
        }
    }

    var isRecurring: Bool {
        self != .oneTime
    }

    var usesDayOfMonth: Bool {
        switch self {
        case .monthly, .everySixMonths, .annually:
            return true
        case .oneTime, .daily, .weekly:
            return false
        }
    }
}

private enum ChoreDurationOption: Int, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case twoHours = 120

    var id: Int { rawValue }
    var minutes: Int { rawValue }

    var title: String {
        switch self {
        case .fifteen:
            return "15 minutes"
        case .thirty:
            return "30 minutes"
        case .fortyFive:
            return "45 minutes"
        case .sixty:
            return "1 hour"
        case .twoHours:
            return "2 hours"
        }
    }
}

private struct ChoreWeekday: CaseIterable, Identifiable {
    let value: Int
    let title: String
    let shortTitle: String

    var id: Int { value }

    static let allCases: [ChoreWeekday] = [
        ChoreWeekday(value: 0, title: "Sunday", shortTitle: "Sun"),
        ChoreWeekday(value: 1, title: "Monday", shortTitle: "Mon"),
        ChoreWeekday(value: 2, title: "Tuesday", shortTitle: "Tue"),
        ChoreWeekday(value: 3, title: "Wednesday", shortTitle: "Wed"),
        ChoreWeekday(value: 4, title: "Thursday", shortTitle: "Thu"),
        ChoreWeekday(value: 5, title: "Friday", shortTitle: "Fri"),
        ChoreWeekday(value: 6, title: "Saturday", shortTitle: "Sat")
    ]

    static func summary(for values: Set<Int>) -> String {
        let selected = allCases.filter { values.contains($0.value) }
        guard !selected.isEmpty else {
            return "selected weekdays"
        }

        if selected.count == 1 {
            return selected[0].title
        }

        let titles = selected.map(\.title)
        return titles.dropLast().joined(separator: ", ") + " and " + (titles.last ?? "")
    }
}

private enum ChoreEditorSaveError: LocalizedError {
    case homeUnavailable
    case calendarCleanupFailed

    var errorDescription: String? {
        switch self {
        case .homeUnavailable:
            return "Choose a Home before creating a chore."
        case .calendarCleanupFailed:
            return "The chore was saved, but some old future calendar events could not be removed. Please retry calendar sync."
        }
    }
}

extension Notification.Name {
    static let homeyChoresDidChange = Notification.Name("homeyChoresDidChange")
}
