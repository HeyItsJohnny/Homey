import Combine
import Foundation

@MainActor
final class HomeCalendarChoresViewModel: ObservableObject {
    @Published private(set) var occurrences: [ChoreOccurrence] = []
    @Published private(set) var assigneesByOccurrenceId: [UUID: [ChoreOccurrenceAssignee]] = [:]
    @Published private(set) var visibleWeekAnchor: Date
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published var selectedAssignee: HomeChoreAssigneeFilter = .all

    private let repository: ChoresRepository
    private var calendar: Calendar
    private var activeHomeId: UUID?
    private var activeRole: HomeMemberRole?
    private var activeCurrentUserId: UUID?
    private var activeTimezone: String?
    private var roomsById: [UUID: ChoreRoom] = [:]
    private var notificationTask: Task<Void, Never>?

    init(repository: ChoresRepository? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.repository = repository ?? ChoresRepository()
        self.calendar = calendar
        visibleWeekAnchor = calendar.startOfDay(for: Date())
        Self.configureFormatters(calendar: calendar)

        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                await self?.reload()
            }
        }
    }

    deinit {
        notificationTask?.cancel()
    }

    func configure(homeId: UUID?, role: HomeMemberRole?, currentUserId: UUID?, weekStartsOn: Int?, timezone: String?) async {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)

        if activeHomeId != homeId || activeCurrentUserId != currentUserId {
            visibleWeekAnchor = calendar.startOfDay(for: Date())
            occurrences = []
            assigneesByOccurrenceId = [:]
            selectedAssignee = .all
        }

        activeHomeId = homeId
        activeRole = role
        activeCurrentUserId = currentUserId
        activeTimezone = timezone

        await reload()
    }

    func reload() async {
        guard let activeHomeId else {
            occurrences = []
            assigneesByOccurrenceId = [:]
            roomsById = [:]
            errorMessage = "Choose a Home before viewing chores."
            return
        }

        guard let range = visibleWeekRange else {
            errorMessage = ChoreRepositoryError.invalidDateRange.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let syncService = ChoreCalendarSyncService(choresRepository: repository)
            let loadedOccurrences = try await repository.refreshChoreSchedule(
                homeId: activeHomeId,
                from: range.start,
                through: range.end,
                currentRole: activeRole,
                calendarSyncService: syncService
            )
            async let loadedAssignees = repository.fetchOccurrenceAssignees(occurrenceIds: loadedOccurrences.map(\.id))
            async let loadedRooms = repository.fetchRooms(homeId: activeHomeId)
            let (assignees, rooms) = try await (loadedAssignees, loadedRooms)

            occurrences = loadedOccurrences
                .filter { $0.status != .skipped && $0.status != .cancelled }
                .sorted { first, second in
                if first.dueAt != second.dueAt {
                    return first.dueAt < second.dueAt
                }
                return first.titleSnapshot.localizedCaseInsensitiveCompare(second.titleSnapshot) == .orderedAscending
            }
            assigneesByOccurrenceId = Dictionary(grouping: assignees, by: \.occurrenceId)
            roomsById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveToPreviousWeek() {
        moveWeek(by: -1)
    }

    func moveToNextWeek() {
        moveWeek(by: 1)
    }

    func moveToToday() {
        visibleWeekAnchor = calendar.startOfDay(for: Date())
        Task { await reload() }
    }

    func selectAssignee(_ filter: HomeChoreAssigneeFilter) {
        selectedAssignee = filter
    }

    func weekDays() -> [Date] {
        guard let range = visibleWeekRange else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
    }

    var visibleWeekRange: (start: Date, end: Date)? {
        let start = startOfWeek(containing: visibleWeekAnchor)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return nil
        }
        return (start, end)
    }

    var visibleWeekTitle: String {
        guard let range = visibleWeekRange,
              let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end) else {
            return "This Week"
        }

        if calendar.isDate(range.start, equalTo: inclusiveEnd, toGranularity: .month) {
            let monthYear = Self.monthYearFormatter.string(from: range.start)
            let startDay = Self.dayFormatter.string(from: range.start)
            let endDay = Self.dayFormatter.string(from: inclusiveEnd)
            return "\(monthYear) \(startDay)-\(endDay)"
        }

        if calendar.component(.year, from: range.start) == calendar.component(.year, from: inclusiveEnd) {
            return "\(Self.monthDayFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
        }

        return "\(Self.monthDayYearFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
    }

    func choreItems(on day: Date, members: [HomeMemberDisplay]) -> [HomeChoreChecklistItemModel] {
        let memberByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })
        return occurrences
            .filter { calendar.isDate($0.dueAt, inSameDayAs: day) }
            .flatMap { occurrence in
                checklistItems(for: occurrence, memberByUserId: memberByUserId)
            }
            .filter { selectedAssignee.includes($0.assigneeUserId) }
            .sorted()
    }

    func choreCount(members: [HomeMemberDisplay]) -> Int {
        Set(weekDays().flatMap { day in
            choreItems(on: day, members: members).map(\.id)
        }).count
    }

    func submitFromHomeBoard(item: HomeChoreChecklistItemModel, assigneeUserId: UUID, note: String?) async -> Bool {
        guard !isSubmitting else { return false }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await repository.submitChoreFromHomeBoard(
                occurrenceId: item.occurrence.id,
                assigneeUserId: assigneeUserId,
                note: note,
                photoPath: nil
            )
            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func skipFromHomeBoard(item: HomeChoreChecklistItemModel, assigneeUserId: UUID) async -> Bool {
        guard !isSubmitting else { return false }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            if (activeRole == .owner || activeRole == .admin),
               assigneeUserId != activeCurrentUserId,
               item.assignee != nil {
                _ = try await repository.skipChoreAsAdmin(
                    occurrenceId: item.occurrence.id,
                    forUserId: assigneeUserId
                )
            } else {
                _ = try await repository.skipChore(occurrenceId: item.occurrence.id)
            }

            await reload()
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func checklistItems(
        for occurrence: ChoreOccurrence,
        memberByUserId: [UUID: HomeMemberDisplay]
    ) -> [HomeChoreChecklistItemModel] {
        let assignees = assigneesByOccurrenceId[occurrence.id, default: []]

        if !assignees.isEmpty {
            return assignees
                .filter { $0.status != .skipped && $0.status != .cancelled }
                .map { assignee in
                HomeChoreChecklistItemModel(
                    occurrence: occurrence,
                    assignee: assignee,
                    member: memberByUserId[assignee.userId],
                    roomName: roomName(for: occurrence)
                )
            }
        }

        if occurrence.assignmentMode == .open, let claimedBy = occurrence.claimedBy {
            return [
                HomeChoreChecklistItemModel(
                    occurrence: occurrence,
                    assignee: nil,
                    member: memberByUserId[claimedBy],
                    fallbackAssigneeUserId: claimedBy,
                    roomName: roomName(for: occurrence)
                )
            ]
        }

        return [
            HomeChoreChecklistItemModel(
                occurrence: occurrence,
                assignee: nil,
                member: nil,
                fallbackAssigneeUserId: nil,
                roomName: roomName(for: occurrence)
            )
        ]
    }

    private func roomName(for occurrence: ChoreOccurrence) -> String {
        guard let roomId = occurrence.roomIdSnapshot,
              let room = roomsById[roomId] else {
            return "No Room"
        }

        return room.name
    }

    private func moveWeek(by value: Int) {
        guard let next = calendar.date(byAdding: .weekOfYear, value: value, to: visibleWeekAnchor) else {
            return
        }
        visibleWeekAnchor = calendar.startOfDay(for: next)
        Task { await reload() }
    }

    private func configureWeekStart(_ weekStartsOn: Int?) {
        let firstWeekday = weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
        calendar.firstWeekday = firstWeekday
        Self.configureFormatters(calendar: calendar)
    }

    private func configureTimezone(_ timezone: String?) {
        if let timezone, let timeZone = TimeZone(identifier: timezone) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .autoupdatingCurrent
        }
        activeTimezone = timezone
        Self.configureFormatters(calendar: calendar)
    }

    private func startOfWeek(containing date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -leadingDays, to: startOfDay) ?? startOfDay
    }

    private static let dayFormatter = DateFormatter()
    private static let monthYearFormatter = DateFormatter()
    private static let monthDayFormatter = DateFormatter()
    private static let monthDayYearFormatter = DateFormatter()

    private static func configureFormatters(calendar: Calendar) {
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "d"

        monthYearFormatter.calendar = calendar
        monthYearFormatter.timeZone = calendar.timeZone
        monthYearFormatter.dateFormat = "MMMM yyyy"

        monthDayFormatter.calendar = calendar
        monthDayFormatter.timeZone = calendar.timeZone
        monthDayFormatter.dateFormat = "MMMM d"

        monthDayYearFormatter.calendar = calendar
        monthDayYearFormatter.timeZone = calendar.timeZone
        monthDayYearFormatter.dateFormat = "MMMM d, yyyy"
    }
}

