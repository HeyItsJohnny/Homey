import SwiftUI
import Supabase
import Combine

private enum AddChoreFrequency: String, CaseIterable, Identifiable {
    case oneTime, daily, weekly, monthly, everySixMonths, annually
    var id: Self { self }
    var title: String {
        switch self {
        case .oneTime: "One Time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .everySixMonths: "Every 6 Months"
        case .annually: "Annually"
        }
    }
    var backendValue: String {
        switch self {
        case .oneTime: "none"
        case .everySixMonths: "monthly"
        case .annually: "yearly"
        default: rawValue
        }
    }
    var interval: Int { self == .everySixMonths ? 6 : 1 }
}

private enum AddChoreEnd: String, CaseIterable, Identifiable {
    case never, onDate, afterCount
    var id: Self { self }
    var title: String {
        switch self { case .never: "Never"; case .onDate: "On Date"; case .afterCount: "After Count" }
    }
    var backendValue: String {
        switch self { case .never: "never"; case .onDate: "on_date"; case .afterCount: "after_count" }
    }
}

private enum AddChoreRoomType: String, CaseIterable, Identifiable {
    case bedroom, kitchen, bathroom
    case livingRoom = "living_room"
    case diningRoom = "dining_room"
    case laundryRoom = "laundry_room"
    case office, garage, outdoor, other
    var id: Self { self }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

private struct AddChoreRoom: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let roomType: String?
    let sortOrder: Int
    var isGeneral: Bool { roomType == "other" || name.caseInsensitiveCompare("Other") == .orderedSame }
    var displayName: String { isGeneral ? "General" : name }
    enum CodingKeys: String, CodingKey {
        case id, name
        case roomType = "room_type", sortOrder = "sort_order"
    }
}

private struct AddChoreMember: Decodable, Identifiable {
    let userID: UUID
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let email: String?
    var id: UUID { userID }
    var name: String {
        let preferred = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return full.isEmpty ? (email?.split(separator: "@").first.map(String.init) ?? "Home Member") : full
    }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", firstName = "first_name", lastName = "last_name", displayName = "display_name", email
    }
}

@MainActor
private final class AddChoreDraft: ObservableObject {
    @Published var step = 0
    @Published var title = ""
    @Published var details = ""
    @Published var instructions = ""
    @Published var rooms: [AddChoreRoom] = []
    @Published var selectedRoomID: UUID?
    @Published var members: [AddChoreMember] = []
    @Published var frequency: AddChoreFrequency = .oneTime
    @Published var startDate = Date()
    @Published var isAllDay = true
    @Published var dueTime = Date()
    @Published var weekdays: Set<Int> = []
    @Published var dayOfMonth = Calendar.current.component(.day, from: Date())
    @Published var monthOfYear = Calendar.current.component(.month, from: Date())
    @Published var endType: AddChoreEnd = .never
    @Published var endsOn = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @Published var occurrenceCount = 10
    @Published var selectedAssigneeID: UUID?
    @Published var points = 0
    @Published var requiresApproval = true
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var loadErrorMessage: String?
    @Published var errorMessage: String?
}

