import Combine
import SwiftUI

struct MyChoresView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = MyChoresViewModel()
    @State private var selectedOccurrence: ChoreOccurrence?

    var body: some View {
        ChoreShellCard(title: "My Chores", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 18) {
                ChoreSectionDescriptionHeader(
                    title: "My Chores",
                    description: "View your assigned chores, track your progress, and stay on top of what needs to be completed."
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
                        weeklyPlanner
                        MyChoresWeekSummaryCard(summary: viewModel.summary)
                    }
                }
            }
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
                weekStartsOn: selectedHome?.weekStartsOn,
                timezone: selectedHome?.timezone
            )
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
        .sheet(item: $selectedOccurrence) { occurrence in
            ChoreOccurrenceDetailView(
                initialOccurrence: occurrence,
                homeTimezone: homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
            )
        }
    }

    private var loadTaskID: String {
        let selectedHome = homeService.selectedHome()
        return "\(homeService.selectedHomeID?.uuidString ?? "no-home")-\(selectedHome?.weekStartsOn ?? -1)-\(selectedHome?.timezone ?? "")"
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

            Text("\(viewModel.plannedChoreCount) Chores")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Button("Today") { viewModel.moveToToday() }
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
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(viewModel.daySections) { section in
                    MyChoresDayColumn(
                        section: section,
                        isToday: viewModel.isToday(section.date),
                        isSelected: viewModel.isSelectedDay(section.date),
                        onSelectDay: { viewModel.selectDay(section.date) },
                        onSelectOccurrence: { selectedOccurrence = $0 }
                    )
                    .frame(width: 210, alignment: .top)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Weekly chore planner")
    }
}

@MainActor
private final class MyChoresViewModel: ObservableObject {
    @Published private(set) var occurrences: [ChoreOccurrence] = []
    @Published private(set) var weekDays: [Date] = []
    @Published private(set) var selectedDate: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?
    private var timezone = TimeZone.autoupdatingCurrent.identifier
    private var calendar = Calendar.autoupdatingCurrent
    private var visibleWeekAnchor = Date()
    private var categoriesById: [UUID: ChoreCategory] = [:]
    private var roomsById: [UUID: ChoreRoom] = [:]

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
        let eligibleOccurrences = occurrences.filter { !$0.isExcludedFromWeeklySummary }
        let approved = eligibleOccurrences.filter { $0.status == .completed }.count
        let pendingApproval = eligibleOccurrences.filter { $0.status == .awaitingApproval }.count
        let toDo = eligibleOccurrences.filter { occurrence in
            switch occurrence.displayStatus {
            case .overdue:
                return true
            case .stored(let status):
                return status == .notStarted || status == .inProgress || status == .needsRedo
            }
        }.count
        return MyChoresWeekSummary(toDo: toDo, pendingApproval: pendingApproval, approved: approved, total: eligibleOccurrences.count)
    }

    var plannedChoreCount: Int {
        occurrences.count
    }

    var daySections: [MyChoresDaySectionModel] {
        weekDays.map { day in
            let dayOccurrences = occurrences
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

    func configure(homeId: UUID?, weekStartsOn: Int?, timezone: String?) async {
        let previousHomeId = activeHomeId
        let previousWeekStart = calendar.firstWeekday
        let previousTimezone = self.timezone
        activeHomeId = homeId
        configureCalendar(weekStartsOn: weekStartsOn, timezone: timezone)
        if previousHomeId != homeId || previousWeekStart != calendar.firstWeekday || previousTimezone != self.timezone {
            selectedDate = nil
            visibleWeekAnchor = calendar.startOfDay(for: Date())
        }
        updateWeekDays()
        await load()
    }

    func load() async {
        guard let homeId = activeHomeId else {
            activeHomeId = nil
            occurrences = []
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
            async let loadedOccurrences = repository.fetchMyOccurrences(
                homeId: homeId,
                from: range.start,
                through: range.end
            )
            async let loadedCategories = repository.fetchCategories(homeId: homeId)
            async let loadedRooms = repository.fetchRooms(homeId: homeId)
            let (loadedMyOccurrences, categories, rooms) = try await (loadedOccurrences, loadedCategories, loadedRooms)
            let visibleOccurrences = loadedMyOccurrences.filter { occurrence in
                occurrence.dueAt >= range.start &&
                occurrence.dueAt < range.end &&
                occurrence.status != .cancelled
            }
            self.occurrences = visibleOccurrences
            categoriesById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            roomsById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
            #if DEBUG
            logMyChoresWeekBoundary(range: range)
            #endif
        } catch {
            occurrences = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load()
        }
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

    #if DEBUG
    private func logMyChoresWeekBoundary(range: (start: Date, end: Date)) {
        let groupedCardCount = daySections.reduce(0) { $0 + $1.occurrences.count }
        print("========== MY CHORES WEEK BOUNDARY ==========")
        print("week_start: \(ISO8601DateFormatter().string(from: range.start))")
        print("next_week_start: \(ISO8601DateFormatter().string(from: range.end))")
        print("visible_occurrence_count: \(occurrences.count)")
        print("grouped_card_count: \(groupedCardCount)")
        if groupedCardCount != occurrences.count {
            print("WARNING: Weekly chore grouping/count mismatch")
        }
        print("==============================================")
    }
    #endif
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
    let occurrences: [ChoreOccurrence]

    var id: Date { date }
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
    let onSelectDay: () -> Void
    let onSelectOccurrence: (ChoreOccurrence) -> Void

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
                    ForEach(section.occurrences) { occurrence in
                        MyChoresOccurrenceCard(
                            occurrence: occurrence,
                            dateTitle: section.accessibilityDateTitle,
                            onTap: { onSelectOccurrence(occurrence) }
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1) }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.08), radius: 7, x: 0, y: 4)
    }
}

private struct MyChoresOccurrenceCard: View {
    let occurrence: ChoreOccurrence
    let dateTitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.titleSnapshot)
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
        ChoreOccurrenceStatusStyle(occurrence: occurrence)
    }

    private var scheduleText: String {
        if occurrence.isAllDay {
            return "All Day"
        }
        return occurrence.dueAt.formatted(date: .omitted, time: .shortened)
    }

    private var pointsText: String {
        "\(occurrence.pointsValue) \(occurrence.pointsValue == 1 ? "point" : "points")"
    }

    private var statusText: String {
        statusStyle.title
    }

    private var accessibilityLabel: String {
        [
            occurrence.titleSnapshot,
            dateTitle,
            scheduleText,
            pointsText,
            statusText
        ].joined(separator: ". ")
    }
}

private extension ChoreOccurrence {
    var isExcludedFromWeeklySummary: Bool {
        status == .skipped || status == .cancelled
    }
}

private extension Array where Element == ChoreOccurrence {
    func sortedForMyChoresWeek() -> [ChoreOccurrence] {
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
