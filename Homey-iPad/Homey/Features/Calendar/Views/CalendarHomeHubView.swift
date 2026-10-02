import Combine
import Foundation
import SwiftUI

private enum HomeHubCalendarMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

private struct HomeHubActivity: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let iconName: String
    let color: Color
    let location: String?
}

@MainActor
private final class CalendarHomeHubViewModel: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let calendarService = CalendarService()
    private var loadTask: Task<Void, Never>?

    func load(homeID: UUID?, date: Date, calendar: Calendar) {
        loadTask?.cancel()
        guard let homeID, let range = Self.visibleRange(containing: date, calendar: calendar) else {
            events = []
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            errorMessage = nil

            do {
                let loadedEvents = try await calendarService.fetchEvents(
                    homeId: homeID,
                    rangeStart: range.start,
                    rangeEnd: range.end
                )
                try Task.checkCancellation()

                events = loadedEvents
            } catch is CancellationError {
                return
            } catch {
                events = []
                errorMessage = "Calendar events couldn’t be loaded right now."
            }

            isLoading = false
        }
    }

    func activities(in range: DateInterval) -> [HomeHubActivity] {
        events.compactMap { event -> HomeHubActivity? in
            guard event.occurrenceStartsAt < range.end, event.occurrenceEndsAt > range.start else { return nil }
            return HomeHubActivity(
                id: "event-\(event.occurrenceId)",
                title: event.title,
                start: event.occurrenceStartsAt,
                end: event.occurrenceEndsAt,
                isAllDay: event.isAllDay,
                iconName: event.categoryIconName ?? "calendar",
                color: Color(hex: event.categoryColorHex) ?? HomeyDashboardTheme.lavenderAccent,
                location: event.location
            )
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private static func visibleRange(containing date: Date, calendar: Calendar) -> DateInterval? {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start,
              let lastMonthDay = calendar.date(byAdding: .day, value: -1, to: month.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastMonthDay),
              let gridEnd = calendar.date(byAdding: .day, value: 7, to: lastWeek.start) else { return nil }
        return DateInterval(start: gridStart, end: gridEnd)
    }

}

struct CalendarHomeHubView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = CalendarHomeHubViewModel()
    @State private var mode: HomeHubCalendarMode = .week
    @State private var selectedDate = Date()

    private var calendar: Calendar {
        var value = Calendar.autoupdatingCurrent
        value.firstWeekday = homeService.selectedHome()?.weekStartsOn ?? 1
        if let identifier = homeService.selectedHome()?.timezone,
           let timeZone = TimeZone(identifier: identifier) {
            value.timeZone = timeZone
        }
        return value
    }

    private var loadKey: String {
        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        return "\(homeService.selectedHomeID?.uuidString ?? "none")-\(components.year ?? 0)-\(components.month ?? 0)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            dateNavigation

            HStack(alignment: .top, spacing: 16) {
                mainCalendar
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HomeHubRightColumn(
                    selectedDate: $selectedDate,
                    calendar: calendar,
                    activities: selectedDayActivities
                )
                .frame(width: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: loadKey) {
            viewModel.load(homeID: homeService.selectedHomeID, date: selectedDate, calendar: calendar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calendar")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(HomeHubCalendarMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(mode == option ? .white : HomeyDashboardTheme.primaryText)
                        .frame(width: 76, height: 36)
                        .background(
                            mode == option ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(HomeyDashboardTheme.currentHomeBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var dateNavigation: some View {
        HStack(spacing: 10) {
            Button { moveDate(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .homeHubNavigationButton()

            Text(dateNavigationTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .frame(minWidth: 190)

            Button { moveDate(1) } label: {
                Image(systemName: "chevron.right")
            }
            .homeHubNavigationButton()

            Spacer()

            modePicker

            Button("Today") { selectedDate = Date() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .buttonStyle(.plain)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyDashboardTheme.warmBrown)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.softRed)
            }
        }
    }

    @ViewBuilder
    private var mainCalendar: some View {
        switch mode {
        case .day:
            HomeHubTimeline(days: [calendar.startOfDay(for: selectedDate)], selectedDate: $selectedDate, calendar: calendar, activities: activitiesForDisplay)
        case .week:
            HomeHubTimeline(days: weekDays, selectedDate: $selectedDate, calendar: calendar, activities: activitiesForDisplay)
        case .month:
            HomeHubMonthGrid(
                selectedDate: $selectedDate,
                calendar: calendar,
                activities: activitiesForDisplay,
                onSelectDate: openDay
            )
        }
    }

    private var weekDays: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [selectedDate] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var displayRange: DateInterval {
        switch mode {
        case .day:
            let start = calendar.startOfDay(for: selectedDate)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let start = weekDays.first ?? selectedDate
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        case .month:
            return calendar.dateInterval(of: .month, for: selectedDate) ?? DateInterval(start: selectedDate, duration: 1)
        }
    }

    private var activitiesForDisplay: [HomeHubActivity] {
        viewModel.activities(in: displayRange)
    }

    private var selectedDayRange: DateInterval {
        let start = calendar.startOfDay(for: selectedDate)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    private var selectedDayActivities: [HomeHubActivity] {
        viewModel.activities(in: selectedDayRange)
    }

    private var dateNavigationTitle: String {
        switch mode {
        case .day:
            return HomeHubFormatters.fullDay.string(from: selectedDate)
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else { return "This Week" }
            return "\(HomeHubFormatters.shortDate.string(from: first)) – \(HomeHubFormatters.shortDate.string(from: last))"
        case .month:
            return HomeHubFormatters.monthYear.string(from: selectedDate)
        }
    }

    private func moveDate(_ direction: Int) {
        let component: Calendar.Component = mode == .day ? .day : (mode == .week ? .weekOfYear : .month)
        selectedDate = calendar.date(byAdding: component, value: direction, to: selectedDate) ?? selectedDate
    }

    private func openDay(_ date: Date) {
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedDate = date
            mode = .day
        }
    }
}

private struct HomeHubTimeline: View {
    let days: [Date]
    @Binding var selectedDate: Date
    let calendar: Calendar
    let activities: [HomeHubActivity]
    @State private var expandedAllDayKeys: Set<String> = []

    private let firstHour = 6
    private let finalHour = 22
    private let hourHeight: CGFloat = 58
    private let headerHeight: CGFloat = 52
    private let labelWidth: CGFloat = 52
    private let allDayRowHeight: CGFloat = 52
    private let allDayRowSpacing: CGFloat = 6
    private let allDayVerticalPadding: CGFloat = 8
    private let allDayControlHeight: CGFloat = 26

    private var allDaySectionHeight: CGFloat {
        days.map(allDayHeight).max() ?? 0
    }

    private var timelineOrigin: CGFloat {
        headerHeight + allDaySectionHeight
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    timelineGrid(width: proxy.size.width)
                    allDayCards(width: proxy.size.width)
                    timedActivityCards(width: proxy.size.width)

                    if activities.isEmpty {
                        Text("Nothing scheduled")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .frame(width: max(0, proxy.size.width - labelWidth), alignment: .center)
                            .offset(x: labelWidth, y: timelineOrigin + 42)
                    }
                }
                .frame(height: timelineOrigin + CGFloat(finalHour - firstHour) * hourHeight)
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .dashboardCard(cornerRadius: 26)
        .onChange(of: selectedDate) { _, _ in
            expandedAllDayKeys.removeAll()
        }
    }

    private func timelineGrid(width: CGFloat) -> some View {
        let columnWidth = (width - labelWidth) / CGFloat(max(days.count, 1))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Button {
                    selectedDate = day
                } label: {
                    VStack(spacing: 3) {
                        Text(HomeHubFormatters.weekday.string(from: day).uppercased())
                            .font(.caption2.weight(.bold))
                        Text(day.formatted(.dateTime.day()))
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : HomeyDashboardTheme.primaryText)
                    .frame(width: columnWidth - 4, height: 44)
                    .background(
                        calendar.isDate(day, inSameDayAs: selectedDate) ? HomeyDashboardTheme.warmBrown : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .position(x: labelWidth + columnWidth * (CGFloat(index) + 0.5), y: 23)
            }

            ForEach(firstHour...finalHour, id: \.self) { hour in
                let y = timelineOrigin + CGFloat(hour - firstHour) * hourHeight
                Text(HomeHubFormatters.hour.string(from: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) ?? selectedDate))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .frame(width: labelWidth - 8, alignment: .trailing)
                    .position(x: (labelWidth - 8) / 2, y: y)
                Path { path in
                    path.move(to: CGPoint(x: labelWidth, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.65), lineWidth: 0.7)
            }
        }
    }

    private func allDayCards(width: CGFloat) -> some View {
        let columnWidth = (width - labelWidth) / CGFloat(max(days.count, 1))
        return ZStack(alignment: .topLeading) {
            if allDaySectionHeight > 0 {
                Text("ALL DAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .frame(width: labelWidth - 8, alignment: .trailing)
                    .position(
                        x: (labelWidth - 8) / 2,
                        y: headerHeight + allDayVerticalPadding + allDayRowHeight / 2
                    )

                ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, day in
                    let dayActivities = allDayActivities(on: day)
                    let isExpanded = expandedAllDayKeys.contains(dayKey(day))
                    let visibleActivities = isExpanded ? dayActivities : Array(dayActivities.prefix(1))

                    ForEach(Array(visibleActivities.enumerated()), id: \.element.id) { rowIndex, activity in
                        HomeHubActivityCard(activity: activity, compact: days.count > 1)
                            .frame(width: columnWidth - 7, height: allDayRowHeight, alignment: .topLeading)
                            .position(
                                x: labelWidth + columnWidth * (CGFloat(dayIndex) + 0.5),
                                y: headerHeight
                                    + allDayVerticalPadding
                                    + CGFloat(rowIndex) * (allDayRowHeight + allDayRowSpacing)
                                    + allDayRowHeight / 2
                            )
                    }

                    if dayActivities.count > 1 {
                        Button {
                            toggleAllDayExpansion(for: day)
                        } label: {
                            Text(isExpanded ? "Show Less" : "+\(dayActivities.count - 1) more")
                                .font((days.count > 1 ? Font.caption2 : Font.caption).weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    HomeyDashboardTheme.selectedSidebarBackground.opacity(0.72),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(width: columnWidth - 7, height: allDayControlHeight)
                        .position(
                            x: labelWidth + columnWidth * (CGFloat(dayIndex) + 0.5),
                            y: headerHeight
                                + allDayVerticalPadding
                                + CGFloat(visibleActivities.count) * (allDayRowHeight + allDayRowSpacing)
                                + allDayControlHeight / 2
                        )
                        .accessibilityLabel(isExpanded ? "Show fewer all-day activities" : "Show \(dayActivities.count - 1) more all-day activities")
                    }
                }

                Path { path in
                    path.move(to: CGPoint(x: labelWidth, y: timelineOrigin))
                    path.addLine(to: CGPoint(x: width, y: timelineOrigin))
                }
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
        }
    }

    private func timedActivityCards(width: CGFloat) -> some View {
        let columnWidth = (width - labelWidth) / CGFloat(max(days.count, 1))
        return ForEach(activities.filter { !$0.isAllDay }) { activity in
            if let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: activity.start) }) {
                let startMinutes = calendar.component(.hour, from: activity.start) * 60 + calendar.component(.minute, from: activity.start)
                let endMinutes = calendar.component(.hour, from: activity.end) * 60 + calendar.component(.minute, from: activity.end)
                let clippedStart = max(startMinutes, firstHour * 60)
                let duration = max(30, min(endMinutes, finalHour * 60) - clippedStart)
                let y = timelineOrigin + CGFloat(clippedStart - firstHour * 60) / 60 * hourHeight
                let height = max(34, CGFloat(duration) / 60 * hourHeight - 3)

                HomeHubActivityCard(activity: activity, compact: days.count > 1)
                    .frame(width: columnWidth - 7, height: height, alignment: .topLeading)
                    .position(
                        x: labelWidth + columnWidth * (CGFloat(dayIndex) + 0.5),
                        y: y + height / 2
                    )
            }
        }
    }

    private func allDayActivities(on day: Date) -> [HomeHubActivity] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        return activities
            .filter { $0.isAllDay && $0.start < dayEnd && $0.end > dayStart }
            .sorted { lhs, rhs in
                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
                return lhs.id < rhs.id
            }
    }

    private func allDayHeight(for day: Date) -> CGFloat {
        let count = allDayActivities(on: day).count
        guard count > 0 else { return 0 }

        let visibleCount = expandedAllDayKeys.contains(dayKey(day)) ? count : 1
        var height = allDayVerticalPadding * 2
            + CGFloat(visibleCount) * allDayRowHeight
            + CGFloat(max(0, visibleCount - 1)) * allDayRowSpacing

        if count > 1 {
            height += allDayRowSpacing + allDayControlHeight
        }
        return height
    }

    private func toggleAllDayExpansion(for day: Date) {
        let key = dayKey(day)
        withAnimation(.easeInOut(duration: 0.16)) {
            if expandedAllDayKeys.contains(key) {
                expandedAllDayKeys.remove(key)
            } else {
                expandedAllDayKeys.insert(key)
            }
        }
    }

    private func dayKey(_ day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

}

private struct HomeHubActivityCard: View {
    let activity: HomeHubActivity
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 5) {
            HStack(spacing: 5) {
                Image(systemName: activity.iconName)
                    .font(.caption2.weight(.bold))
                Text(activity.title)
                    .font((compact ? Font.caption2 : Font.subheadline).weight(.bold))
                    .lineLimit(compact ? 2 : 1)
            }
            if !compact {
                Text(activity.isAllDay ? "All Day" : "\(HomeHubFormatters.time.string(from: activity.start))–\(HomeHubFormatters.time.string(from: activity.end))")
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
        }
        .foregroundStyle(HomeyDashboardTheme.primaryText)
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 5 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(activity.color.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(activity.color).frame(width: 3).padding(.vertical, 7)
        }
        .clipped()
    }
}

private struct HomeHubMonthGrid: View {
    @Binding var selectedDate: Date
    let calendar: Calendar
    let activities: [HomeHubActivity]
    let onSelectDate: (Date) -> Void

    private var days: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: selectedDate),
              let start = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days, id: \.self) { day in
                    let dayActivities = activities.filter { calendar.isDate($0.start, inSameDayAs: day) }
                    let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(day)
                    let isCurrentMonth = isInSelectedMonth(day)

                    Button { onSelectDate(day) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(.bold))

                                Spacer(minLength: 4)

                                if isToday {
                                    Text("TODAY")
                                        .font(.system(size: 8, weight: .bold))
                                }
                            }

                            HStack(spacing: 3) {
                                ForEach(Array(dayActivities.prefix(3))) { activity in
                                    Circle()
                                        .fill(isSelected ? Color.white.opacity(0.9) : activity.color)
                                        .frame(width: 6, height: 6)
                                }
                                if dayActivities.count > 3 {
                                    Text("+\(dayActivities.count - 3)").font(.caption2.weight(.bold))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(
                            isSelected
                                ? Color.white
                                : HomeyDashboardTheme.primaryText.opacity(isCurrentMonth ? 1 : 0.42)
                        )
                        .padding(9)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(monthCellBackground(isSelected: isSelected, isCurrentMonth: isCurrentMonth))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isToday && !isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.softBorder.opacity(0.55),
                                    lineWidth: isToday && !isSelected ? 1.5 : 0.7
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: day, activityCount: dayActivities.count))
                    .accessibilityHint("Opens this date in Day view")
                }
            }
        }
        .padding(16)
        .dashboardCard(cornerRadius: 26)
    }

    private var weekdaySymbols: [String] {
        HomeHubFormatters.twoLetterWeekdaySymbols(for: calendar)
    }

    private func isInSelectedMonth(_ date: Date) -> Bool {
        calendar.component(.month, from: date) == calendar.component(.month, from: selectedDate)
    }

    private func monthCellBackground(isSelected: Bool, isCurrentMonth: Bool) -> Color {
        if isSelected {
            return HomeyDashboardTheme.warmBrown
        }
        if isCurrentMonth {
            return HomeyDashboardTheme.cardBackground.opacity(0.62)
        }
        return HomeyDashboardTheme.cardBackground.opacity(0.24)
    }

    private func accessibilityLabel(for date: Date, activityCount: Int) -> String {
        let dateText = HomeHubFormatters.fullDay.string(from: date)
        guard activityCount > 0 else { return "\(dateText), nothing scheduled" }
        return "\(dateText), \(activityCount) \(activityCount == 1 ? "activity" : "activities")"
    }
}

