import SwiftUI

struct CalendarRootView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var model = PhoneCalendarViewModel()
    @State private var showingCreate = false
    @State private var selectedEvent: PhoneCalendarEvent?

    private var scope: String {
        "\(appSession.activeHome?.id.uuidString ?? "no-home")-\(appSession.activeHome?.weekStartsOn ?? 1)-\(appSession.activeTimezone.identifier)"
    }

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    monthCard
                    selectedDaySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .refreshable { await reload(force: true) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: scope) { await reload(force: true) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyCalendarEventsDidChange"))) { notification in
            guard notification.object as AnyObject? !== model else { return }
            Task { await reload(force: true) }
        }
        .sheet(isPresented: $showingCreate) {
            if let home = appSession.activeHome {
                PhoneCalendarEditor(
                    mode: .create(model.selectedDate),
                    categories: model.userCategories,
                    calendar: model.calendar,
                    timezone: model.timezone,
                    isSaving: model.isSaving,
                    externalError: model.errorMessage
                ) { draft in
                    await model.create(draft, home: home)
                }
            }
        }
        .navigationDestination(item: $selectedEvent) { event in
            if let home = appSession.activeHome {
                PhoneCalendarEventDetail(event: event, home: home, model: model)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Calendar")
                .font(.title.bold())
                .foregroundStyle(HomeyColors.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Section("Add") {
                    Button("Event", systemImage: "calendar.badge.plus") {
                        showingCreate = true
                    }
                }
                Section("Sync") {
                    Button("Coming Soon", systemImage: "arrow.triangle.2.circlepath") {}
                        .disabled(true)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 44, height: 44)
                    .background(HomeyColors.field, in: Circle())
            }
            .accessibilityLabel("Calendar actions")
        }
    }

    private var monthCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button { Task { await moveMonth(-1) } } label: {
                    Image(systemName: "chevron.left").frame(width: 38, height: 38)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(model.monthTitle).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
                Spacer()
                Button { Task { await moveMonth(1) } } label: {
                    Image(systemName: "chevron.right").frame(width: 38, height: 38)
                }
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(HomeyColors.primary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 7) {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyColors.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                ForEach(model.visibleDates(), id: \.self) { date in
                    calendarDay(date)
                }
            }

            Button("Today") { Task { await moveToToday() } }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(HomeyColors.primary)
        }
        .homeyCard()
    }

    private func calendarDay(_ date: Date) -> some View {
        let isSelected = model.calendar.isDate(date, inSameDayAs: model.selectedDate)
        let isToday = model.calendar.isDateInToday(date)
        let isCurrentMonth = model.calendar.isDate(date, equalTo: model.visibleMonth, toGranularity: .month)
        let colors = model.indicatorColors(on: date)
        return Button {
            guard let home = appSession.activeHome else { return }
            Task { await model.select(date, home: home) }
        } label: {
            VStack(spacing: 4) {
                Text("\(model.calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : isCurrentMonth ? HomeyColors.text : HomeyColors.secondaryText.opacity(0.45))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? HomeyColors.primary : Color.clear, in: Circle())
                    .overlay { if isToday && !isSelected { Circle().stroke(HomeyColors.primary, lineWidth: 1.5) } }
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in
                        Circle().fill(calendarColor(hex)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(date, eventCount: model.events(on: date).count))
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.selectedDateTitle).font(HomeyTypography.headline).foregroundStyle(HomeyColors.text)
                Spacer()
                Button { showingCreate = true } label: { Label("Add Event", systemImage: "plus") }
                    .font(.caption.weight(.semibold))
            }
            if model.isLoading && model.events.isEmpty {
                ProgressView("Loading events…").frame(maxWidth: .infinity).homeyCard()
            } else if let error = model.errorMessage, model.events.isEmpty {
                VStack(spacing: 12) {
                    HomeyErrorView(message: error)
                    Button("Try Again") { Task { await reload(force: true) } }.buttonStyle(HomeyButtonStyle())
                }.homeyCard()
            } else if selectedEvents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark").font(.title2).foregroundStyle(HomeyColors.success)
                    Text("No events scheduled").font(.headline).foregroundStyle(HomeyColors.text)
                    Button("Add Event") { showingCreate = true }.buttonStyle(.borderedProminent).tint(HomeyColors.primary)
                }
                .frame(maxWidth: .infinity)
                .homeyCard()
            } else {
                if !allDayEvents.isEmpty { eventGroup("ALL DAY", events: allDayEvents) }
                if !timedEvents.isEmpty { eventGroup("EVENTS", events: timedEvents) }
                if let error = model.errorMessage {
                    Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(HomeyColors.secondaryText)
                }
            }
        }
    }

    private func eventGroup(_ title: String, events: [PhoneCalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    Button { selectedEvent = event } label: {
                        PhoneCalendarEventRow(event: event, timezone: model.timezone)
                            .padding(.vertical, 12)
                    }.buttonStyle(.plain)
                    if index < events.count - 1 { Divider() }
                }
            }.homeyCard()
        }
    }

    private var selectedEvents: [PhoneCalendarEvent] { model.events(on: model.selectedDate) }
    private var allDayEvents: [PhoneCalendarEvent] { selectedEvents.filter(\.isAllDay) }
    private var timedEvents: [PhoneCalendarEvent] { selectedEvents.filter { !$0.isAllDay } }

    private func reload(force: Bool) async {
        guard let home = appSession.activeHome else { return }
        await model.configure(home: home, force: force)
    }
    private func moveMonth(_ offset: Int) async { guard let home = appSession.activeHome else { return }; await model.moveMonth(offset, home: home) }
    private func moveToToday() async { guard let home = appSession.activeHome else { return }; await model.moveToToday(home: home) }

    private func dayAccessibilityLabel(_ date: Date, eventCount: Int) -> String {
        let formatter = DateFormatter(); formatter.calendar = model.calendar; formatter.timeZone = model.timezone; formatter.dateStyle = .full
        return "\(formatter.string(from: date)), \(eventCount) event\(eventCount == 1 ? "" : "s")"
    }
}

