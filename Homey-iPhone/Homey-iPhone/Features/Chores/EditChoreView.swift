import SwiftUI
import Supabase

struct EditChoreView: View {
    let home: HomeSummary
    let initial: PhoneChoreDetail
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSession
    @State private var draft: PhoneChoreDetail
    @State private var selectedAssignee: UUID?
    @State private var savePhase: PhoneChoreSavePhase?
    @State private var error: String?
    @State private var partialFailure: ChoreRecurringEditPartialFailure?
    private let service = PhoneChoreEditService()
    private let weekdays = Array(0...6)

    init(home: HomeSummary, initial: PhoneChoreDetail, onSaved: @escaping () -> Void) {
        self.home = home; self.initial = initial; self.onSaved = onSaved
        _draft = State(initialValue: initial)
        _selectedAssignee = State(initialValue: initial.canSafelyEdit ? initial.assigneeIDs.first : nil)
    }

    private var saving: Bool { savePhase != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edit Chore").font(HomeyTypography.hero)
                        Text("Changes apply to this chore and its future occurrences.")
                            .font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    }
                    if !initial.canSafelyEdit {
                        HomeyErrorView(message: initial.legacyExplanation)
                    } else {
                        field("Chore Title *") { TextField("Chore title", text: $draft.title) }
                        field("Description") { TextField("Description", text: $draft.description, axis: .vertical).lineLimit(2...5) }
                        field("Instructions") { TextField("Instructions", text: $draft.instructions, axis: .vertical).lineLimit(2...6) }
                        field("Room") {
                            Picker("Room", selection: $draft.roomID) {
                                ForEach(draft.rooms) { Text($0.displayName).tag(Optional($0.id)) }
                            }.labelsHidden().pickerStyle(.menu)
                        }
                        field("Assigned Person *") {
                            ChoreSingleAssigneePicker(options: draft.members, selection: $selectedAssignee)
                        }
                        field("Points") { Stepper("\(draft.pointsValue) points", value: $draft.pointsValue, in: 0...1000, step: 1) }
                        Toggle("Requires Approval", isOn: $draft.requiresApproval)
                        Toggle("Requires Photo", isOn: $draft.requiresPhoto)
                        Toggle("All Day", isOn: $draft.isAllDay)
                        if !draft.isAllDay { dueTimePicker }
                        recurrenceSection
                        field("Start Date") { DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date).labelsHidden() }
                        endSection
                        field("Completion") { Text(draft.completionMode.displayName).foregroundStyle(HomeyColors.secondaryText) }
                        field("Duration") { Stepper("\(draft.durationMinutes) minutes", value: $draft.durationMinutes, in: 5...1440, step: 5) }
                    }
                    if let error { HomeyErrorView(message: error) }
                }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .disabled(saving || !initial.canSafelyEdit)
            }
            .background(HomeyColors.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered).disabled(saving)
                    Button { Task { await save() } } label: {
                        if saving { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Save Changes").frame(maxWidth: .infinity) }
                    }.buttonStyle(HomeyButtonStyle()).disabled(!valid || saving || !initial.canSafelyEdit)
                }.padding().background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Chore", systemImage: "chevron.left").font(.headline) }.disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
            .onChange(of: appSession.activeHome?.id) { _, id in if id != home.id { dismiss() } }
            .overlay {
                if let savePhase {
                    ZStack {
                        Color.black.opacity(0.32).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large).tint(HomeyColors.primary)
                            Text(savePhase.message).font(HomeyTypography.headline)
                                .foregroundStyle(HomeyColors.text)
                        }
                        .padding(.horizontal, 30).padding(.vertical, 24)
                        .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 18)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(savePhase.message)
                }
            }
        }
    }

    private var valid: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        draft.roomID != nil && selectedAssignee != nil &&
        (draft.frequency != .weekly || !draft.weekdays.isEmpty) &&
        (draft.endType != .onDate || draft.endsOn != nil) &&
        (draft.endType != .afterCount || (draft.occurrenceCount ?? 0) > 0)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.subheadline.weight(.semibold)); content() }
            .padding(16).homeyCard()
    }

    private var dueTimePicker: some View {
        field("Due Time") {
            DatePicker("Due Time", selection: Binding(get: { service.time(from: draft.dueTime) }, set: { draft.dueTime = service.timeString($0) }), displayedComponents: .hourAndMinute).labelsHidden()
        }
    }

    private var recurrenceSection: some View {
        field("Recurrence") {
            Picker("Frequency", selection: $draft.frequency) { ForEach(PhoneEditFrequency.allCases) { Text($0.displayName).tag($0) } }
            if draft.frequency != .none { Stepper("Every \(draft.intervalValue)", value: $draft.intervalValue, in: 1...52) }
            if draft.frequency == .weekly {
                HStack { ForEach(weekdays, id: \.self) { day in
                    Button(Calendar.current.veryShortWeekdaySymbols[day]) {
                        if draft.weekdays.contains(day) { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                    }.buttonStyle(.bordered).tint(draft.weekdays.contains(day) ? HomeyColors.primary : .gray)
                } }
            }
            if draft.frequency == .monthly || draft.frequency == .yearly {
                Stepper("Day \(draft.dayOfMonth ?? 1)", value: Binding(get: { draft.dayOfMonth ?? 1 }, set: { draft.dayOfMonth = $0 }), in: 1...31)
            }
            if draft.frequency == .yearly {
                Stepper("Month \(draft.monthOfYear ?? 1)", value: Binding(get: { draft.monthOfYear ?? 1 }, set: { draft.monthOfYear = $0 }), in: 1...12)
            }
        }
    }

    private var endSection: some View {
        field("Chore Ends") {
            Picker("Chore Ends", selection: $draft.endType) { ForEach(PhoneEditEndType.allCases) { Text($0.displayName).tag($0) } }.pickerStyle(.segmented)
            if draft.endType == .onDate { DatePicker("End Date", selection: Binding(get: { draft.endsOn ?? draft.startDate }, set: { draft.endsOn = $0 }), displayedComponents: .date) }
            if draft.endType == .afterCount { Stepper("\(draft.occurrenceCount ?? 1) occurrences", value: Binding(get: { draft.occurrenceCount ?? 1 }, set: { draft.occurrenceCount = $0 }), in: 1...999) }
        }
    }

    private func save() async {
        guard valid, let assignee = selectedAssignee, appSession.activeHome?.id == home.id else { return }
        guard savePhase == nil else { return }
        savePhase = .saving; error = nil
        draft.assigneeIDs = [assignee]
        do {
            try await service.save(draft: draft, original: initial, partialFailure: partialFailure) { phase in
                savePhase = phase
            }
            savePhase = .refreshing
            onSaved()
        } catch let failure as ChoreRecurringEditPartialFailure {
            #if DEBUG
            print("[Homey] CHORE EDIT: \(failure.stage.rawValue) failed template_id=\(failure.templateId.uuidString) error=\(failure.underlyingDescription)")
            #endif
            partialFailure = failure
            error = failure.localizedDescription
        } catch {
            #if DEBUG
            print("[Homey] CHORE EDIT: save failed template_id=\(draft.id.uuidString) occurrence_id=\(draft.occurrenceID.uuidString) error=\(String(reflecting: error))")
            #endif
            self.error = error.localizedDescription
        }
        savePhase = nil
    }
}