private struct HomeHubRightColumn: View {
    @Binding var selectedDate: Date
    let calendar: Calendar
    let activities: [HomeHubActivity]

    var body: some View {
        VStack(spacing: 14) {
            MiniMonthCard(selectedDate: $selectedDate, calendar: calendar)
            SelectedDayAgendaCard(
                date: selectedDate,
                activities: activities
            )
            .frame(maxHeight: .infinity)
        }
    }
}

private struct MiniMonthCard: View {
    @Binding var selectedDate: Date
    let calendar: Calendar

    private var days: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: selectedDate),
              let start = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(HomeHubFormatters.monthYear.string(from: selectedDate))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Spacer()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption2.weight(.bold)).foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                ForEach(days, id: \.self) { day in
                    Button { selectedDate = day } label: {
                        Text(day.formatted(.dateTime.day()))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(calendar.isDate(day, inSameDayAs: selectedDate) ? .white : HomeyDashboardTheme.primaryText)
                            .frame(width: 27, height: 27)
                            .background(
                                calendar.isDate(day, inSameDayAs: selectedDate) ? HomeyDashboardTheme.warmBrown : Color.clear,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .dashboardCard(cornerRadius: 22)
    }

    private func changeMonth(_ value: Int) {
        selectedDate = calendar.date(byAdding: .month, value: value, to: selectedDate) ?? selectedDate
    }

    private var weekdaySymbols: [String] {
        HomeHubFormatters.twoLetterWeekdaySymbols(for: calendar)
    }
}

private struct SelectedDayAgendaCard: View {
    let date: Date
    let activities: [HomeHubActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(HomeHubFormatters.agendaDay.string(from: date))
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Divider()
                .overlay(HomeyDashboardTheme.softBorder)

            if sortedActivities.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)

                    Text("Nothing scheduled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        if !allDayActivities.isEmpty {
                            Text("ALL DAY")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                                .padding(.bottom, 1)

                            ForEach(allDayActivities) { activity in
                                SelectedDayAgendaRow(activity: activity)
                            }
                        }

                        if !allDayActivities.isEmpty && !timedActivities.isEmpty {
                            Divider()
                                .overlay(HomeyDashboardTheme.softBorder.opacity(0.75))
                                .padding(.vertical, 3)
                        }

                        ForEach(timedActivities) { activity in
                            SelectedDayAgendaRow(activity: activity)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: 22)
    }

    private var sortedActivities: [HomeHubActivity] {
        activities.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if !lhs.isAllDay, lhs.start != rhs.start { return lhs.start < rhs.start }

            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private var allDayActivities: [HomeHubActivity] {
        sortedActivities.filter(\.isAllDay)
    }

    private var timedActivities: [HomeHubActivity] {
        sortedActivities.filter { !$0.isAllDay }
    }

}

private struct SelectedDayAgendaRow: View {
    let activity: HomeHubActivity

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: activity.iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(activity.color)
                .frame(width: 30, height: 30)
                .background(activity.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                Text(activity.isAllDay ? "All Day" : HomeHubFormatters.time.string(from: activity.start))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                if let location = activity.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func homeHubNavigationButton() -> some View {
        self
            .font(.caption.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(width: 36, height: 36)
            .background(HomeyDashboardTheme.cardBackground, in: Circle())
            .buttonStyle(.plain)
    }
}

private enum HomeHubFormatters {
    static let fullDay: DateFormatter = formatter("EEE, MMM d, yyyy")
    static let shortDate: DateFormatter = formatter("MMM d")
    static let monthYear: DateFormatter = formatter("MMMM yyyy")
    static let weekday: DateFormatter = formatter("EEE")
    static let hour: DateFormatter = formatter("h a")
    static let time: DateFormatter = formatter("h:mm a")
    static let agendaDay: DateFormatter = formatter("EEEE, MMMM d")

    static func twoLetterWeekdaySymbols(for calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map { String($0.prefix(2)) }
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}
