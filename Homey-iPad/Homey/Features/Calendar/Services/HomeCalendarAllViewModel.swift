import Combine
import Foundation

@MainActor
final class HomeCalendarAllViewModel: ObservableObject {
    @Published private(set) var plannedMeals: [PlannedMeal] = []
    @Published private(set) var choreItems: [HomeChoreChecklistItemModel] = []
    @Published private(set) var normalEvents: [CalendarEvent] = []
    @Published private(set) var pointBalance = 0
    @Published private(set) var visibleWeekAnchor: Date
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let mealPlannerService: MealPlannerService
    private let calendarService: CalendarService
    private let choresRepository: ChoresRepository
    private var calendar: Calendar
    private var activeHomeId: UUID?
    private var activeRole: HomeMemberRole?
    private var activeUserId: UUID?
    private var activeMembers: [HomeMemberDisplay] = []
    private var activeTimezone: String?
    private var notificationTask: Task<Void, Never>?

    init(
        mealPlannerService: MealPlannerService? = nil,
        calendarService: CalendarService? = nil,
        choresRepository: ChoresRepository? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.mealPlannerService = mealPlannerService ?? MealPlannerService(calendar: calendar)
        self.calendarService = calendarService ?? CalendarService(calendar: calendar)
        self.choresRepository = choresRepository ?? ChoresRepository()
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

    func configure(
        homeId: UUID?,
        role: HomeMemberRole?,
        weekStartsOn: Int?,
        timezone: String?,
        members: [HomeMemberDisplay],
        currentUserId: UUID?
    ) async {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)
        mealPlannerService.configureWeekStart(weekStartsOn)
        mealPlannerService.configureTimezone(timezone)

        if activeHomeId != homeId {
            visibleWeekAnchor = calendar.startOfDay(for: Date())
            plannedMeals = []
            choreItems = []
            normalEvents = []
            pointBalance = 0
        }

        activeHomeId = homeId
        activeRole = role
        activeMembers = members
        activeUserId = currentUserId

        await reload()
    }