enum PhoneChoreSavePhase {
    case saving, futureChores, calendar, refreshing
    var message: String {
        switch self {
        case .saving: "Saving Chore..."
        case .futureChores: "Updating future chores..."
        case .calendar: "Updating calendar..."
        case .refreshing: "Refreshing chores..."
        }
    }
}

@MainActor
final class PhoneChoreEditService {
    private let client = SupabaseManager.shared.client
    private let coordinator = ChoreRecurringEditCoordinator()

    func time(from value: String?) -> Date {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return value.flatMap(f.date) ?? Date()
    }
    func timeString(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: date) }

    func save(
        draft: PhoneChoreDetail,
        original: PhoneChoreDetail,
        partialFailure: ChoreRecurringEditPartialFailure?,
        progress: @escaping (PhoneChoreSavePhase) -> Void
    ) async throws {
        guard draft.homeID == original.homeID, draft.canSafelyEdit, draft.assigneeIDs.count == 1 else {
            throw ChoreCalendarInfrastructureError.repositoryOperationFailed
        }
        if draft == original { progress(.refreshing); postRefresh(); return }
        let basis = max(Date(), draft.startDate)
        let through = Calendar.current.date(byAdding: .day, value: 90, to: basis) ?? basis

        if let partialFailure, partialFailure.stage == .replaceOccurrences {
            throw partialFailure
        } else if let partialFailure {
            try await coordinator.resumeRecurringSchedule(homeId: draft.homeID, templateId: draft.id,
                generateThrough: through, timezone: draft.timezone,
                remainingCalendarEventIds: partialFailure.remainingCalendarEventIds,
                progress: { progress(Self.phase($0)) })
        } else if isAssignmentOnly(draft, original) {
            progress(.saving); log("save_chore_template", "started", draft)
            _ = try await saveTemplate(draft)
            log("save_chore_template", "completed", draft)
            progress(.futureChores); log("assignment refresh", "started", draft)
            _ = try await coordinator.refreshAssignmentsOnly(templateId: draft.id, effectiveFrom: effectiveDate(timezone: draft.timezone))
            log("assignment refresh", "completed", draft)
            progress(.refreshing)
            postRefresh()
        } else {
            _ = try await coordinator.replaceRecurringSchedule(homeId: draft.homeID,
                effectiveFrom: effectiveDate(timezone: draft.timezone), generateThrough: through, timezone: draft.timezone,
                progress: { stage in progress(Self.phase(stage)); self.log(stage, draft) }) {
                    try await self.saveTemplate(draft)
                }
        }
        progress(.refreshing)
        log("navigation", "dismissing edit and details", draft)
    }

    private func isAssignmentOnly(_ lhs: PhoneChoreDetail, _ rhs: PhoneChoreDetail) -> Bool {
        var left = lhs; var right = rhs
        left.assigneeIDs = []; left.assigneeNames = []; left.members = []; left.rooms = []
        right.assigneeIDs = []; right.assigneeNames = []; right.members = []; right.rooms = []
        return left == right && lhs.assigneeIDs != rhs.assigneeIDs
    }

    private func saveTemplate(_ draft: PhoneChoreDetail) async throws -> UUID {
        _ = try await client.auth.session
        return try await client.rpc("save_chore_template", params: PhoneEditSaveParameters(draft)).execute().value
    }
    private func effectiveDate(timezone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar.startOfDay(for: Date())
    }
    private func postRefresh() {
        NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
        NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
    }
    private static func phase(_ value: ChoreRecurringEditProgress) -> PhoneChoreSavePhase {
        switch value {
        case .savingTemplate: .saving
        case .replacingOccurrences: .futureChores
        case .updatingCalendar: .calendar
        case .refreshing: .refreshing
        }
    }
    private func log(_ stage: ChoreRecurringEditProgress, _ draft: PhoneChoreDetail) {
        log(String(describing: stage), "started", draft)
    }
    private func log(_ stage: String, _ state: String, _ draft: PhoneChoreDetail) {
        #if DEBUG
        print("[Homey] CHORE EDIT: \(stage) \(state) template_id=\(draft.id.uuidString) occurrence_id=\(draft.occurrenceID.uuidString)")
        #endif
    }
}