private struct PhoneCalendarEventRow: View {
    let event: PhoneCalendarEvent
    let timezone: TimeZone
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(calendarColor(event.categoryColorHex)).frame(width: 4, height: 42)
            Text(timeText).font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText).frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(event.title).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                    if event.isRecurring { Image(systemName: "repeat").font(.caption2).foregroundStyle(HomeyColors.secondaryText) }
                }
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(HomeyColors.secondaryText).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
    }
    private var timeText: String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter(); formatter.timeZone = timezone; formatter.dateFormat = "h:mm a"; return formatter.string(from: event.occurrenceStartsAt)
    }
}

private enum PhoneCalendarEditorMode {
    case create(Date)
    case edit(PhoneCalendarEvent, PhoneCalendarEditScope)
}

private enum PhoneRecurrenceEndMode: String, CaseIterable, Identifiable { case never = "Never", date = "On Date", count = "After Count"; var id: Self { self } }

private struct PhoneCalendarEditor: View {
    @Environment(\.dismiss) private var dismiss
    let mode: PhoneCalendarEditorMode
    let categories: [PhoneCalendarCategory]
    let calendar: Calendar
    let timezone: TimeZone
    let isSaving: Bool
    let externalError: String?
    let onSave: (PhoneCalendarDraft) async -> Bool
    @State private var draft: PhoneCalendarDraft
    @State private var localError: String?
    @State private var endMode: PhoneRecurrenceEndMode

