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
    @State private var pendingWeekScrollBehavior: CalendarWeekScrollBehavior = .selectedDate

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
                    header

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

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(visibleRangeTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                Picker("Calendar View", selection: displayModeBinding) {
                    ForEach(CalendarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 176)
                .accessibilityLabel("Calendar view")

                if viewModel.displayMode == .month {
                    iconButton(systemImage: "chevron.left", label: previousPeriodAccessibilityLabel) {
                        Task { await viewModel.moveToPreviousPeriod() }
                    }

                    iconButton(systemImage: "chevron.right", label: nextPeriodAccessibilityLabel) {
                        Task { await viewModel.moveToNextPeriod() }
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
                    .accessibilityLabel("Go to today")
                }

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
        }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            calendarFilterButtons

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 22) {
                    primaryCalendarCard
                        .frame(minWidth: viewModel.displayMode == .week ? 760 : 620)

                    agendaCard
                        .frame(width: 360)
                }

                VStack(alignment: .leading, spacing: 22) {
                    primaryCalendarCard
                    agendaCard
                }
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
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Month View")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Spacer()

                if viewModel.filteredEventCount > 0 {
                    eventCountBadge(count: viewModel.filteredEventCount, accessibilitySuffix: "this month")
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
                        categories: viewModel.categories,
                        linkedPresentation: viewModel.linkedPresentation(for:),
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

    private var weekGridCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            calendarWeekHeader

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(viewModel.weekDays(), id: \.self) { day in
                            WeekDayColumn(
                                date: day,
                                events: viewModel.events(on: day),
                                categories: viewModel.categories,
                                isSelected: viewModel.isSelected(day),
                                isToday: viewModel.isToday(day),
                                assignedMembers: assignedMembers(for:),
                                linkedPresentation: viewModel.linkedPresentation(for:),
                                onSelect: {
                                    viewModel.selectDate(day)
                                },
                                onSelectEvent: { event in
                                    presentEditEditor(for: event)
                                }
                            )
                            .frame(width: 210, alignment: .top)
                            .id(day)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollWeek(proxy: proxy, animated: false)
                }
                .onChange(of: viewModel.visibleWeekAnchor) { _, _ in
                    scrollWeek(proxy: proxy, animated: true)
                }
                .onChange(of: viewModel.displayMode) { _, mode in
                    if mode == .week {
                        pendingWeekScrollBehavior = .selectedDate
                        scrollWeek(proxy: proxy, animated: false)
                    }
                }
                .accessibilityLabel("Weekly calendar")
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
    }

    private var calendarWeekHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                pendingWeekScrollBehavior = .startOfWeek
                Task { await viewModel.moveToPreviousWeek() }
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
                Text(weekCardTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            Button {
                pendingWeekScrollBehavior = .startOfWeek
                Task { await viewModel.moveToNextWeek() }
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

            let count = viewModel.visibleWeekEvents().count
            Text("\(count) \(count == 1 ? "Event" : "Events")")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Button("Today") {
                pendingWeekScrollBehavior = .selectedDate
                Task { await viewModel.moveToToday() }
            }
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
                        Button {
                            presentEditEditor(for: event)
                        } label: {
                            if let presentation = viewModel.linkedPresentation(for: event) {
                                CalendarLinkedAgendaEventRow(presentation: presentation, categories: viewModel.categories)
                            } else {
                                AgendaEventRow(event: event, categories: viewModel.categories, assignedMembers: assignedMembers(for: event))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens event details")

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
                presentCreateEditor()
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

    private func eventCountBadge(count: Int, accessibilitySuffix: String) -> some View {
        Text("\(count) \(count == 1 ? "Event" : "Events")")
            .font(.caption.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
            .accessibilityLabel("\(count) \(count == 1 ? "event" : "events") \(accessibilitySuffix)")
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

    private var weekCardTitle: String {
        guard let range = viewModel.visibleWeekRange(),
              let finalDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: range.end) else {
            return "This Week"
        }

        return CalendarViewFormatters.compactWeekRangeTitle(start: range.start, end: finalDay)
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

    private func scrollWeek(proxy: ScrollViewProxy, animated: Bool) {
        guard viewModel.displayMode == .week else {
            return
        }

        let weekDays = viewModel.weekDays()
        guard let fallbackDay = weekDays.first else {
            return
        }

        let requestedDay: Date
        switch pendingWeekScrollBehavior {
        case .startOfWeek:
            requestedDay = fallbackDay
        case .selectedDate:
            requestedDay = weekDays.first { viewModel.isSelected($0) } ?? weekDays.first { viewModel.isToday($0) } ?? fallbackDay
        }

        let action = {
            proxy.scrollTo(requestedDay, anchor: .leading)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22), action)
        } else {
            action()
        }
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

private struct CalendarDayCell: View {
    let date: Date
    let events: [CalendarEvent]
    let categories: [CalendarCategory]
    let linkedPresentation: (CalendarEvent) -> CalendarLinkedEventPresentation?
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
                            .fill(CalendarLinkedEventColorResolver.color(for: event, presentation: linkedPresentation(event), categories: categories))
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

private struct WeekDayColumn: View {
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
                            WeekEventChip(
                                event: event,
                                categories: categories,
                                assignedMembers: assignedMembers(event),
                                linkedPresentation: linkedPresentation(event)
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

    private var dayForeground: Color {
        if isSelected {
            return .white
        }

        if isToday {
            return HomeyDashboardTheme.warmBrown
        }

        return HomeyDashboardTheme.primaryText
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

    private var columnBackground: Color {
        isSelected ? HomeyDashboardTheme.selectedSidebarBackground.opacity(0.9) : HomeyDashboardTheme.cardBackground.opacity(0.70)
    }

    private var columnBorder: Color {
        isSelected ? HomeyDashboardTheme.warmBrown.opacity(0.45) : HomeyDashboardTheme.softBorder
    }

    private var dayAccessibilityLabel: String {
        let dateText = CalendarViewFormatters.selectedDate.string(from: date)
        let countText = "\(events.count) \(events.count == 1 ? "event" : "events")"
        let selectedText = isSelected ? ", selected" : ""
        return "\(dateText), \(countText)\(selectedText)"
    }
}

private struct WeekEventChip: View {
    let event: CalendarEvent
    let categories: [CalendarCategory]
    let assignedMembers: [HomeMemberDisplay]
    let linkedPresentation: CalendarLinkedEventPresentation?

    var body: some View {
        if let linkedPresentation {
            CalendarLinkedEventChip(presentation: linkedPresentation, categories: categories)
        } else {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CalendarEventColorResolver.color(for: event, categories: categories))
                    .frame(width: 5, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(timeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.appBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(timeText)")
        }
    }

    private var timeText: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(CalendarViewFormatters.eventTime.string(from: event.occurrenceStartsAt)) - \(CalendarViewFormatters.eventTime.string(from: event.occurrenceEndsAt))"
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

private enum CalendarWeekScrollBehavior {
    case startOfWeek
    case selectedDate
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
