import Combine
import Foundation

@MainActor
final class PhoneDailyTasksViewModel: ObservableObject {
    @Published private(set) var tasks: [PhoneDailyTask] = []
    @Published private(set) var members: [PhoneDailyTaskMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var processingAssignments: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var requestedDate = ""

    private let service = PhoneDailyTaskService()
    private var activeHomeID: UUID?
    private var currentUserID: UUID?
    private var activeRole: HomeMemberRole?
    private var timezone = TimeZone.current
    private var activeLoadID = UUID()

    var canManage: Bool { activeRole == .owner || activeRole == .admin }

    func configure(
        homeID: UUID?,
        currentUserID: UUID?,
        role: HomeMemberRole?,
        timezone: TimeZone,
        force: Bool
    ) async {
        guard let homeID, let currentUserID else {
            reset()
            return
        }

        let nextDate = PhoneDailyTaskLocalDate.string(timezone: timezone)
        let contextChanged = activeHomeID != homeID
            || self.currentUserID != currentUserID
            || activeRole != role
            || requestedDate != nextDate

        if contextChanged {
            activeLoadID = UUID()
            tasks = []
            members = []
            processingAssignments = []
            errorMessage = nil
            actionErrorMessage = nil
        }

        activeHomeID = homeID
        self.currentUserID = currentUserID
        activeRole = role
        self.timezone = timezone
        requestedDate = nextDate
        if force { actionErrorMessage = nil }

        if contextChanged || force || tasks.isEmpty {
            await load()
        }
    }

    func reloadForCurrentDay() async {
        guard activeHomeID != nil else { return }
        let nextDate = PhoneDailyTaskLocalDate.string(timezone: timezone)
        if nextDate != requestedDate {
            requestedDate = nextDate
            tasks = []
        }
        actionErrorMessage = nil
        await load()
    }

    func toggle(task: PhoneDailyTask, assignment: PhoneDailyTaskAssignment) async {
        guard let homeID = activeHomeID, let currentUserID else { return }
        guard canManage || assignment.userID == currentUserID else { return }

        let key = processingKey(taskID: task.id, userID: assignment.userID)
        guard !processingAssignments.contains(key) else { return }
        processingAssignments.insert(key)
        actionErrorMessage = nil
        defer { processingAssignments.remove(key) }

        let intendedCompletion = !assignment.isCompleted
        do {
            if assignment.isCompleted {
                guard let completionID = assignment.completionID else {
                    await load()
                    if assignmentState(taskID: task.id, userID: assignment.userID) == false { return }
                    throw PhoneDailyTaskError.updateFailed
                }
                try await service.undo(homeID: homeID, completionID: completionID)
            } else {
                try await service.complete(
                    homeID: homeID,
                    taskID: task.id,
                    userID: assignment.userID,
                    date: requestedDate
                )
            }
            await load()
            notifySharedChoreDataChanged()
        } catch is CancellationError {
            return
        } catch {
            // A duplicate-completion race can report an RPC error after another
            // request has already committed. Refresh first and accept that state.
            await load()
            if assignmentState(taskID: task.id, userID: assignment.userID) != intendedCompletion {
                actionErrorMessage = PhoneDailyTaskError.updateFailed.localizedDescription
            } else {
                notifySharedChoreDataChanged()
            }
        }
    }

    func isProcessing(taskID: UUID, userID: UUID) -> Bool {
        processingAssignments.contains(processingKey(taskID: taskID, userID: userID))
    }

    func memberName(for userID: UUID) -> String {
        members.first { $0.userID == userID }?.displayName ?? "Home Member"
    }

    private func load() async {
        guard let homeID = activeHomeID else { return }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadID == loadID { isLoading = false }
        }

        do {
            let loadedRows = try await service.fetchTasks(homeID: homeID, date: requestedDate)
            let loadedMembers = canManage ? try await service.fetchMembers(homeID: homeID) : []
            guard activeLoadID == loadID, activeHomeID == homeID else { return }

            tasks = Dictionary(grouping: loadedRows, by: \.taskID)
                .values
                .compactMap(PhoneDailyTask.init(rows:))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            members = loadedMembers.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func assignmentState(taskID: UUID, userID: UUID) -> Bool? {
        tasks.first { $0.id == taskID }?.assignments.first { $0.userID == userID }?.isCompleted
    }

    private func processingKey(taskID: UUID, userID: UUID) -> String {
        "\(taskID.uuidString):\(userID.uuidString)"
    }

    private func notifySharedChoreDataChanged() {
        NotificationCenter.default.post(name: Notification.Name("homeyDailyTasksDidChange"), object: self)
        NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: self)
    }

    private func reset() {
        activeLoadID = UUID()
        activeHomeID = nil
        currentUserID = nil
        activeRole = nil
        timezone = .current
        requestedDate = ""
        tasks = []
        members = []
        processingAssignments = []
        isLoading = false
        errorMessage = nil
        actionErrorMessage = nil
    }
}