    init(mode: PhoneCalendarEditorMode, categories: [PhoneCalendarCategory], calendar: Calendar, timezone: TimeZone, isSaving: Bool, externalError: String?, onSave: @escaping (PhoneCalendarDraft) async -> Bool) {
        self.mode = mode; self.categories = categories; self.calendar = calendar; self.timezone = timezone
        self.isSaving = isSaving; self.externalError = externalError; self.onSave = onSave
        let initial: PhoneCalendarDraft
        switch mode {
        case .create(let date): initial = PhoneCalendarDraft(date: date, calendar: calendar)
        case .edit(let event, let scope): initial = PhoneCalendarDraft(event: event, calendar: calendar, occurrenceOnly: scope == .occurrence)
        }
        _draft = State(initialValue: initial)
        _endMode = State(initialValue: initial.recurrence.endDate != nil ? .date : initial.recurrence.count != nil ? .count : .never)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $draft.title)
                    Toggle("All Day", isOn: $draft.isAllDay)
                }
                Section("Date and Time") {
                    DatePicker("Start", selection: $draft.startsAt, displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("End", selection: $draft.endsAt, in: draft.startsAt..., displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                }
                Section("Category") {
                    Picker("Category", selection: $draft.categoryID) {
                        Text("No Category").tag(Optional<UUID>.none)
                        ForEach(categories) { category in Text(category.name).tag(Optional(category.id)) }
                    }
                }
                if showsRecurrence {
                    Section("Recurrence") {
                        Picker("Repeat", selection: $draft.recurrence.frequency) {
                            Text("Does Not Repeat").tag(Optional<PhoneCalendarRecurrenceFrequency>.none)
                            ForEach(PhoneCalendarRecurrenceFrequency.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                        if draft.recurrence.frequency != nil {
                            Stepper("Every \(draft.recurrence.interval) \(intervalUnit)", value: $draft.recurrence.interval, in: 1...99)
                            if draft.recurrence.frequency == .weekly {
                                weeklyDayPicker
                            }
                            Picker("Ends", selection: $endMode) { ForEach(PhoneRecurrenceEndMode.allCases) { Text($0.rawValue).tag($0) } }
                            if endMode == .date {
                                DatePicker("End Date", selection: recurrenceEndDate, in: calendar.startOfDay(for: draft.startsAt)..., displayedComponents: .date)
                            } else if endMode == .count {
                                Stepper("\(draft.recurrence.count ?? 10) occurrences", value: recurrenceCount, in: 1...999)
                            }
                        }
                    }
                }
                Section("Details") {
                    TextField("Location (optional)", text: $draft.location)
                    TextField("Notes (optional)", text: $draft.notes, axis: .vertical).lineLimit(3...6)
                }
                if let error = localError ?? externalError { Section { Text(error).foregroundStyle(HomeyColors.danger) } }
            }
            .scrollContentBackground(.hidden)
            .background(HomeyColors.background)
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(isSaving) }
            }
            .onChange(of: endMode) { _, value in
                if value != .date { draft.recurrence.endDate = nil }
                if value != .count { draft.recurrence.count = nil }
            }
            .onChange(of: draft.isAllDay) { _, allDay in
                if allDay { draft.startsAt = calendar.startOfDay(for: draft.startsAt); draft.endsAt = max(calendar.startOfDay(for: draft.endsAt), draft.startsAt) }
            }
            .onChange(of: draft.recurrence.frequency) { _, frequency in
                if frequency == .weekly, draft.recurrence.daysOfWeek?.isEmpty != false {
                    draft.recurrence.daysOfWeek = [isoWeekday(draft.startsAt)]
                } else if frequency != .weekly {
                    draft.recurrence.daysOfWeek = nil
                }
            }
        }
        .presentationDetents([.large])
    }

    private var editorTitle: String { if case .create = mode { return "New Event" }; return "Edit Event" }
    private var showsRecurrence: Bool { if case .edit(_, .occurrence) = mode { return false }; return true }
    private var intervalUnit: String { (draft.recurrence.frequency?.rawValue ?? "day") + (draft.recurrence.interval == 1 ? "" : "s") }
    private var recurrenceEndDate: Binding<Date> { Binding(get: { draft.recurrence.endDate ?? calendar.startOfDay(for: draft.startsAt) }, set: { draft.recurrence.endDate = $0; draft.recurrence.count = nil }) }
    private var recurrenceCount: Binding<Int> { Binding(get: { draft.recurrence.count ?? 10 }, set: { draft.recurrence.count = $0; draft.recurrence.endDate = nil }) }

    private var weeklyDayPicker: some View {
        HStack(spacing: 5) {
            ForEach(1...7, id: \.self) { day in
                let selected = draft.recurrence.daysOfWeek?.contains(day) == true
                Button {
                    var days = Set(draft.recurrence.daysOfWeek ?? [])
                    if selected {
                        if days.count > 1 { days.remove(day) }
                    } else {
                        days.insert(day)
                    }
                    draft.recurrence.daysOfWeek = days.sorted()
                } label: {
                    Text(["M", "T", "W", "T", "F", "S", "S"][day - 1])
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(selected ? Color.white : HomeyColors.primary)
                        .background(selected ? HomeyColors.primary : HomeyColors.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekdayName(day))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func save() async {
        localError = nil
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { localError = "Enter an event title."; return }
        if draft.endsAt < draft.startsAt { localError = "The event must end after it starts."; return }
        if draft.recurrence.frequency == .weekly, draft.recurrence.daysOfWeek?.isEmpty != false {
            draft.recurrence.daysOfWeek = [isoWeekday(draft.startsAt)]
        }
        if endMode == .never { draft.recurrence.endDate = nil; draft.recurrence.count = nil }
        if await onSave(draft) { dismiss() }
    }
    private func isoWeekday(_ date: Date) -> Int { let value = calendar.component(.weekday, from: date); return value == 1 ? 7 : value - 1 }
    private func weekdayName(_ isoDay: Int) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return names[max(0, min(names.count - 1, isoDay - 1))]
    }
}

private struct PhoneCalendarEventDetail: View {
    @Environment(\.dismiss) private var dismiss
    @State var event: PhoneCalendarEvent
    let home: HomeSummary
    @ObservedObject var model: PhoneCalendarViewModel
    @State private var editScope: PhoneCalendarEditScope?
    @State private var showingEditChoice = false
    @State private var showingDeleteChoice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(calendarColor(event.categoryColorHex))
                            .frame(width: 12, height: 12)
                        Text(event.categoryName ?? "Event")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HomeyColors.secondaryText)
                        Spacer()
                        if event.isAllDay {
                            Text("All Day")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HomeyColors.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(HomeyColors.primary.opacity(0.1), in: Capsule())
                        }
                    }
                    Text(event.title).font(HomeyTypography.hero).foregroundStyle(HomeyColors.text)

                    Divider()
                    metadataRow(label: "Starts", value: startDescription, symbol: "calendar")
                    Divider()
                    metadataRow(label: "Ends", value: endDescription, symbol: "calendar")

                    if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                        Divider()
                        metadataRow(label: "Location", value: location, symbol: "mappin.and.ellipse")
                    }
                    if event.isRecurring {
                        Divider()
                        metadataRow(label: "Repeats", value: recurrenceDescription, symbol: "repeat")
                    }
                    if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        Divider()
                        metadataRow(label: "Notes", value: notes, symbol: "note.text")
                    }
                }
                .homeyCard()
                Button { event.isRecurring ? (showingEditChoice = true) : (editScope = .series) } label: { Label("Edit Event", systemImage: "pencil").frame(maxWidth: .infinity) }.buttonStyle(HomeyButtonStyle())
                Button(role: .destructive) { showingDeleteChoice = true } label: { Label("Delete Event", systemImage: "trash").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }.padding(18)
        }
        .background(HomeyColors.background)
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: editScopeBinding) { wrapper in
            PhoneCalendarEditor(
                mode: .edit(event, wrapper.scope), categories: model.userCategories, calendar: model.calendar,
                timezone: model.timezone, isSaving: model.isSaving, externalError: model.errorMessage
            ) { draft in
                let saved = await model.update(event, draft: draft, scope: wrapper.scope, home: home)
                if saved, let refreshed = model.refreshedEvent(matching: event) { event = refreshed }
                return saved
            }
        }
        .confirmationDialog("Edit Recurring Event", isPresented: $showingEditChoice, titleVisibility: .visible) {
            Button("This Event Only") { editScope = .occurrence }
            Button("Entire Series") { editScope = .series }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(event.isRecurring ? "Delete Recurring Event" : "Delete Event?", isPresented: $showingDeleteChoice, titleVisibility: .visible) {
            if event.isRecurring {
                Button("This Event Only", role: .destructive) { Task { await delete(.occurrence) } }
                Button("Entire Series", role: .destructive) { Task { await delete(.series) } }
            } else {
                Button("Delete Event", role: .destructive) { Task { await delete(.series) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(event.isRecurring ? "Choose whether to remove this occurrence or the entire series." : "This event will be removed from your Home calendar.") }
    }

    private func metadataRow(label: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeyColors.primary)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomeyColors.secondaryText)
                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(HomeyColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startDescription: String {
        dateFormatter(includeTime: !event.isAllDay).string(from: event.occurrenceStartsAt)
    }

    private var endDescription: String {
        let displayEnd: Date
        if event.isAllDay {
            displayEnd = model.calendar.date(byAdding: .day, value: -1, to: event.occurrenceEndsAt) ?? event.occurrenceEndsAt
        } else {
            displayEnd = event.occurrenceEndsAt
        }
        return dateFormatter(includeTime: !event.isAllDay).string(from: displayEnd)
    }

    private func dateFormatter(includeTime: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = model.calendar
        formatter.timeZone = model.timezone
        formatter.dateStyle = .medium
        formatter.timeStyle = includeTime ? .short : .none
        return formatter
    }

    private var recurrenceDescription: String {
        guard let frequency = event.recurrenceFrequency else { return "Recurring" }
        guard event.recurrenceInterval > 1 else { return frequency.title }
        let unit = frequency.rawValue + (event.recurrenceInterval == 1 ? "" : "s")
        return "Every \(event.recurrenceInterval) \(unit)"
    }
    private func delete(_ scope: PhoneCalendarEditScope) async { if await model.delete(event, scope: scope, home: home) { dismiss() } }
    private var editScopeBinding: Binding<PhoneEditScopeWrapper?> {
        Binding(get: { editScope.map(PhoneEditScopeWrapper.init) }, set: { editScope = $0?.scope })
    }
}

private struct PhoneEditScopeWrapper: Identifiable { let scope: PhoneCalendarEditScope; var id: String { scope == .occurrence ? "occurrence" : "series" } }

private func calendarColor(_ hex: String?) -> Color {
    guard let hex else { return HomeyColors.primary }
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return HomeyColors.primary }
    return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}