enum HomeChoreAssigneeFilter: Hashable, Identifiable {
    case all
    case member(UUID)
    case anyone

    var id: String {
        switch self {
        case .all:
            return "all"
        case .member(let userId):
            return userId.uuidString
        case .anyone:
            return "anyone"
        }
    }

    func includes(_ userId: UUID?) -> Bool {
        switch self {
        case .all:
            return true
        case .member(let selectedUserId):
            return userId == selectedUserId
        case .anyone:
            return userId == nil
        }
    }
}

struct HomeChoreChecklistItemModel: Identifiable, Hashable {
    let occurrence: ChoreOccurrence
    let assignee: ChoreOccurrenceAssignee?
    let member: HomeMemberDisplay?
    var fallbackAssigneeUserId: UUID? = nil
    var roomName: String = "No Room"

    var id: String {
        if let assignee {
            return "\(occurrence.id.uuidString)-\(assignee.userId.uuidString)"
        }
        return "\(occurrence.id.uuidString)-anyone"
    }

    var assigneeUserId: UUID? {
        assignee?.userId ?? fallbackAssigneeUserId
    }

    var assigneeName: String {
        member?.displayName ?? "Anyone"
    }

    var assigneeInitials: String {
        member?.initials ?? "A"
    }

    var status: HomeChoreChecklistStatus {
        if let assignee {
            return HomeChoreChecklistStatus(assigneeStatus: assignee.status)
        }
        return HomeChoreChecklistStatus(occurrenceStatus: occurrence.status)
    }