struct AddChoreWizardView: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID?
    let role: HomeMemberRole?
    let timezone: String
    let onFinished: () -> Void
    @StateObject private var draft = AddChoreDraft()
    @State private var showingNewRoom = false
    private let service = AddChoreWizardService()

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                VStack(spacing: 0) {
                    progress
                    ScrollView { content.padding(16) }
                    controls
                }
            }
            .navigationTitle("Add Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(draft.isSaving) } }
            .interactiveDismissDisabled(draft.isSaving)
            .task(id: homeID) { await load() }
            .sheet(isPresented: $showingNewRoom) {
                AddChoreRoomSheet(homeID: homeID, service: service) { room in
                    draft.rooms.append(room)
                    draft.rooms.sort { $0.sortOrder < $1.sortOrder }
                    draft.selectedRoomID = room.id
                }
            }
            .alert("Unable to Save Chore", isPresented: Binding(
                get: { draft.errorMessage != nil },
                set: { if !$0 { draft.errorMessage = nil } }
            )) { Button("OK", role: .cancel) { draft.errorMessage = nil } } message: {
                Text(draft.errorMessage ?? "Please try again.")
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(draft.step + 1) of 5").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            ProgressView(value: Double(draft.step + 1), total: 5).tint(HomeyColors.primary)
        }.padding(.horizontal, 18).padding(.vertical, 12).background(.white.opacity(0.76))
    }

    @ViewBuilder private var content: some View {
        if draft.isLoading { ProgressView("Loading…").frame(maxWidth: .infinity).padding(.top, 50) }
        else if let loadErrorMessage = draft.loadErrorMessage {
            VStack(spacing: 14) {
                HomeyErrorView(message: loadErrorMessage)
                Button("Try Again") { Task { await load() } }.buttonStyle(HomeyButtonStyle())
            }.homeyCard()
        }
        else {
            switch draft.step {
            case 0: detailsStep
            case 1: roomStep
            case 2: scheduleStep
            case 3: rulesStep
            default: reviewStep
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).homeyCard()
    }
    private func heading(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(HomeyTypography.title); Text(message).foregroundStyle(HomeyColors.secondaryText) }
    }

    private var detailsStep: some View { card {
        VStack(alignment: .leading, spacing: 16) {
            heading("Chore Details", "Add the information household members need.")
            TextField("Chore Title", text: $draft.title).homeyTextField()
            TextField("Description (optional)", text: $draft.details, axis: .vertical).lineLimit(2...4).homeyTextField()
            TextField("Instructions (optional)", text: $draft.instructions, axis: .vertical).lineLimit(2...5).homeyTextField()
        }
    } }

    private var roomStep: some View { card {
        VStack(alignment: .leading, spacing: 12) {
            heading("Room", "Choose General for chores that do not belong to a physical room.")
            ForEach(draft.rooms.sorted { lhs, rhs in
                if lhs.isGeneral != rhs.isGeneral { return lhs.isGeneral }
                return lhs.sortOrder < rhs.sortOrder
            }) { room in
                Button { draft.selectedRoomID = room.id } label: {
                    HStack { Image(systemName: draft.selectedRoomID == room.id ? "checkmark.circle.fill" : "circle"); Text(room.displayName); Spacer() }
                }.buttonStyle(.plain).foregroundStyle(draft.selectedRoomID == room.id ? HomeyColors.primary : HomeyColors.text).padding(.vertical, 7)
            }
            Divider()
            Button { showingNewRoom = true } label: { Label("Add New Room", systemImage: "plus.circle.fill") }
        }
    } }

    private var scheduleStep: some View { card {
        VStack(alignment: .leading, spacing: 16) {
            heading("Scheduling", "Choose when and how often this chore appears.")
            Picker("Repeats", selection: $draft.frequency) { ForEach(AddChoreFrequency.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
            Toggle("All Day", isOn: $draft.isAllDay).tint(HomeyColors.primary)
            if !draft.isAllDay { DatePicker("Due Time", selection: $draft.dueTime, displayedComponents: .hourAndMinute) }
            if draft.frequency == .weekly {
                Text("Weekdays").font(.headline)
                ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, day in
                    Toggle(day, isOn: Binding(
                        get: { draft.weekdays.contains(index) },
                        set: { selected in
                            if selected { draft.weekdays.insert(index) }
                            else { draft.weekdays.remove(index) }
                        }
                    )).tint(HomeyColors.primary)
                }
            }
            if draft.frequency == .monthly || draft.frequency == .everySixMonths || draft.frequency == .annually {
                Stepper("Day \(draft.dayOfMonth)", value: $draft.dayOfMonth, in: 1...31)
            }
            if draft.frequency == .annually {
                Picker("Month", selection: $draft.monthOfYear) { ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) } }
            }
            if draft.frequency != .oneTime {
                Text("Chore Ends")
                    .font(.headline)
                    .foregroundStyle(HomeyColors.text)
                Picker("Ends", selection: $draft.endType) { ForEach(AddChoreEnd.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                if draft.endType == .onDate { DatePicker("End Date", selection: $draft.endsOn, displayedComponents: .date) }
                if draft.endType == .afterCount { Stepper("\(draft.occurrenceCount) occurrences", value: $draft.occurrenceCount, in: 1...999) }
            }
        }
    } }

    private var rulesStep: some View { card {
        VStack(alignment: .leading, spacing: 16) {
            heading("Assignment and Rules", "Set ownership, approval, and reward points.")
            ChoreSingleAssigneePicker(
                options: draft.members.map { ChoreAssigneeOption(id: $0.id, name: $0.name) },
                selection: $draft.selectedAssigneeID
            )
            Stepper("\(draft.points) points", value: $draft.points, in: 0...10_000, step: 1)
            Toggle("Requires Approval", isOn: $draft.requiresApproval).tint(HomeyColors.primary)
        }
    } }

    private var reviewStep: some View { card {
        VStack(alignment: .leading, spacing: 10) {
            heading("Review", "Confirm the chore before saving.")
            Text(draft.title).font(.title2.bold())
            LabeledContent("Room", value: draft.rooms.first { $0.id == draft.selectedRoomID }?.displayName ?? "General")
            LabeledContent("Schedule", value: draft.frequency.title)
            LabeledContent("Assigned To", value: draft.members.first { $0.id == draft.selectedAssigneeID }?.name ?? "Not Selected")
            LabeledContent("Points", value: "\(draft.points)")
            LabeledContent("Approval", value: draft.requiresApproval ? "Required" : "Not Required")
        }
    } }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Back") { draft.step -= 1 }.buttonStyle(HomeyButtonStyle(secondary: true)).disabled(draft.step == 0 || draft.isLoading || draft.isSaving)
            Button(draft.step == 4 ? (draft.isSaving ? "Saving…" : "Create Chore") : "Continue") {
                if draft.step == 4 { Task { await save() } } else { draft.step += 1 }
            }.buttonStyle(HomeyButtonStyle()).disabled(!canContinue || draft.isSaving)
        }.padding(16).background(.white.opacity(0.86))
    }

    private var canContinue: Bool {
        guard !draft.isLoading else { return false }
        switch draft.step {
        case 0: return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1: return draft.selectedRoomID != nil
        case 2: return draft.frequency != .weekly || !draft.weekdays.isEmpty
        case 3: return draft.selectedAssigneeID != nil
        default: return true
        }
    }

    private func load() async {
        guard let homeID else { draft.isLoading = false; draft.loadErrorMessage = "Select a Home before adding a chore."; return }
        draft.isLoading = true
        draft.loadErrorMessage = nil
        do {
            async let rooms = service.roomsEnsuringGeneral(homeID: homeID)
            async let members = service.members(homeID: homeID)
            let loaded = try await (rooms, members)
            guard self.homeID == homeID else { return }
            draft.rooms = loaded.0
            draft.members = loaded.1
            draft.selectedRoomID = loaded.0.first(where: \.isGeneral)?.id
            if !loaded.1.contains(where: { $0.id == draft.selectedAssigneeID }) {
                draft.selectedAssigneeID = nil
            }
        } catch { draft.loadErrorMessage = "Unable to load rooms. Please try again." }
        draft.isLoading = false
    }

    private func save() async {
        guard role == .owner || role == .admin else { draft.errorMessage = "Only an owner or admin can create chores."; return }
        guard let homeID, let roomID = draft.selectedRoomID else { draft.errorMessage = "Choose a Home and Room."; return }
        guard draft.selectedAssigneeID != nil else { draft.errorMessage = ChoreSingleAssigneeError.selectionRequired.localizedDescription; return }
        draft.isSaving = true
        defer { draft.isSaving = false }
        do {
            try await service.save(homeID: homeID, roomID: roomID, draft: draft, timezone: timezone)
            guard self.homeID == homeID else { return }
            NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
            NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
            onFinished()
            dismiss()
        } catch { draft.errorMessage = error.localizedDescription }
    }
}

