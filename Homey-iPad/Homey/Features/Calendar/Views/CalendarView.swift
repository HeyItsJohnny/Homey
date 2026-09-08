import SwiftUI

struct CalendarView: View {
    let focusDate: Date?

    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = CalendarViewModel()
    @State private var editorPresentation: CalendarEditorPresentation?
    @State private var chorePresentation: ChoreCalendarPresentation?
    @State private var mealPresentation: MealCalendarPresentation?
    @State private var eventPendingEditScope: CalendarEvent?
    @State private var successMessage: String?
    @State private var choreRouteErrorMessage: String?
    @State private var resolvingChoreCalendarEventId: UUID?

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var membersById: [UUID: HomeMemberDisplay] {
        Dictionary(uniqueKeysWithValues: homeService.membersForSelectedHome().map { ($0.userId, $0) })
    }

    init(focusDate: Date? = nil) {
        self.focusDate = focusDate
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let successMessage {
                        CalendarStatusBanner(message: successMessage)
                            .transition(.opacity)
                    }

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
            await loadMembersIfNeeded()
            await viewModel.loadInitialData(homeId: selectedHome?.id)

            if let focusDate {
                await viewModel.focus(on: focusDate)
            }
        }
        .onChange(of: selectedHome?.weekStartsOn) { _, newValue in
            viewModel.configureWeekStart(newValue)
            Task {
                await viewModel.reload()
            }
        }
        .onDisappear {
            Task {
                await viewModel.stopRealtimeUpdates()
            }
        }
        .onChange(of: focusDate) { _, newValue in
            guard let newValue else {
                return
            }

            Task {
                await viewModel.focus(on: newValue)
            }
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                let reason = notification.userInfo?[HomeyCalendarRefreshReason.userInfoKey] as? String
                    ?? HomeyCalendarRefreshReason.calendarEventsChanged
                await viewModel.reloadAfterExternalCalendarChange(reason: reason)
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            EventEditorView(
                mode: presentation.mode,
                selectedDate: presentation.selectedDate,
                categories: viewModel.categories,
                members: homeService.membersForSelectedHome(),
                isSaving: viewModel.isSavingEvent,
                isDeleting: viewModel.isDeletingEvent,
                errorMessage: viewModel.errorMessage,
                onSave: { draft in
                    switch presentation.mode {
                    case .create:
                        return await viewModel.createEvent(
                            homeId: selectedHome?.id,
                            title: draft.title,
                            notes: draft.notes,
                            location: draft.location,
                            startDate: draft.startDate,
                            endDate: draft.endDate,
                            isAllDay: draft.isAllDay,
                            timezone: draft.timezone,
                            categoryId: draft.categoryId,
                            assignedUserIds: draft.assignedUserIds,
                            recurrence: draft.recurrence
                        )
                    case .edit(let event, let scope):
                        switch scope {
                        case .singleOccurrence:
                            return await viewModel.updateOccurrence(
                                eventId: event.eventId,
                                occurrenceStartsAt: event.occurrenceStartsAt,
                                title: draft.title,
                                notes: draft.notes,
                                location: draft.location,
                                startDate: draft.startDate,
                                endDate: draft.endDate,
                                isAllDay: draft.isAllDay,
                                timezone: draft.timezone,
                                categoryId: draft.categoryId
                            )
                        case .entireSeries:
                            return await viewModel.updateEvent(
                                eventId: event.eventId,
                                title: draft.title,
                                notes: draft.notes,
                                location: draft.location,
                                startDate: draft.startDate,
                                endDate: draft.endDate,
                                isAllDay: draft.isAllDay,
                                timezone: draft.timezone,
                                categoryId: draft.categoryId,
                                assignedUserIds: draft.assignedUserIds,
                                recurrence: draft.recurrence
                            )
                        }
                    }
                },
                onDelete: presentation.event.map { event in
                    { scope in
                        switch scope {
                        case .singleOccurrence:
                            return await viewModel.deleteOccurrence(
                                eventId: event.eventId,
                                occurrenceStartsAt: event.occurrenceStartsAt
                            )
                        case .entireSeries:
                            return await viewModel.deleteEvent(eventId: event.eventId)
                        }
                    }
                },
                onSuccess: { completion in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        successMessage = completion.successMessage
                    }
                }
            )
        }
        .sheet(item: $chorePresentation, onDismiss: {
            Task {
                await viewModel.reload()
            }
        }) { presentation in
            ChoreOccurrenceDetailView(
                initialOccurrence: presentation.occurrence,
                homeTimezone: selectedHome?.timezone ?? TimeZone.autoupdatingCurrent.identifier
            )
        }
        .sheet(item: $mealPresentation, onDismiss: {
            Task {
                await viewModel.reload()
            }
        }) { presentation in
            MealEditorView(
                mode: .edit(mealID: presentation.plannedMeal.meal.id),
                onSaved: { _, _, _ in
                    Task {
                        await viewModel.reload()
                    }
                },
                onDelete: { _ in
                    Task {
                        await viewModel.reload()
                    }
                }
            )
        }
        .alert(
            "Unable to find the linked chore.",
            isPresented: Binding(
                get: { choreRouteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        choreRouteErrorMessage = nil
                    }
                }
            )
        ) {
            Button("Close", role: .cancel) {
                choreRouteErrorMessage = nil
            }
        } message: {
            Text(choreRouteErrorMessage ?? "Close this message and try again.")
        }
        .confirmationDialog(
            "Edit Recurring Event",
            isPresented: Binding(
                get: { eventPendingEditScope != nil },
                set: { isPresented in
                    if !isPresented {
                        eventPendingEditScope = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("This Event Only") {
                if let event = eventPendingEditScope {
                    editorPresentation = CalendarEditorPresentation(
                        mode: .edit(event, scope: .singleOccurrence),
                        selectedDate: event.occurrenceStartsAt
                    )
                }
                eventPendingEditScope = nil
            }

            Button("Entire Series") {
                if let event = eventPendingEditScope {
                    editorPresentation = CalendarEditorPresentation(
                        mode: .edit(event, scope: .entireSeries),
                        selectedDate: event.startsAt
                    )
                }
                eventPendingEditScope = nil
            }

            Button("Cancel", role: .cancel) {
                eventPendingEditScope = nil
            }
        }
    }

    private var calendarPeriodControls: some View {
        HStack(spacing: 10) {
            iconButton(systemImage: "chevron.left", label: previousPeriodAccessibilityLabel) {
                Task { await viewModel.moveToPreviousPeriod() }
            }

            Text(visibleRangeTitle)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityAddTraits(.isHeader)

            iconButton(systemImage: "chevron.right", label: nextPeriodAccessibilityLabel) {
                Task { await viewModel.moveToNextPeriod() }
            }
        }
    }

    private var calendarDisplayControls: some View {
        HStack(spacing: 10) {
            Picker("Calendar View", selection: displayModeBinding) {
                ForEach(CalendarDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 176)
            .accessibilityLabel("Calendar view")

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
            .accessibilityLabel("Go to today")
        }
    }

    private var addEventButton: some View {
        Button {
            presentCreateEditor()
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

    private var calendarControlsBelowFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                calendarDisplayControls

                Spacer(minLength: 18)

                addEventButton
            }

            VStack(alignment: .leading, spacing: 12) {
                calendarDisplayControls
                HStack {
                    Spacer(minLength: 0)
                    addEventButton
                }
            }
        }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            calendarFilterButtons

            if viewModel.eventFilter == .all {
                HomeCalendarAllView(
                    homeId: selectedHome?.id,
                    role: homeService.currentMembershipForSelectedHome()?.role ?? selectedHome?.role,
                    weekStartsOn: selectedHome?.weekStartsOn,
                    timezone: selectedHome?.timezone,
                    members: homeService.membersForSelectedHome(),
                    currentUserId: authenticationService.currentUser?.id,
                    onOpenMeals: {
                        viewModel.setEventFilter(.meals)
                    },
                    onOpenChores: {
                        viewModel.setEventFilter(.chores)
                    },
                    onOpenCalendar: {
                        viewModel.setEventFilter(.calendar)
                        Task { await viewModel.moveToToday() }
                    },
                    onOpenMeal: { plannedMeal in
                        mealPresentation = MealCalendarPresentation(plannedMeal: plannedMeal)
                    }
                )
            } else if viewModel.eventFilter == .meals {
                HomeCalendarMealsView(
                    homeId: selectedHome?.id,
                    weekStartsOn: selectedHome?.weekStartsOn,
                    timezone: selectedHome?.timezone,
                    onOpenMeal: { plannedMeal in
                        mealPresentation = MealCalendarPresentation(plannedMeal: plannedMeal)
                    }
                )
            } else if viewModel.eventFilter == .chores {
                HomeCalendarChoresView(
                    homeId: selectedHome?.id,
                    role: homeService.currentMembershipForSelectedHome()?.role ?? selectedHome?.role,
                    weekStartsOn: selectedHome?.weekStartsOn,
                    timezone: selectedHome?.timezone,
                    members: homeService.membersForSelectedHome(),
                    currentUserId: authenticationService.currentUser?.id
                )
            } else {
                calendarPeriodControls
                calendarControlsBelowFilters
                primaryCalendarCard
                selectedDayDetailsCard
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading || resolvingChoreCalendarEventId != nil {
                ProgressView()
                    .tint(HomeyDashboardTheme.warmBrown)
                    .padding(12)
                    .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                    .shadow(color: HomeyDashboardTheme.primaryText.opacity(0.10), radius: 10, x: 0, y: 6)
                    .accessibilityLabel(resolvingChoreCalendarEventId == nil ? "Loading calendar events" : "Opening chore")
            }
        }
    }

    private var calendarFilterButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Spacer(minLength: 0)
                calendarFilterButtonGroup
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal) {
                calendarFilterButtonGroup
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
    }

    private var calendarFilterButtonGroup: some View {
        HStack(spacing: 8) {
            ForEach(CalendarEventFilter.allCases) { filter in
                Button {
                    viewModel.setEventFilter(filter)
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(viewModel.eventFilter == filter ? Color.white : HomeyDashboardTheme.primaryText)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background(
                            viewModel.eventFilter == filter ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(filter.title) events")
                .accessibilityAddTraits(viewModel.eventFilter == filter ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var primaryCalendarCard: some View {
        switch viewModel.displayMode {
        case .month:
            monthGridCard
        case .week:
            weekGridCard
        }
    }

    private var monthGridCard: some View {
        CalendarMonthGrid(
            weekdaySymbols: viewModel.weekdaySymbols(),
            days: viewModel.visibleDays(),
            eventsForDay: viewModel.events(on:),
            categories: viewModel.categories,
            linkedPresentation: viewModel.linkedPresentation(for:),
            isCurrentMonth: viewModel.isDateInVisibleMonth,
            isSelected: viewModel.isSelected,
            isToday: viewModel.isToday,
            onSelectDay: viewModel.selectDate,
            onSelectEvent: presentEditEditor(for:)
        )
    }

    private var weekGridCard: some View {
        CalendarWeekGrid(
            days: viewModel.weekDays(),
            eventsForDay: viewModel.events(on:),
            categories: viewModel.categories,
            linkedPresentation: viewModel.linkedPresentation(for:),
            assignedMembers: assignedMembers(for:),
            isSelected: viewModel.isSelected,
            isToday: viewModel.isToday,
            onSelectDay: viewModel.selectDate,
            onSelectEvent: presentEditEditor(for:)
        )
    }

    private var selectedDayDetailsCard: some View {
        CalendarDayDetailsView(
            title: selectedDateTitle,
            countText: selectedDayCountText,
            events: viewModel.selectedDayEvents,
            categories: viewModel.categories,
            linkedPresentation: viewModel.linkedPresentation(for:),
            assignedMembers: assignedMembers(for:),
            onSelectEvent: presentEditEditor(for:),
            onAddEvent: presentCreateEditor
        )
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

    private func presentCreateEditor() {
        successMessage = nil
        editorPresentation = CalendarEditorPresentation(mode: .create, selectedDate: viewModel.selectedDate)
    }

    private func presentEditEditor(for event: CalendarEvent) {
        successMessage = nil
        Task {
            await presentEditEditorAfterChoreLinkCheck(for: event)
        }
    }

    private func presentEditEditorAfterChoreLinkCheck(for event: CalendarEvent) async {
        if let presentation = viewModel.linkedPresentation(for: event) {
            switch presentation.content {
            case .meal(let plannedMeal):
                mealPresentation = MealCalendarPresentation(plannedMeal: plannedMeal)
            case .chore(let chore):
                chorePresentation = ChoreCalendarPresentation(occurrence: chore.occurrence)
            }
            return
        }

        resolvingChoreCalendarEventId = event.eventId

        do {
            let occurrence = try await ChoresRepository().fetchOccurrence(calendarEventId: event.eventId)
            guard resolvingChoreCalendarEventId == event.eventId else {
                return
            }
            resolvingChoreCalendarEventId = nil

            if let occurrence {
                #if DEBUG
                print("========== CHORE CALENDAR ROUTE ==========")
                print("calendar_event_id: \(event.eventId.uuidString)")
                print("occurrence_id: \(occurrence.id.uuidString)")
                print("==========================================")
                #endif
                chorePresentation = ChoreCalendarPresentation(occurrence: occurrence)
                return
            }

            if eventLooksLikeChoreEvent(event) {
                #if DEBUG
                print("Unable to find linked chore occurrence")
                print("calendar_event_id: \(event.eventId.uuidString)")
                #endif
                choreRouteErrorMessage = "This calendar event is linked to a chore, but Homey could not find the chore occurrence."
                return
            }
        } catch {
            guard resolvingChoreCalendarEventId == event.eventId else {
                return
            }
            resolvingChoreCalendarEventId = nil

            #if DEBUG
            print("Unable to resolve chore-linked calendar event")
            print("calendar_event_id: \(event.eventId.uuidString)")
            print(String(reflecting: error))
            #endif

            if eventLooksLikeChoreEvent(event) {
                choreRouteErrorMessage = "This calendar event is linked to a chore, but Homey could not open it."
                return
            }
        }

        guard resolvingChoreCalendarEventId == nil else {
            return
        }

        if event.isRecurring {
            eventPendingEditScope = event
        } else {
            editorPresentation = CalendarEditorPresentation(mode: .edit(event), selectedDate: event.occurrenceStartsAt)
        }
    }

    private func eventLooksLikeChoreEvent(_ event: CalendarEvent) -> Bool {
        event.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Chore") == .orderedSame
    }

    private func isChoreLinkedCalendarEvent(_ event: CalendarEvent) async -> Bool {
        if await resolveChoreOccurrence(for: event) != nil {
            return true
        }

        return false
    }

    private func resolveChoreOccurrence(for event: CalendarEvent) async -> ChoreOccurrence? {
        do {
            return try await ChoresRepository().fetchOccurrence(calendarEventId: event.eventId)
        } catch {
            #if DEBUG
            print("Unable to resolve chore-linked calendar event")
            print("calendar_event_id: \(event.eventId.uuidString)")
            print(String(reflecting: error))
            #endif
            return nil
        }
    }

    private func loadMembersIfNeeded() async {
        guard let selectedHome,
              let currentUser = authenticationService.currentUser else {
            return
        }

        await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser)
    }

    private var monthTitle: String {
        CalendarViewFormatters.monthAndYear.string(from: viewModel.visibleMonth)
    }

    private var weekTitle: String {
        guard let range = viewModel.visibleWeekRange(),
              let finalDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: range.end) else {
            return ""
        }

        return CalendarViewFormatters.weekRangeTitle(start: range.start, end: finalDay)
    }

    private var visibleRangeTitle: String {
        switch viewModel.displayMode {
        case .month:
            return monthTitle
        case .week:
            return weekTitle
        }
    }

    private var previousPeriodAccessibilityLabel: String {
        viewModel.displayMode == .week ? "Previous week" : "Previous month"
    }

    private var nextPeriodAccessibilityLabel: String {
        viewModel.displayMode == .week ? "Next week" : "Next month"
    }

    private var displayModeBinding: Binding<CalendarDisplayMode> {
        Binding(
            get: { viewModel.displayMode },
            set: { mode in
                Task {
                    await viewModel.setDisplayMode(mode)
                }
            }
        )
    }

    private var selectedDateTitle: String {
        CalendarViewFormatters.selectedDate.string(from: viewModel.selectedDate)
    }

    private var selectedDayCountText: String {
        let count = viewModel.selectedDayEvents.count
        return "\(count) \(count == 1 ? "Event" : "Events")"
    }
}

private struct CalendarEditorPresentation: Identifiable {
    let id = UUID()
    let mode: EventEditorMode
    let selectedDate: Date

    var event: CalendarEvent? {
        mode.event
    }
}

private struct ChoreCalendarPresentation: Identifiable {
    let occurrence: ChoreOccurrence

    var id: UUID {
        occurrence.id
    }
}

private struct MealCalendarPresentation: Identifiable {
    let plannedMeal: PlannedMeal

    var id: UUID {
        plannedMeal.calendarEventId
    }
}

private extension EventEditorCompletion {
    var successMessage: String {
        switch self {
        case .created:
            return "Event saved."
        case .updated:
            return "Event updated."
        case .deleted:
            return "Event deleted."
        }
    }
}

private struct CalendarMonthGrid: View {
    let weekdaySymbols: [String]
    let days: [Date]
    let eventsForDay: (Date) -> [CalendarEvent]
    let categories: [CalendarCategory]
    let linkedPresentation: (CalendarEvent) -> CalendarLinkedEventPresentation?
    let isCurrentMonth: (Date) -> Bool
    let isSelected: (Date) -> Bool
    let isToday: (Date) -> Bool
    let onSelectDay: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                ForEach(days, id: \.self) { day in
                    CalendarMonthDayCell(
                        date: day,
                        events: eventsForDay(day),
                        categories: categories,
                        linkedPresentation: linkedPresentation,
                        isCurrentMonth: isCurrentMonth(day),
                        isSelected: isSelected(day),
                        isToday: isToday(day),
                        onSelectDay: { onSelectDay(day) },
                        onSelectEvent: onSelectEvent,
                        onShowMore: { onSelectDay(day) }
                    )
                }
            }

            CalendarLegendView()
        }
        .padding(18)
        .dashboardCard(cornerRadius: 26)
    }
}

private struct CalendarMonthDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    let categories: [CalendarCategory]
    let linkedPresentation: (CalendarEvent) -> CalendarLinkedEventPresentation?
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let onSelectDay: () -> Void
    let onSelectEvent: (CalendarEvent) -> Void
    let onShowMore: () -> Void

    private let visibleEventLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: onSelectDay) {
                HStack {
                    Text(dayNumber)
                        .font(.subheadline.weight(isSelected || isToday ? .bold : .semibold))
                        .foregroundStyle(dayForeground)
                        .frame(width: 30, height: 30)
                        .background(dayNumberBackground, in: Circle())

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(events.prefix(visibleEventLimit)) { event in
                    Button {
                        onSelectEvent(event)
                    } label: {
                        CalendarEventPill(
                            event: event,
                            categories: categories,
                            linkedPresentation: linkedPresentation(event),
                            style: .month
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens event details")
                }

                if events.count > visibleEventLimit {
                    Button(action: onShowMore) {
                        Text("+\(events.count - visibleEventLimit) more")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(events.count - visibleEventLimit) more events")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cellBorder, lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelectDay)
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

    private var dayNumberBackground: Color {
        if isSelected {
            return HomeyDashboardTheme.warmBrown
        }

        if isToday {
            return HomeyDashboardTheme.selectedSidebarBackground
        }

        return .clear
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

private struct CalendarWeekGrid: View {
    let days: [Date]
    let eventsForDay: (Date) -> [CalendarEvent]
    let categories: [CalendarCategory]
    let linkedPresentation: (CalendarEvent) -> CalendarLinkedEventPresentation?
    let assignedMembers: (CalendarEvent) -> [HomeMemberDisplay]
    let isSelected: (Date) -> Bool
    let isToday: (Date) -> Bool
    let onSelectDay: (Date) -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(days, id: \.self) { day in
                CalendarWeekDayColumn(
                    date: day,
                    events: eventsForDay(day),
                    categories: categories,
                    isSelected: isSelected(day),
                    isToday: isToday(day),
                    assignedMembers: assignedMembers,
                    linkedPresentation: linkedPresentation,
                    onSelect: { onSelectDay(day) },
                    onSelectEvent: onSelectEvent
                )
            }
        }
        .padding(18)
        .dashboardCard(cornerRadius: 26)
        .accessibilityLabel("Weekly calendar")
    }
}

private struct CalendarWeekDayColumn: View {
    let date: Date
    let events: [CalendarEvent]
    let categories: [CalendarCategory]
    let isSelected: Bool
    let isToday: Bool
    let assignedMembers: (CalendarEvent) -> [HomeMemberDisplay]
    let linkedPresentation: (CalendarEvent) -> CalendarLinkedEventPresentation?
    let onSelect: () -> Void
    let onSelectEvent: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(CalendarViewFormatters.weekdayName.string(from: date))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)

                        if isToday {
                            Text("Today")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                                .overlay { Capsule().stroke(HomeyDashboardTheme.warmBrown.opacity(0.35), lineWidth: 1) }
                        }
                    }

                    Text(dayNumber)
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
            .accessibilityLabel(dayAccessibilityLabel)

            VStack(alignment: .leading, spacing: 7) {
                if events.isEmpty {
                    Text("No Events")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .accessibilityLabel("No Events")
                } else {
                    ForEach(events) { event in
                        Button {
                            onSelectEvent(event)
                        } label: {
                            CalendarEventPill(
                                event: event,
                                categories: categories,
                                linkedPresentation: linkedPresentation(event),
                                style: .week,
                                assignedMembers: assignedMembers(event)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens event details")
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
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var dayNumber: String {
        String(Calendar.autoupdatingCurrent.component(.day, from: date))
    }

    private var dayAccessibilityLabel: String {
        let dateText = CalendarViewFormatters.selectedDate.string(from: date)
        let countText = "\(events.count) \(events.count == 1 ? "event" : "events")"
        let selectedText = isSelected ? ", selected" : ""
        return "\(dateText), \(countText)\(selectedText)"
    }
}

private struct CalendarEventPill: View {
    enum Style {
        case month
        case week
    }

    let event: CalendarEvent
    let categories: [CalendarCategory]
    let linkedPresentation: CalendarLinkedEventPresentation?
    let style: Style
    var assignedMembers: [HomeMemberDisplay] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accentColor)
                    .frame(width: style == .month ? 4 : 5, height: style == .month ? 18 : 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(style == .month ? .caption2.weight(.bold) : .caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(style == .month ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    if style == .week {
                        Text(subtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            if !assignedMembers.isEmpty {
                HStack(spacing: -6) {
                    ForEach(assignedMembers.prefix(3)) { member in
                        AvatarView(
                            imageURL: member.avatarURL,
                            initials: member.initials,
                            size: 22,
                            accentColor: HomeyDashboardTheme.warmBrown,
                            borderWidth: 1.5,
                            showsShadow: false,
                            accessibilityLabel: "Assigned to \(member.displayName)"
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(style == .month ? 5 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: style == .month ? 7 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style == .month ? 7 : 14, style: .continuous)
                .stroke(accentColor.opacity(0.42), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private var title: String {
        guard let linkedPresentation else {
            return event.title
        }

        switch linkedPresentation.content {
        case .meal(let plannedMeal):
            return "\(plannedMeal.mealType.displayName) · \(plannedMeal.meal.name)"
        case .chore(let chore):
            return chore.title
        }
    }

    private var subtitle: String {
        guard let linkedPresentation else {
            return timeText
        }

        switch linkedPresentation.content {
        case .meal:
            return timeText
        case .chore(let chore):
            return "\(timeText) · \(chore.statusStyle.title)"
        }
    }

    private var accentColor: Color {
        CalendarLinkedEventColorResolver.color(for: event, presentation: linkedPresentation, categories: categories)
    }

    private var backgroundOpacity: Double {
        switch linkedPresentation?.content {
        case .meal:
            return 0.14
        case .chore:
            return 0.12
        case nil:
            return 0.10
        }
    }

    private var timeText: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(CalendarViewFormatters.eventTime.string(from: event.occurrenceStartsAt)) - \(CalendarViewFormatters.eventTime.string(from: event.occurrenceEndsAt))"
    }
}

private struct CalendarDayDetailsView: View {
    let title: String
    let countText: String
    let events: [CalendarEvent]
    let categories: [CalendarCategory]
    let linkedPresentation: (CalendarEvent) -> CalendarLinkedEventPresentation?
    let assignedMembers: (CalendarEvent) -> [HomeMemberDisplay]
    let onSelectEvent: (CalendarEvent) -> Void
    let onAddEvent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text(countText)
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer()
            }

            if events.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button {
                            onSelectEvent(event)
                        } label: {
                            if let presentation = linkedPresentation(event) {
                                CalendarLinkedAgendaEventRow(presentation: presentation, categories: categories)
                            } else {
                                AgendaEventRow(event: event, categories: categories, assignedMembers: assignedMembers(event))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens event details")

                        if index < events.count - 1 {
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

    private var emptyState: some View {
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
                onAddEvent()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Event")
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct CalendarLegendView: View {
    var body: some View {
        HStack(spacing: 14) {
            legendItem(title: "Meals", color: HomeyDashboardTheme.sageAccent)
            legendItem(title: "Chores", color: HomeyDashboardTheme.softRed)
            legendItem(title: "Events", color: HomeyDashboardTheme.lavenderAccent)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calendar legend. Meals, chores, events.")
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }
}

private struct AgendaEventRow: View {
    let event: CalendarEvent
    let categories: [CalendarCategory]
    let assignedMembers: [HomeMemberDisplay]

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(CalendarEventColorResolver.color(for: event, categories: categories))
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

        return "\(CalendarViewFormatters.eventTime.string(from: event.occurrenceStartsAt)) - \(CalendarViewFormatters.eventTime.string(from: event.occurrenceEndsAt))"
    }
}

private struct CalendarStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(HomeyDashboardTheme.sageAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HomeyDashboardTheme.sageAccent.opacity(0.20), lineWidth: 1)
        }
        .accessibilityLabel(message)
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

    static let weekdayName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static func weekRangeTitle(start: Date, end: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(start, equalTo: end, toGranularity: .month),
           calendar.isDate(start, equalTo: end, toGranularity: .year) {
            return "\(monthName.string(from: start)) \(dayNumber.string(from: start))-\(dayNumber.string(from: end)), \(year.string(from: start))"
        }

        if calendar.isDate(start, equalTo: end, toGranularity: .year) {
            return "\(monthAndDay.string(from: start)) - \(monthAndDay.string(from: end)), \(year.string(from: start))"
        }

        return "\(monthDayAndYear.string(from: start)) - \(monthDayAndYear.string(from: end))"
    }

    static func compactWeekRangeTitle(start: Date, end: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(shortMonthName.string(from: start)) \(dayNumber.string(from: start))-\(dayNumber.string(from: end))"
        }

        if calendar.component(.year, from: start) == calendar.component(.year, from: end) {
            return "\(monthAndDay.string(from: start)) - \(monthAndDay.string(from: end))"
        }

        return "\(monthDayAndYear.string(from: start)) - \(monthDayAndYear.string(from: end))"
    }

    private static let monthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    private static let shortMonthName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let monthAndDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthDayAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

extension Color {
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