    var canSkipFromHomeBoard: Bool {
        guard let assignee else {
            return false
        }

        return assignee.status == .assigned
    }

    var dueAt: Date {
        occurrence.dueAt
    }
}

extension HomeChoreChecklistItemModel: Comparable {
    static func < (lhs: HomeChoreChecklistItemModel, rhs: HomeChoreChecklistItemModel) -> Bool {
        if lhs.assigneeName != rhs.assigneeName {
            if lhs.assigneeName == "Anyone" { return false }
            if rhs.assigneeName == "Anyone" { return true }
            return lhs.assigneeName.localizedCaseInsensitiveCompare(rhs.assigneeName) == .orderedAscending
        }

        if lhs.dueAt != rhs.dueAt {
            return lhs.dueAt < rhs.dueAt
        }

        return lhs.occurrence.titleSnapshot.localizedCaseInsensitiveCompare(rhs.occurrence.titleSnapshot) == .orderedAscending
    }
}

enum HomeChoreChecklistStatus: Hashable {
    case notStarted
    case needsRedo
    case awaitingApproval
    case completed

    init(assigneeStatus: ChoreAssigneeStatus) {
        switch assigneeStatus {
        case .awaitingApproval:
            self = .awaitingApproval
        case .completed, .skipped, .cancelled:
            self = .completed
        case .needsRedo:
            self = .needsRedo
        case .assigned, .inProgress:
            self = .notStarted
        }
    }

    init(occurrenceStatus: ChoreOccurrenceStatus) {
        switch occurrenceStatus {
        case .awaitingApproval:
            self = .awaitingApproval
        case .completed, .skipped, .cancelled:
            self = .completed
        case .needsRedo:
            self = .needsRedo
        case .notStarted, .inProgress:
            self = .notStarted
        }
    }

    var title: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .needsRedo:
            return "Needs Redo"
        case .awaitingApproval:
            return "Awaiting Approval"
        case .completed:
            return "Completed"
        }
    }

    var canSubmitFromHomeBoard: Bool {
        switch self {
        case .notStarted, .needsRedo:
            return true
        case .awaitingApproval, .completed:
            return false
        }
    }

    var requiresHouseholdAction: Bool {
        switch self {
        case .notStarted, .needsRedo:
            return true
        case .awaitingApproval, .completed:
            return false
        }
    }

    var requiresStatusCaption: Bool {
        switch self {
        case .notStarted:
            return false
        case .needsRedo, .awaitingApproval, .completed:
            return true
        }
    }
}