private struct AddChoreRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID?
    let service: AddChoreWizardService
    let onCreated: (AddChoreRoom) -> Void
    @State private var name = ""
    @State private var roomType: AddChoreRoomType = .bedroom
    @State private var isSaving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Room Name", text: $name)
                Picker("Room Type", selection: $roomType) { ForEach(AddChoreRoomType.allCases) { Text($0.title).tag($0) } }
                if let error { Text(error).foregroundStyle(HomeyColors.danger) }
            }
                .navigationTitle("Add New Room")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") { Task { await create() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving) }
                }
        }
    }
    private func create() async {
        guard let homeID else { return }
        isSaving = true; defer { isSaving = false }
        do { let room = try await service.createRoom(homeID: homeID, name: name, roomType: roomType.rawValue); onCreated(room); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct AddChoreWizardService {
    private let client = SupabaseManager.shared.client
    func roomsEnsuringGeneral(homeID: UUID) async throws -> [AddChoreRoom] {
        var rooms: [AddChoreRoom] = try await client.from("chore_rooms").select("id,name,room_type,sort_order").eq("home_id", value: homeID.uuidString).order("sort_order").execute().value
        if !rooms.contains(where: \.isGeneral) {
            _ = try await createRoom(homeID: homeID, name: "Other", roomType: "other")
            rooms = try await client.from("chore_rooms").select("id,name,room_type,sort_order").eq("home_id", value: homeID.uuidString).order("sort_order").execute().value
        }
        return rooms
    }
    func members(homeID: UUID) async throws -> [AddChoreMember] {
        try await client.rpc("get_home_members", params: AddChoreMembersParams(homeID: homeID)).execute().value
    }
    func createRoom(homeID: UUID, name: String, roomType: String = "other") async throws -> AddChoreRoom {
        let userID = try await client.auth.session.user.id
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing: [AddChoreRoom] = try await client.from("chore_rooms").select("id,name,room_type,sort_order").eq("home_id", value: homeID.uuidString).order("sort_order").execute().value
        if let room = existing.first(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) { return room }
        let nextSortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let payload = AddChoreRoomPayload(homeID: homeID, name: normalizedName, roomType: roomType, sortOrder: nextSortOrder, createdBy: userID)
        return try await client.from("chore_rooms").insert(payload).select("id,name,room_type,sort_order").single().execute().value
    }
    func save(homeID: UUID, roomID: UUID, draft: AddChoreDraft, timezone: String) async throws {
        guard draft.selectedAssigneeID != nil else { throw ChoreSingleAssigneeError.selectionRequired }
        let calendar = Calendar.current
        let date = Self.dateString(draft.startDate, timezone: timezone)
        let dueTime = draft.isAllDay ? nil : String(format: "%02d:%02d:00", calendar.component(.hour, from: draft.dueTime), calendar.component(.minute, from: draft.dueTime))
        let params = AddChoreSaveParams(homeID: homeID, roomID: roomID, draft: draft, timezone: timezone, startDate: date, dueTime: dueTime)
        let templateID: UUID = try await client.rpc("save_chore_template", params: params).execute().value
        let through = calendar.date(byAdding: .day, value: 90, to: max(Date(), draft.startDate)) ?? draft.startDate
        let _: [UUID] = try await client.rpc("generate_chore_occurrences", params: AddChoreGenerateParams(templateID: templateID, through: Self.dateString(through, timezone: timezone))).execute().value
    }
    private static func dateString(_ date: Date, timezone: String) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

private struct AddChoreMembersParams: Encodable { let homeID: UUID; enum CodingKeys: String, CodingKey { case homeID = "target_home_id" } }
private struct AddChoreRoomPayload: Encodable {
    let homeID: UUID, name: String, roomType: String
    let sortOrder: Int
    let createdBy: UUID
    let preferredCleaningFrequency = "weekly"
    enum CodingKeys: String, CodingKey { case homeID = "home_id", name, roomType = "room_type", sortOrder = "sort_order", createdBy = "created_by", preferredCleaningFrequency = "preferred_cleaning_frequency" }
}
private struct AddChoreGenerateParams: Encodable { let templateID: UUID; let through: String; enum CodingKeys: String, CodingKey { case templateID = "requested_template_id", through = "generate_through" } }

private struct AddChoreSaveParams: Encodable {
    let requestedHomeID: UUID
    let requestedTemplateID: UUID? = nil
    let requestedTitle: String
    let requestedDescription: String?
    let requestedInstructions: String?
    let requestedCategoryID: UUID? = nil
    let requestedRoomID: UUID
    let requestedAssignmentMode: String
    let requestedCompletionMode: String
    let requestedPointsValue: Int
    let requestedRequiresApproval: Bool
    let requestedRequiresPhoto = false
    let requestedFrequency: String
    let requestedIntervalValue: Int
    let requestedStartDate: String
    let requestedDueTime: String?
    let requestedDurationMinutes = 30
    let requestedIsAllDay: Bool
    let requestedWeekdays: [Int]
    let requestedDayOfMonth: Int?
    let requestedMonthOfYear: Int?
    let requestedEndType: String
    let requestedEndsOn: String?
    let requestedOccurrenceCount: Int?
    let requestedTimezone: String
    let requestedAssigneeIDs: [UUID]
    init(homeID: UUID, roomID: UUID, draft: AddChoreDraft, timezone: String, startDate: String, dueTime: String?) {
        requestedHomeID = homeID; requestedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        requestedDescription = draft.details.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        requestedInstructions = draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        requestedRoomID = roomID; requestedAssignmentMode = "assigned"
        requestedCompletionMode = "single"
        requestedPointsValue = draft.points; requestedRequiresApproval = draft.requiresApproval
        requestedFrequency = draft.frequency.backendValue; requestedIntervalValue = draft.frequency.interval
        requestedStartDate = startDate; requestedDueTime = dueTime; requestedIsAllDay = draft.isAllDay
        requestedWeekdays = draft.frequency == .weekly ? draft.weekdays.sorted() : []
        requestedDayOfMonth = [.monthly, .everySixMonths, .annually].contains(draft.frequency) ? draft.dayOfMonth : nil
        requestedMonthOfYear = draft.frequency == .annually ? draft.monthOfYear : nil
        requestedEndType = draft.frequency == .oneTime ? "after_count" : draft.endType.backendValue
        requestedEndsOn = draft.frequency != .oneTime && draft.endType == .onDate ? Self.dateString(draft.endsOn, timezone: timezone) : nil
        requestedOccurrenceCount = draft.frequency == .oneTime ? 1 : (draft.endType == .afterCount ? draft.occurrenceCount : nil)
        requestedTimezone = timezone
        requestedAssigneeIDs = draft.selectedAssigneeID.map { [$0] } ?? []
    }
    private static func dateString(_ date: Date, timezone: String) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let p = calendar.dateComponents([.year, .month, .day], from: date); return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
    enum CodingKeys: String, CodingKey {
        case requestedHomeID = "requested_home_id", requestedTemplateID = "requested_template_id", requestedTitle = "requested_title", requestedDescription = "requested_description", requestedInstructions = "requested_instructions", requestedCategoryID = "requested_category_id", requestedRoomID = "requested_room_id", requestedAssignmentMode = "requested_assignment_mode", requestedCompletionMode = "requested_completion_mode", requestedPointsValue = "requested_points_value", requestedRequiresApproval = "requested_requires_approval", requestedRequiresPhoto = "requested_requires_photo", requestedFrequency = "requested_frequency", requestedIntervalValue = "requested_interval_value", requestedStartDate = "requested_start_date", requestedDueTime = "requested_due_time", requestedDurationMinutes = "requested_duration_minutes", requestedIsAllDay = "requested_is_all_day", requestedWeekdays = "requested_weekdays", requestedDayOfMonth = "requested_day_of_month", requestedMonthOfYear = "requested_month_of_year", requestedEndType = "requested_end_type", requestedEndsOn = "requested_ends_on", requestedOccurrenceCount = "requested_occurrence_count", requestedTimezone = "requested_timezone", requestedAssigneeIDs = "requested_assignee_ids"
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestedHomeID, forKey: .requestedHomeID); try c.encodeNil(forKey: .requestedTemplateID); try c.encode(requestedTitle, forKey: .requestedTitle)
        try c.encodeIfPresent(requestedDescription, forKey: .requestedDescription); if requestedDescription == nil { try c.encodeNil(forKey: .requestedDescription) }
        try c.encodeIfPresent(requestedInstructions, forKey: .requestedInstructions); if requestedInstructions == nil { try c.encodeNil(forKey: .requestedInstructions) }
        try c.encodeNil(forKey: .requestedCategoryID); try c.encode(requestedRoomID, forKey: .requestedRoomID); try c.encode(requestedAssignmentMode, forKey: .requestedAssignmentMode); try c.encode(requestedCompletionMode, forKey: .requestedCompletionMode); try c.encode(requestedPointsValue, forKey: .requestedPointsValue); try c.encode(requestedRequiresApproval, forKey: .requestedRequiresApproval); try c.encode(requestedRequiresPhoto, forKey: .requestedRequiresPhoto); try c.encode(requestedFrequency, forKey: .requestedFrequency); try c.encode(requestedIntervalValue, forKey: .requestedIntervalValue); try c.encode(requestedStartDate, forKey: .requestedStartDate)
        try c.encodeIfPresent(requestedDueTime, forKey: .requestedDueTime); if requestedDueTime == nil { try c.encodeNil(forKey: .requestedDueTime) }
        try c.encode(requestedDurationMinutes, forKey: .requestedDurationMinutes); try c.encode(requestedIsAllDay, forKey: .requestedIsAllDay); try c.encode(requestedWeekdays, forKey: .requestedWeekdays)
        try c.encodeIfPresent(requestedDayOfMonth, forKey: .requestedDayOfMonth); if requestedDayOfMonth == nil { try c.encodeNil(forKey: .requestedDayOfMonth) }
        try c.encodeIfPresent(requestedMonthOfYear, forKey: .requestedMonthOfYear); if requestedMonthOfYear == nil { try c.encodeNil(forKey: .requestedMonthOfYear) }
        try c.encode(requestedEndType, forKey: .requestedEndType)
        try c.encodeIfPresent(requestedEndsOn, forKey: .requestedEndsOn); if requestedEndsOn == nil { try c.encodeNil(forKey: .requestedEndsOn) }
        try c.encodeIfPresent(requestedOccurrenceCount, forKey: .requestedOccurrenceCount); if requestedOccurrenceCount == nil { try c.encodeNil(forKey: .requestedOccurrenceCount) }
        try c.encode(requestedTimezone, forKey: .requestedTimezone); try c.encode(requestedAssigneeIDs, forKey: .requestedAssigneeIDs)
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
