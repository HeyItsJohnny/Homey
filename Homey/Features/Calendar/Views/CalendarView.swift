import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = CalendarViewModel()
    @State private var isShowingAddEventPlaceholder = false

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var membersById: [UUID: HomeMemberDisplay] {
        Dictionary(uniqueKeysWithValues: homeService.membersForSelectedHome().map { ($0.userId, $0) })
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if selectedHome == nil {
                        missingHomeCard
                    } else if let errorMessage = viewModel.errorMessage, viewModel.events.isEmpty {
                        errorCard(message: errorMessage)
                    } else {
                        calendarContent
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.reload()
            }
        }
        .task(id: selectedHome?.id) {
            viewModel.configureWeekStart(selectedHome?.weekStartsOn)
            await viewModel.loadInitialData(homeId: selectedHome?.id)
        }
        .onChange(of: selectedHome?.weekStartsOn) { _, newValue in
            viewModel.configureWeekStart(newValue)
        }
        .sheet(isPresented: $isShowingAddEventPlaceholder) {
            AddEventPlaceholderSheet()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(monthTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                iconButton(systemImage: "chevron.left", label: "Previous month") {
                    Task { await viewModel.moveToPreviousMonth() }
                }

                iconButton(systemImage: "chevron.right", label: "Next month") {
                    Task { await viewModel.moveToNextMonth() }
                }

                Button {
                    Task { await viewModel.moveToToday() }
                } label: {
                    Text("Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                        .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Today")

                Button {
                    isShowingAddEventPlaceholder = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                        Text("Add Event")
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 150)
                .disabled(selectedHome == nil)
                .accessibilityLabel("Add Event")
            }
        }
    }

    private var calendarContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                monthGridCard
                    .frame(minWidth: 620)

                agendaCard
                    .frame(width: 360)
            }

            VStack(alignment: .leading, spacing: 22) {
                monthGridCard
                agendaCard
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading {
                ProgressView()
                    .tint(HomeyDashboardTheme.warmBrown)
                    .padding(12)
                    .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                    .shadow(color: HomeyDashboardTheme.primaryText.opacity(0.10), radius: 10, x: 0, y: 6)
                    .accessibilityLabel("Loading calendar events")
            }
        }
    }

    private var monthGridCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Month View")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Spacer()

                if !viewModel.events.isEmpty {
                    Text("\(viewModel.events.count) \(viewModel.events.count == 1 ? "Event" : "Events")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                ForEach(viewModel.weekdaySymbols(), id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                ForEach(viewModel.visibleDays(), id: \.self) { day in
                    CalendarDayCell(
                        date: day,
                        events: viewModel.events(on: day),
                        isCurrentMonth: viewModel.isDateInVisibleMonth(day),
                        isSelected: viewModel.isSelected(day),
                        isToday: viewModel.isToday(day)
                    ) {
                        viewModel.selectDate(day)
                    }
                }
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
    }

    private var agendaCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedDateTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(selectedDayCountText)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            if viewModel.selectedDayEvents.isEmpty {
                selectedDayEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.selectedDayEvents.enumerated()), id: \.element.id) { index, event in
                        AgendaEventRow(event: event, assignedMembers: assignedMembers(for: event))

                        if index < viewModel.selectedDayEvents.count - 1 {
                            Divider()
                                .background(HomeyDashboardTheme.softBorder)
                                .padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
    }

    private var selectedDayEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HomeyDashboardTheme.selectedSidebarBackground)
                    .frame(width: 56, height: 56)

                Image(systemName: "calendar.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("No Events")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text("Nothing is scheduled for this day.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Button {
                isShowingAddEventPlaceholder = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Event")
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private var missingHomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a Home")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Select a Home before viewing its shared calendar.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Unable to Load Calendar")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Button("Try Again") {
                Task { await viewModel.reload() }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .frame(width: 140)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 44, height: 44)
                .background(HomeyDashboardTheme.cardBackground, in: Circle())
                .overlay {
                    Circle()
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func assignedMembers(for event: CalendarEvent) -> [HomeMemberDisplay] {
        event.assignedUserIds.compactMap { membersById[$0] }
    }

    private var monthTitle: String {
        CalendarViewFormatters.monthAndYear.string(from: viewModel.visibleMonth)
    }

    private var selectedDateTitle: String {
        CalendarViewFormatters.selectedDate.string(from: viewModel.selectedDate)
    }

    private var selectedDayCountText: String {
        let count = viewModel.selectedDayEvents.count
        return "\(count) \(count == 1 ? "Event" : "Events")"
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dayNumber)
                        .font(.subheadline.weight(isSelected || isToday ? .bold : .semibold))
                        .foregroundStyle(dayForeground)
                        .frame(width: 30, height: 30)
                        .background(dayNumberBackground, in: Circle())

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 2)

                HStack(spacing: 4) {
                    ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle()
                            .fill(event.indicatorColor)
                            .frame(width: 7, height: 7)
                    }

                    if events.count > 3 {
                        Text("+\(events.count - 3)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: 12)
            }
            .padding(10)
            .frame(minHeight: 86, alignment: .topLeading)
            .background(cellBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(cellBorder, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumber: String {
        String(Calendar.autoupdatingCurrent.component(.day, from: date))
    }

    private var dayForeground: Color {
        if isSelected {
            return .white
        }

        if isToday {
            return HomeyDashboardTheme.warmBrown
        }

        return isCurrentMonth ? HomeyDashboardTheme.primaryText : HomeyDashboardTheme.secondaryText.opacity(0.55)
    }

    @ViewBuilder
    private var dayNumberBackground: some View {
        if isSelected {
            HomeyDashboardTheme.warmBrown
        } else if isToday {
            HomeyDashboardTheme.selectedSidebarBackground
        } else {
            Color.clear
        }
    }

    private var cellBackground: Color {
        if isSelected {
            return HomeyDashboardTheme.selectedSidebarBackground.opacity(0.9)
        }

        return HomeyDashboardTheme.cardBackground.opacity(isCurrentMonth ? 0.72 : 0.36)
    }

    private var cellBorder: Color {
        isSelected ? HomeyDashboardTheme.warmBrown.opacity(0.45) : HomeyDashboardTheme.softBorder
    }

    private var accessibilityLabel: String {
        let dateText = CalendarViewFormatters.selectedDate.string(from: date)
        let countText = "\(events.count) \(events.count == 1 ? "event" : "events")"
        let selectedText = isSelected ? ", selected" : ""
        return "\(dateText), \(countText)\(selectedText)"
    }
}

private struct AgendaEventRow: View {
    let event: CalendarEvent
    let assignedMembers: [HomeMemberDisplay]

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(event.indicatorColor)
                .frame(width: 8, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)

                    if event.isAllDay {
                        Text("All Day")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }
                }

                Text(timeText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }

                if !assignedMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(assignedMembers.prefix(4)) { member in
                            AvatarView(
                                imageURL: member.avatarURL,
                                initials: member.initials,
                                size: 30,
                                accentColor: HomeyDashboardTheme.warmBrown,
                                borderWidth: 2,
                                showsShadow: false,
                                accessibilityLabel: "Assigned to \(member.displayName)"
                            )
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(timeText)")
    }

    private var timeText: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(CalendarViewFormatters.eventTime.string(from: event.startsAt)) - \(CalendarViewFormatters.eventTime.string(from: event.endsAt))"
    }
}

private struct AddEventPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(HomeyDashboardTheme.selectedSidebarBackground)
                        .frame(width: 72, height: 72)

                    Image(systemName: "calendar.badge.plus")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }

                VStack(spacing: 6) {
                    Text("Event Editor Coming Soon")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text("The calendar data layer is ready. Event creation UI will be added next.")
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 140)
            }
            .padding(34)
            .frame(maxWidth: 420)
            .dashboardCard(cornerRadius: 30)
        }
        .presentationDetents([.medium])
    }
}

private enum CalendarViewFormatters {
    static let monthAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    static let selectedDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    static let eventTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension CalendarEvent {
    var indicatorColor: Color {
        Color(hex: categoryColorHex) ?? HomeyDashboardTheme.warmBrown
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else {
            return nil
        }

        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }

        guard normalized.count == 6,
              let value = Int(normalized, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

#Preview("Calendar") {
    CalendarView()
        .environmentObject(HomeService())
}
