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
    @State private var confirmsDelete = false
    @State private var failedDeleteCalendarEventIDs: [UUID] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: EditChoreField?
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
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edit Chore").font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Update the details for this chore.")
                            .font(.system(size: 13)).foregroundStyle(HomeyColors.secondaryText)
                    }
                    if !initial.canSafelyEdit {
                        HomeyErrorView(message: initial.legacyExplanation)
                    } else {
                        editorCard {
                            editorLabel("Title")
                            TextField("Chore title", text: $draft.title)
                                .focused($focusedField, equals: .title).editorInput()
                        }
                        iconEditorCard(symbol: "house.fill", tint: .indigo) {
                            editorLabel("Room")
                            Picker("Room", selection: $draft.roomID) {
                                ForEach(draft.rooms) { Text($0.displayName).tag(Optional($0.id)) }
                            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).editorInput()
                        }
                        editorCard {
                            editorLabel("Description")
                            TextField("Description", text: $draft.description, axis: .vertical)
                                .lineLimit(2...6).focused($focusedField, equals: .description).editorInput(minHeight: 66)
                        }
                        assigneeAndPoints
                        recurrenceSection
                        approvalCard
                        iconEditorCard(symbol: "doc.text.fill", tint: .blue) {
                            editorLabel("Instructions")
                            TextField("Instructions", text: $draft.instructions, axis: .vertical)
                                .lineLimit(2...7).focused($focusedField, equals: .instructions).editorInput(minHeight: 66)
                        }
                        deleteButton
                    }
                    if let error { HomeyErrorView(message: error) }
                }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .disabled(saving || !initial.canSafelyEdit)
            }
            .background(HomeyColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Chores", systemImage: "chevron.left").font(.headline) }.disabled(saving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        Text("Save").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 15).frame(height: 44)
                    }.buttonStyle(.plain).foregroundStyle(.white)
                        .background(HomeyColors.primary, in: Capsule())
                        .disabled(!valid || saving || !initial.canSafelyEdit)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button("Done") { focusedField = nil }
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

    private func editorLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(HomeyColors.text)
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func iconEditorCard<Content: View>(symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            EditChoreIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 7) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var assigneeAndPoints: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { assigneeCard; pointsCard }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        assigneeCard.frame(minWidth: 150)
                        pointsCard.frame(minWidth: 130)
                    }
                    VStack(spacing: 10) { assigneeCard; pointsCard }
                }
            }
        }
    }

    private var assigneeCard: some View {
        iconEditorCard(symbol: "person.fill", tint: .purple) {
            editorLabel("Assigned To")
            Picker("Assigned To", selection: $selectedAssignee) {
                Text("Select").tag(Optional<UUID>.none)
                ForEach(draft.members) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).editorInput()
        }
    }

    private var pointsCard: some View {
        iconEditorCard(symbol: "dollarsign.circle.fill", tint: .green) {
            editorLabel("Points")
            Stepper("\(draft.pointsValue)", value: $draft.pointsValue, in: 0...1000, step: 1)
                .font(.system(size: 14)).editorInput()
        }
    }

    private var dueTimePicker: some View {
        DatePicker("Due Time", selection: Binding(get: { service.time(from: draft.dueTime) }, set: { draft.dueTime = service.timeString($0) }), displayedComponents: .hourAndMinute)
    }

    private var recurrenceSection: some View {
        editorCard {
            HStack(alignment: .top, spacing: 12) {
                EditChoreIcon(symbol: "arrow.triangle.2.circlepath", tint: .pink)
                VStack(alignment: .leading, spacing: 8) {
                    editorLabel("Recurrence")
                    Picker("Frequency", selection: $draft.frequency) { ForEach(PhoneEditFrequency.allCases) { Text($0.displayName).tag($0) } }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).editorInput()
                    if draft.frequency != .none { Stepper("Every \(draft.intervalValue)", value: $draft.intervalValue, in: 1...52) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Divider().padding(.vertical, 4)
            HStack(alignment: .top, spacing: 12) {
                EditChoreIcon(symbol: "infinity", tint: .indigo)
                VStack(alignment: .leading, spacing: 8) {
                    editorLabel("Ends")
                    Picker("Chore Ends", selection: $draft.endType) { ForEach(PhoneEditEndType.allCases) { Text($0.displayName).tag($0) } }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).editorInput()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if draft.endType == .onDate { DatePicker("End Date", selection: Binding(get: { draft.endsOn ?? draft.startDate }, set: { draft.endsOn = $0 }), displayedComponents: .date) }
            if draft.endType == .afterCount { Stepper("\(draft.occurrenceCount ?? 1) occurrences", value: Binding(get: { draft.occurrenceCount ?? 1 }, set: { draft.occurrenceCount = $0 }), in: 1...999) }
            Divider().padding(.vertical, 4)
            DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
            Toggle("All Day", isOn: $draft.isAllDay)
            if !draft.isAllDay { dueTimePicker }
        }
    }

    private var approvalCard: some View {
        iconEditorCard(symbol: "checkmark.circle", tint: .purple) {
            Toggle(isOn: $draft.requiresApproval) {
                VStack(alignment: .leading, spacing: 4) {
                    editorLabel("Requires Approval")
                    Text("Chore must be approved before it is marked complete.")
                        .font(.system(size: 12)).foregroundStyle(HomeyColors.secondaryText)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            #if DEBUG
            print("[Homey] CHORE DELETE: button tapped template_id=\(draft.id.uuidString)")
            #endif
            confirmsDelete = true
            #if DEBUG
            print("[Homey] CHORE DELETE: confirmation presented template_id=\(draft.id.uuidString)")
            #endif
        } label: {
            Label(failedDeleteCalendarEventIDs.isEmpty ? "Delete Chore" : "Retry Calendar Cleanup", systemImage: "trash")
                .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .buttonStyle(.plain).foregroundStyle(HomeyColors.danger)
        .background(HomeyColors.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        .disabled(saving || !(home.role == .owner || home.role == .admin))
        .confirmationDialog("Delete Chore?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Chore", role: .destructive) { Task { await deleteChore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete this chore and its unstarted occurrences? Started and completed chore history, earned points, and rewards will be preserved.")
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

    private func deleteChore() async {
        guard savePhase == nil, appSession.activeHome?.id == home.id else { return }
        savePhase = .deleting; error = nil
        #if DEBUG
        print("[Homey] CHORE DELETE: confirmed template_id=\(draft.id.uuidString)")
        print("[Homey] CHORE DELETE: backend deletion started template_id=\(draft.id.uuidString)")
        #endif
        do {
            try await service.retire(
                draft: draft,
                retryCalendarEventIDs: failedDeleteCalendarEventIDs
            ) { phase in savePhase = phase }
            failedDeleteCalendarEventIDs = []
            #if DEBUG
            print("[Homey] CHORE DELETE: backend deletion completed template_id=\(draft.id.uuidString)")
            print("[Homey] CHORE DELETE: calendar cleanup completed template_id=\(draft.id.uuidString)")
            print("[Homey] CHORE DELETE: chores refreshed template_id=\(draft.id.uuidString)")
            #endif
            savePhase = .refreshing
            onSaved()
            #if DEBUG
            print("[Homey] CHORE DELETE: navigation completed template_id=\(draft.id.uuidString)")
            #endif
        } catch let partial as PhoneChoreDeletePartialFailure {
            failedDeleteCalendarEventIDs = partial.remainingCalendarEventIDs
            self.error = partial.localizedDescription
            #if DEBUG
            print("[Homey] CHORE DELETE: calendar cleanup failed template_id=\(draft.id.uuidString) remaining=\(partial.remainingCalendarEventIDs.count)")
            #endif
        } catch {
            self.error = "The chore could not be deleted. \(error.localizedDescription)"
            #if DEBUG
            print("[Homey] CHORE DELETE: backend deletion failed template_id=\(draft.id.uuidString) error=\(String(reflecting: error))")
            #endif
        }
        savePhase = nil
    }
}

private enum EditChoreField { case title, description, instructions }

private struct EditChoreIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 40, height: 40).background(tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private extension View {
    func editorInput(minHeight: CGFloat = 44) -> some View {
        padding(.horizontal, 12).frame(minHeight: minHeight, alignment: .leading)
            .font(.system(size: 14)).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HomeyColors.border.opacity(0.65), lineWidth: 1))
    }
}

enum PhoneChoreSavePhase {
    case saving, futureChores, calendar, refreshing, deleting
    var message: String {
        switch self {
        case .saving: "Saving Chore..."
        case .futureChores: "Updating future chores..."
        case .calendar: "Updating calendar..."
        case .refreshing: "Refreshing chores..."
        case .deleting: "Deleting chore..."
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

    func retire(
        draft: PhoneChoreDetail,
        retryCalendarEventIDs: [UUID],
        progress: @escaping (PhoneChoreSavePhase) -> Void
    ) async throws {
        _ = try await client.auth.session
        let calendarEventIDs: [UUID]
        if retryCalendarEventIDs.isEmpty {
            progress(.deleting)
            let rows: [PhoneRetiredOccurrenceRow] = try await client.rpc(
                "retire_chore_template",
                params: PhoneRetireChoreParameters(templateID: draft.id, effectiveFrom: Date())
            ).execute().value
            calendarEventIDs = rows.compactMap(\.calendarEventID)
        } else {
            calendarEventIDs = retryCalendarEventIDs
        }
        progress(.calendar)
        let calendarService = ChoreCalendarService()
        var failedEventIDs: [UUID] = []
        for eventID in calendarEventIDs {
            do { try await calendarService.deleteEvent(eventId: eventID) }
            catch { failedEventIDs.append(eventID) }
        }
        if !failedEventIDs.isEmpty {
            NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
            throw PhoneChoreDeletePartialFailure(remainingCalendarEventIDs: failedEventIDs)
        }
        progress(.refreshing)
        postRefresh()
    }

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

private struct PhoneChoreDeletePartialFailure: LocalizedError {
    let remainingCalendarEventIDs: [UUID]
    var errorDescription: String? {
        "The chore was deleted, but some future calendar events could not be removed. Tap Retry Calendar Cleanup to finish."
    }
}

private struct PhoneRetireChoreParameters: Encodable {
    let templateID: UUID
    let effectiveFrom: String
    init(templateID: UUID, effectiveFrom: Date) {
        self.templateID = templateID
        self.effectiveFrom = ChoreCalendarDateFormatting.timestamp(effectiveFrom)
    }
    enum CodingKeys: String, CodingKey {
        case templateID = "requested_template_id"
        case effectiveFrom = "effective_from"
    }
}

private struct PhoneRetiredOccurrenceRow: Decodable {
    let occurrenceID: UUID
    let calendarEventID: UUID?
    enum CodingKeys: String, CodingKey {
        case occurrenceID = "occurrence_id"
        case calendarEventID = "calendar_event_id"
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