    func reload() async {
        guard let activeHomeId else {
            plannedMeals = []
            choreItems = []
            normalEvents = []
            pointBalance = 0
            errorMessage = "Choose a Home before viewing the dashboard."
            return
        }

        guard let range = visibleWeekRange else {
            errorMessage = CalendarServiceError.invalidDateRange.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let syncService = ChoreCalendarSyncService(choresRepository: choresRepository)

            async let loadedMeals = mealPlannerService.fetchPlannedMeals(
                homeId: activeHomeId,
                startDate: range.start,
                endDate: range.end
            )
            async let loadedOccurrences = choresRepository.refreshChoreSchedule(
                homeId: activeHomeId,
                from: range.start,
                through: range.end,
                currentRole: activeRole,
                calendarSyncService: syncService
            )
            async let loadedEvents = calendarService.fetchEvents(
                homeId: activeHomeId,
                rangeStart: range.start,
                rangeEnd: range.end
            )

            let (meals, occurrences, events) = try await (loadedMeals, loadedOccurrences, loadedEvents)
            let assignees = try await choresRepository.fetchOccurrenceAssignees(occurrenceIds: occurrences.map(\.id))

            plannedMeals = meals
            choreItems = Self.makeChoreItems(
                occurrences: occurrences,
                assignees: assignees,
                members: activeMembers,
                calendar: calendar
            )
            normalEvents = Self.normalCalendarEvents(events, plannedMeals: meals, occurrences: occurrences)

            if let activeUserId {
                pointBalance = try await choresRepository.fetchPointBalance(
                    homeId: activeHomeId,
                    userId: activeUserId,
                    currentRole: activeRole
                )
            } else {
                pointBalance = 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitFromHomeBoard(item: HomeChoreChecklistItemModel, assigneeUserId: UUID) async -> Bool {
        guard !isSubmitting else { return false }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await choresRepository.submitChoreFromHomeBoard(
                occurrenceId: item.occurrence.id,
                assigneeUserId: assigneeUserId,
                note: nil,
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

    var mealsPlannedCount: Int {
        Set(plannedMeals.map(\.id)).count
    }

    var choresToDoCount: Int {
        actionableChores.count
    }

    var eventsCount: Int {
        Set(normalEvents.map(\.id)).count
    }

    var todayTitle: String {
        "Today · \(Self.todayFormatter.string(from: calendar.startOfDay(for: Date())))"
    }

    var weekTitle: String {
        guard let range = visibleWeekRange,
              let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end) else {
            return "This Week"
        }

        if calendar.isDate(range.start, equalTo: inclusiveEnd, toGranularity: .month) {
            return "\(Self.monthYearFormatter.string(from: range.start)) \(Self.dayFormatter.string(from: range.start))-\(Self.dayFormatter.string(from: inclusiveEnd))"
        }

        return "\(Self.monthDayFormatter.string(from: range.start)) - \(Self.monthDayFormatter.string(from: inclusiveEnd))"
    }

    var todayTimelineItems: [HomeAllTimelineItem] {
        let today = calendar.startOfDay(for: Date())
        let mealItems = plannedMeals
            .filter { calendar.isDate($0.startsAt, inSameDayAs: today) }
            .map { HomeAllTimelineItem(plannedMeal: $0) }
        let eventItems = normalEvents
            .filter { calendar.isDate($0.occurrenceStartsAt, inSameDayAs: today) }
            .map { HomeAllTimelineItem(calendarEvent: $0) }

        return (mealItems + eventItems).sorted { lhs, rhs in
            lhs.sortDate < rhs.sortDate
        }
    }

    var todayChores: [HomeChoreChecklistItemModel] {
        let today = calendar.startOfDay(for: Date())
        return choreItems
            .filter { calendar.isDate($0.dueAt, inSameDayAs: today) }
            .filter { $0.status.requiresHouseholdAction }
            .sorted()
    }

    func activity(for day: Date) -> HomeAllDayActivity {
        HomeAllDayActivity(
            hasMeals: plannedMeals.contains { calendar.isDate($0.startsAt, inSameDayAs: day) },
            hasChores: choreItems.contains { calendar.isDate($0.dueAt, inSameDayAs: day) },
            hasEvents: normalEvents.contains { calendar.isDate($0.occurrenceStartsAt, inSameDayAs: day) }
        )
    }

    private var actionableChores: [HomeChoreChecklistItemModel] {
        choreItems.filter { $0.status.requiresHouseholdAction }
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

    private static func makeChoreItems(
        occurrences: [ChoreOccurrence],
        assignees: [ChoreOccurrenceAssignee],
        members: [HomeMemberDisplay],
        calendar: Calendar
    ) -> [HomeChoreChecklistItemModel] {
        let memberByUserId = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })
        let assigneesByOccurrenceId = Dictionary(grouping: assignees, by: \.occurrenceId)

        return occurrences
            .flatMap { occurrence -> [HomeChoreChecklistItemModel] in
                let occurrenceAssignees = assigneesByOccurrenceId[occurrence.id, default: []]

                if !occurrenceAssignees.isEmpty {
                    return occurrenceAssignees.map { assignee in
                        HomeChoreChecklistItemModel(
                            occurrence: occurrence,
                            assignee: assignee,
                            member: memberByUserId[assignee.userId]
                        )
                    }
                }

                if occurrence.assignmentMode == .open, let claimedBy = occurrence.claimedBy {
                    return [
                        HomeChoreChecklistItemModel(
                            occurrence: occurrence,
                            assignee: nil,
                            member: memberByUserId[claimedBy],
                            fallbackAssigneeUserId: claimedBy
                        )
                    ]
                }

                return [
                    HomeChoreChecklistItemModel(
                        occurrence: occurrence,
                        assignee: nil,
                        member: nil,
                        fallbackAssigneeUserId: nil
                    )
                ]
            }
            .sorted()
    }

    private static func normalCalendarEvents(
        _ events: [CalendarEvent],
        plannedMeals: [PlannedMeal],
        occurrences: [ChoreOccurrence]
    ) -> [CalendarEvent] {
        let mealEventIds = Set(plannedMeals.map(\.calendarEventId))
        let choreEventIds = Set(occurrences.compactMap(\.calendarEventId))

        return events.filter { event in
            !mealEventIds.contains(event.eventId) && !choreEventIds.contains(event.eventId)
        }
    }

    private static let dayFormatter = DateFormatter()
    private static let monthYearFormatter = DateFormatter()
    private static let monthDayFormatter = DateFormatter()
    private static let todayFormatter = DateFormatter()

    private static func configureFormatters(calendar: Calendar) {
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "d"

        monthYearFormatter.calendar = calendar
        monthYearFormatter.timeZone = calendar.timeZone
        monthYearFormatter.dateFormat = "MMMM yyyy"

        monthDayFormatter.calendar = calendar
        monthDayFormatter.timeZone = calendar.timeZone
        monthDayFormatter.dateFormat = "MMM d"

        todayFormatter.calendar = calendar
        todayFormatter.timeZone = calendar.timeZone
        todayFormatter.dateFormat = "EEEE, MMM d"
    }
}

struct HomeAllTimelineItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case meal(PlannedMeal)
        case calendarEvent(CalendarEvent)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let sortDate: Date
    let imageURL: URL?
    let systemImage: String
    let accentColorHex: String?
    let isAllDay: Bool

    init(plannedMeal: PlannedMeal) {
        id = "meal-\(plannedMeal.id)"
        kind = .meal(plannedMeal)
        title = plannedMeal.meal.name
        subtitle = plannedMeal.mealType.displayName
        sortDate = plannedMeal.startsAt
        imageURL = plannedMeal.signedPhotoURL
        systemImage = plannedMeal.mealType.systemImageName
        accentColorHex = nil
        isAllDay = false
    }

    init(calendarEvent: CalendarEvent) {
        id = "event-\(calendarEvent.id)"
        kind = .calendarEvent(calendarEvent)
        title = calendarEvent.title
        subtitle = calendarEvent.categoryName ?? "Calendar"
        sortDate = calendarEvent.occurrenceStartsAt
        imageURL = nil
        systemImage = calendarEvent.categoryIconName ?? "calendar"
        accentColorHex = calendarEvent.categoryColorHex
        isAllDay = calendarEvent.isAllDay
    }
}

struct HomeAllDayActivity: Hashable {
    let hasMeals: Bool
    let hasChores: Bool
    let hasEvents: Bool
}
