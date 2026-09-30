import SwiftUI

struct PhoneDailyTasksView: View {
    @EnvironmentObject private var appSession: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = PhoneDailyTasksViewModel()
    @State private var editingTask: PhoneDailyTask?
    @State private var showingNewTask = false

    private var context: String {
        "\(appSession.activeHome?.id.uuidString ?? "no-home")-\(appSession.currentUser?.id.uuidString ?? "no-user")-\(appSession.activeRole?.rawValue ?? "no-role")-\(PhoneDailyTaskLocalDate.string(timezone: appSession.activeTimezone))"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks")
                        .font(HomeyTypography.title)
                        .foregroundStyle(HomeyColors.text)
                    Text("Today · \(PhoneDailyTaskLocalDate.displayString(timezone: appSession.activeTimezone))")
                        .font(.subheadline)
                        .foregroundStyle(HomeyColors.secondaryText)
                }

                if let actionErrorMessage = model.actionErrorMessage {
                    Label(actionErrorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(HomeyColors.danger)
                }

                if model.isLoading && model.tasks.isEmpty {
                    ProgressView("Loading today's tasks…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let errorMessage = model.errorMessage, model.tasks.isEmpty {
                    errorState(errorMessage)
                } else if model.tasks.isEmpty {
                    emptyState
                } else if model.canManage {
                    householdTasks
                } else {
                    personalTasks
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await load(force: true) }
        .task(id: context) { await load(force: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reloadForCurrentDay() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSCalendarDayChanged)) { _ in
            Task { await model.reloadForCurrentDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyDailyTasksDidChange"))) { notification in
            guard notification.object as AnyObject? !== model else { return }
            Task { await load(force: true) }
        }
        .sheet(isPresented: $showingNewTask) { editor(task: nil) }
        .sheet(item: $editingTask) { task in editor(task: task) }
    }

    private var personalTasks: some View {
        let rows = model.tasks.compactMap { task -> (PhoneDailyTask, PhoneDailyTaskAssignment)? in
            guard let userID = appSession.currentUser?.id,
                  let assignment = task.assignments.first(where: { $0.userID == userID }) else { return nil }
            return (task, assignment)
        }
        let todo = rows.filter { !$0.1.isCompleted }
        let completed = rows.filter { $0.1.isCompleted }

        return VStack(alignment: .leading, spacing: 18) {
            personalGroup("TO DO", rows: todo)
            if !completed.isEmpty { personalGroup("COMPLETED", rows: completed) }
        }
    }

    private func personalGroup(_ title: String, rows: [(PhoneDailyTask, PhoneDailyTaskAssignment)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyColors.secondaryText)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.0.id) { index, row in
                    dailyTaskButton(task: row.0, assignment: row.1, memberName: nil)
                    if index < rows.count - 1 { Divider().padding(.leading, 48) }
                }
            }
            .homeyCard()
        }
    }

    private var householdTasks: some View {
        VStack(spacing: 14) {
            ForEach(model.tasks) { task in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.name)
                                .font(.headline)
                                .foregroundStyle(HomeyColors.text)
                            Text(pointsText(task.points))
                                .font(.caption)
                                .foregroundStyle(HomeyColors.secondaryText)
                            Text("\(task.completedCount) of \(task.assignments.count) complete")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HomeyColors.primary)
                        }
                        Spacer()
                        Button { editingTask = task } label: {
                            Image(systemName: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 38, height: 38)
                                .background(HomeyColors.field, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(HomeyColors.primary)
                        .accessibilityLabel("Edit \(task.name)")
                    }

                    Divider()

                    let assignments = task.assignments.sorted {
                        model.memberName(for: $0.userID).localizedCaseInsensitiveCompare(model.memberName(for: $1.userID)) == .orderedAscending
                    }
                    ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                        dailyTaskButton(
                            task: task,
                            assignment: assignment,
                            memberName: model.memberName(for: assignment.userID)
                        )
                        if index < assignments.count - 1 { Divider().padding(.leading, 48) }
                    }
                }
                .homeyCard()
            }
        }
    }

    private func dailyTaskButton(
        task: PhoneDailyTask,
        assignment: PhoneDailyTaskAssignment,
        memberName: String?
    ) -> some View {
        let isProcessing = model.isProcessing(taskID: task.id, userID: assignment.userID)
        return Button {
            Task { await model.toggle(task: task, assignment: assignment) }
        } label: {
            HStack(spacing: 12) {
                if isProcessing {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                } else {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(assignment.isCompleted ? HomeyColors.success : HomeyColors.secondaryText)
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(memberName ?? task.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyColors.text)
                    if memberName == nil {
                        Text(pointsText(task.points))
                            .font(.caption)
                            .foregroundStyle(HomeyColors.secondaryText)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel("\(assignment.isCompleted ? "Undo" : "Complete") \(memberName ?? task.name)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundStyle(HomeyColors.primary)
            Text(model.canManage ? "No daily tasks yet" : "No tasks assigned today")
                .font(.headline)
                .foregroundStyle(HomeyColors.text)
            if model.canManage {
                Button("Add Task") { showingNewTask = true }
                    .buttonStyle(HomeyButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .homeyCard()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            HomeyErrorView(message: message)
            Button("Try Again") { Task { await load(force: true) } }
                .buttonStyle(HomeyButtonStyle())
        }
        .homeyCard()
    }

    @ViewBuilder
    private func editor(task: PhoneDailyTask?) -> some View {
        PhoneDailyTaskEditorView(
            homeID: appSession.activeHome?.id,
            role: appSession.activeRole,
            task: task
        ) {
            Task { await load(force: true) }
        }
    }

    private func pointsText(_ points: Int) -> String { "\(points) pt\(points == 1 ? "" : "s")" }

    private func load(force: Bool) async {
        await model.configure(
            homeID: appSession.activeHome?.id,
            currentUserID: appSession.currentUser?.id,
            role: appSession.activeRole,
            timezone: appSession.activeTimezone,
            force: force
        )
    }
}

struct PhoneDailyTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID?
    let role: HomeMemberRole?
    let task: PhoneDailyTask?
    let onFinished: () -> Void

    @State private var name: String
    @State private var points: Int
    @State private var selectedAssigneeIDs: Set<UUID>
    @State private var members: [PhoneDailyTaskMember] = []
    @State private var isLoadingMembers = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFocused: Bool

    private let service = PhoneDailyTaskService()

    init(homeID: UUID?, role: HomeMemberRole?, task: PhoneDailyTask?, onFinished: @escaping () -> Void) {
        self.homeID = homeID
        self.role = role
        self.task = task
        self.onFinished = onFinished
        _name = State(initialValue: task?.name ?? "")
        _points = State(initialValue: task?.points ?? 0)
        _selectedAssigneeIDs = State(initialValue: task?.assigneeIDs ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            detailsCard
                            pointsCard
                            assigneesCard

                            if let errorMessage {
                                HomeyErrorView(message: errorMessage)
                                    .homeyCard()
                            }

                            if task != nil { deleteButton }
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    saveControl
                }
            }
            .navigationTitle(task == nil ? "Add Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSaving)
                }
            }
            .task { await loadMembers() }
            .interactiveDismissDisabled(isSaving)
            .confirmationDialog("Delete Task?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await retire() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This task will no longer appear in daily task lists. Previous completion history and points will be kept.")
            }
        }
        .presentationDetents([.large])
    }

    private var detailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                heading("Task Details", "Add a simple daily task for members of this Home.")
                TextField("Task Name", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .homeyTextField()
            }
        }
    }

    private var pointsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                heading("Points", "Choose how many reward points this task earns.")
                Stepper("\(points) points", value: $points, in: 0...10_000, step: 1)
                    .font(.body.weight(.medium))
                    .accessibilityValue("\(points) points")
            }
        }
    }

    private var assigneesCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                heading("Assign To", "Select everyone who should complete this task each day.")
                if isLoadingMembers {
                    ProgressView("Loading members…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ChoreMultiAssigneePicker(
                        options: members.map { ChoreAssigneeOption(id: $0.userID, name: $0.displayName) },
                        selection: $selectedAssigneeIDs
                    )
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            Label("Delete Task", systemImage: "trash")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .foregroundStyle(HomeyColors.danger)
        .background(HomeyColors.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        .disabled(isSaving || !(role == .owner || role == .admin))
    }

    private var saveControl: some View {
        Button(isSaving ? "Saving…" : task == nil ? "Create Task" : "Save Task") {
            Task { await save() }
        }
        .buttonStyle(HomeyButtonStyle())
        .disabled(!canSave)
        .padding(16)
        .background(.white.opacity(0.86))
    }

    private var canSave: Bool {
        let availableMemberIDs = Set(members.map(\.userID))
        return !isSaving
            && !isLoadingMembers
            && (role == .owner || role == .admin)
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedAssigneeIDs.isEmpty
            && selectedAssigneeIDs.isSubset(of: availableMemberIDs)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeyCard()
    }

    private func heading(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
            Text(message).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
        }
    }

    private func loadMembers() async {
        guard role == .owner || role == .admin, let homeID else {
            errorMessage = "Only a Home owner or admin can manage tasks."
            return
        }
        isLoadingMembers = true
        errorMessage = nil
        defer { isLoadingMembers = false }
        do {
            members = try await service.fetchMembers(homeID: homeID).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            selectedAssigneeIDs.formIntersection(Set(members.map(\.userID)))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard role == .owner || role == .admin, let homeID else { return }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { errorMessage = PhoneDailyTaskError.invalidName.localizedDescription; return }
        guard !selectedAssigneeIDs.isEmpty else {
            errorMessage = PhoneDailyTaskError.assigneeRequired.localizedDescription
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await service.save(
                homeID: homeID,
                taskID: task?.id,
                name: normalizedName,
                points: points,
                assigneeIDs: selectedAssigneeIDs.sorted { $0.uuidString < $1.uuidString }
            )
            finish()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func retire() async {
        guard role == .owner || role == .admin, let homeID, let task else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await service.retire(homeID: homeID, taskID: task.id)
            finish()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        NotificationCenter.default.post(name: Notification.Name("homeyDailyTasksDidChange"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
        onFinished()
        dismiss()
    }
}