private struct PhoneEditSaveParameters: Encodable {
    let homeID, templateID: UUID; let title: String; let description, instructions: String?; let categoryID, roomID: UUID?
    let assignmentMode, completionMode: String; let points: Int; let approval, photo: Bool; let frequency: String; let interval: Int
    let startDate, dueTime: String?; let duration: Int; let allDay: Bool; let weekdays: [Int]; let day, month: Int?
    let endType, endsOn: String?; let count: Int?; let timezone: String; let assignees: [UUID]
    init(_ d: PhoneChoreDetail) {
        homeID=d.homeID; templateID=d.id; title=d.title.trimmingCharacters(in:.whitespacesAndNewlines); description=d.description.phoneNilIfBlank
        instructions=d.instructions.phoneNilIfBlank; categoryID=d.categoryID; roomID=d.roomID; assignmentMode=d.assignmentMode
        completionMode=d.completionMode.rawValue; points=d.pointsValue; approval=d.requiresApproval; photo=d.requiresPhoto
        frequency=d.frequency.rawValue; interval=d.intervalValue; startDate=ChoreCalendarDateFormatting.date(d.startDate, timezone:d.timezone)
        dueTime=d.isAllDay ? nil:d.dueTime; duration=d.durationMinutes; allDay=d.isAllDay; weekdays=Array(d.weekdays).sorted()
        day=d.dayOfMonth; month=d.monthOfYear; endType=d.frequency == .none ? "after_count":d.endType.rawValue
        endsOn=d.endType == .onDate ? d.endsOn.map { ChoreCalendarDateFormatting.date($0, timezone:d.timezone) }:nil
        count=d.frequency == .none ? 1:(d.endType == .afterCount ? d.occurrenceCount:nil); timezone=d.timezone; assignees=d.assigneeIDs
    }
    enum CodingKeys:String,CodingKey { case homeID="requested_home_id",templateID="requested_template_id",title="requested_title",description="requested_description",instructions="requested_instructions",categoryID="requested_category_id",roomID="requested_room_id",assignmentMode="requested_assignment_mode",completionMode="requested_completion_mode",points="requested_points_value",approval="requested_requires_approval",photo="requested_requires_photo",frequency="requested_frequency",interval="requested_interval_value",startDate="requested_start_date",dueTime="requested_due_time",duration="requested_duration_minutes",allDay="requested_is_all_day",weekdays="requested_weekdays",day="requested_day_of_month",month="requested_month_of_year",endType="requested_end_type",endsOn="requested_ends_on",count="requested_occurrence_count",timezone="requested_timezone",assignees="requested_assignee_ids" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(homeID, forKey: .homeID); try c.encode(templateID, forKey: .templateID); try c.encode(title, forKey: .title)
        try c.encodeOptional(description, forKey: .description); try c.encodeOptional(instructions, forKey: .instructions)
        try c.encodeOptional(categoryID, forKey: .categoryID); try c.encodeOptional(roomID, forKey: .roomID)
        try c.encode(assignmentMode, forKey: .assignmentMode); try c.encode(completionMode, forKey: .completionMode)
        try c.encode(points, forKey: .points); try c.encode(approval, forKey: .approval); try c.encode(photo, forKey: .photo)
        try c.encode(frequency, forKey: .frequency); try c.encode(interval, forKey: .interval); try c.encodeOptional(startDate, forKey: .startDate)
        try c.encodeOptional(dueTime, forKey: .dueTime); try c.encode(duration, forKey: .duration); try c.encode(allDay, forKey: .allDay)
        try c.encode(weekdays, forKey: .weekdays); try c.encodeOptional(day, forKey: .day); try c.encodeOptional(month, forKey: .month)
        try c.encodeOptional(endType, forKey: .endType); try c.encodeOptional(endsOn, forKey: .endsOn); try c.encodeOptional(count, forKey: .count)
        try c.encode(timezone, forKey: .timezone); try c.encode(assignees, forKey: .assignees)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}
