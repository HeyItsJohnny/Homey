import SwiftUI
import Supabase
import Combine

// Implementation notes: this phone flow intentionally uses the iPad ChoreQuickSetup
// contracts: chore_rooms, save_chore_template, generate_chore_occurrences, PostgreSQL
// weekday values (Sunday = 0), and the same room/suggestion/points catalog. Its draft
// remains local until confirmation. No parallel database model or RPC is introduced.

private enum SetupRoomType: String, CaseIterable, Identifiable, Codable {
    case bedroom, kitchen, bathroom
    case livingRoom = "living_room"
    case diningRoom = "dining_room"
    case laundryRoom = "laundry_room"
    case office, garage, outdoor, other
    var id: String { rawValue }
    var name: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

private enum SetupWeekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    var id: Int { rawValue }
    var name: String { Calendar.current.weekdaySymbols[rawValue - 1] }
    var postgresValue: Int { rawValue - 1 }
}

private enum SetupFrequency: String, CaseIterable, Identifiable {
    case daily, weekly, everyTwoWeeks, monthly, biannually, annually, oneTime
    var id: String { rawValue }
    var name: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .everyTwoWeeks: "Every 2 Weeks"
        case .monthly: "Monthly"
        case .biannually: "Every 6 Months"
        case .annually: "Annually"
        case .oneTime: "One Time"
        }
    }
    var backendFrequency: String {
        switch self {
        case .oneTime: "none"
        case .annually, .biannually: "yearly"
        default: rawValue == "everyTwoWeeks" ? "weekly" : rawValue
        }
    }
    var interval: Int { self == .everyTwoWeeks ? 2 : (self == .biannually ? 6 : 1) }
    var usesWeekday: Bool { self == .weekly || self == .everyTwoWeeks }
}

private struct SetupSuggestion {
    let name: String
    let frequency: SetupFrequency
    let points: Int
    let cleansRoom: Bool
    let selected: Bool
}

private enum SetupCatalog {
    static func roomType(for name: String) -> SetupRoomType {
        let value = name.lowercased()
        if value.contains("kitchen") { return .kitchen }
        if value.contains("bath") { return .bathroom }
        if value.contains("living") { return .livingRoom }
        if value.contains("dining") { return .diningRoom }
        if value.contains("laundry") { return .laundryRoom }
        if value.contains("office") { return .office }
        if value.contains("garage") { return .garage }
        if value.contains("outdoor") || value.contains("yard") || value.contains("patio") { return .outdoor }
        if value.contains("bed") { return .bedroom }
        return .other
    }

    static func suggestions(for type: SetupRoomType) -> [SetupSuggestion] {
        func regular(_ name: String, _ frequency: SetupFrequency, _ points: Int, _ selected: Bool = true) -> SetupSuggestion {
            .init(name: name, frequency: frequency, points: points, cleansRoom: true, selected: selected)
        }
        func maintenance(_ name: String, _ frequency: SetupFrequency, _ points: Int, _ selected: Bool = true) -> SetupSuggestion {
            .init(name: name, frequency: frequency, points: points, cleansRoom: false, selected: selected)
        }
        switch type {
        case .bedroom: return [regular("Vacuum", .weekly, 10), regular("Dust Surfaces", .weekly, 5), regular("Pick Up / Organize", .weekly, 5), maintenance("Change Sheets", .everyTwoWeeks, 10), maintenance("Clean Mirror", .weekly, 5, false), maintenance("Clean Under Bed", .monthly, 20, false)]
        case .kitchen: return [regular("Wipe Counters", .daily, 5), regular("Clean Sink", .weekly, 10), regular("Sweep / Vacuum Floor", .weekly, 10), regular("Mop Floor", .weekly, 15), maintenance("Clean Microwave", .weekly, 10), maintenance("Wipe Appliances", .weekly, 10), maintenance("Clean Refrigerator", .monthly, 20, false)]
        case .bathroom: return [regular("Clean Toilet", .weekly, 10), regular("Clean Sink", .weekly, 10), regular("Clean Shower / Tub", .weekly, 15), regular("Clean Mirror", .weekly, 5), regular("Mop Floor", .weekly, 15)]
        case .livingRoom: return [regular("Vacuum", .weekly, 10), regular("Dust Surfaces", .weekly, 5), regular("Pick Up / Organize", .weekly, 5), maintenance("Vacuum Furniture", .monthly, 15, false), maintenance("Clean Windows", .monthly, 20, false)]
        case .diningRoom: return [regular("Wipe Table", .weekly, 5), regular("Sweep / Vacuum Floor", .weekly, 10), regular("Dust Surfaces", .weekly, 5)]
        case .laundryRoom: return [regular("Sweep / Vacuum Floor", .weekly, 10), regular("Wipe Surfaces", .weekly, 5), maintenance("Clean Washer", .monthly, 20, false), maintenance("Clean Dryer Lint Area", .weekly, 10)]
        case .office: return [regular("Vacuum", .weekly, 10), regular("Dust Desk / Surfaces", .weekly, 5), regular("Pick Up / Organize", .weekly, 5)]
        case .garage: return [regular("Sweep Floor", .monthly, 15), regular("Pick Up / Organize", .monthly, 15)]
        case .outdoor: return [maintenance("Sweep Patio", .weekly, 10), maintenance("Pick Up Yard", .weekly, 10), maintenance("Water Plants", .weekly, 5)]
        case .other: return [maintenance("Tidy Area", .weekly, 10), maintenance("Wipe Surfaces", .weekly, 5), maintenance("Pick Up / Organize", .weekly, 5)]
        }
    }
}

private struct SetupMember: Decodable, Identifiable {
    let membershipID: UUID
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
        case membershipID = "membership_id", userID = "user_id", firstName = "first_name", lastName = "last_name", displayName = "display_name", email
    }
}

private struct SetupChore: Identifiable {
    let id = UUID()
    var name: String
    var frequency: SetupFrequency
    var weekday: SetupWeekday
    var points: Int
    var contributesToRoomCleaning: Bool
    var isSelected: Bool
    var isCustom = false
    var isOpen = true
    var assigneeIDs: Set<UUID> = []
    var createdTemplateID: UUID?
}

@MainActor
private final class RoomChoreSetupDraft: ObservableObject {
    @Published var step = 0
    @Published var roomName = ""
    @Published var roomType: SetupRoomType = .other
    @Published var weekday: SetupWeekday = .saturday
    @Published var chores: [SetupChore] = []
    @Published var members: [SetupMember] = []
    @Published var createdRoomID: UUID?
    @Published var createdCount = 0
    @Published var currentItem: String?
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var isComplete = false

    var selected: [SetupChore] { chores.filter(\.isSelected) }
    func loadSuggestions() {
        chores = SetupCatalog.suggestions(for: roomType).map {
            SetupChore(name: $0.name, frequency: $0.frequency, weekday: weekday, points: $0.points, contributesToRoomCleaning: $0.cleansRoom, isSelected: $0.selected)
        }
    }
    func applyWeekday() { for index in chores.indices { chores[index].weekday = weekday } }
}

struct RoomChoreSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID?
    let role: HomeMemberRole?
    let timezone: String
    let onFinished: () -> Void
    @StateObject private var draft = RoomChoreSetupDraft()
    @State private var customName = ""
    @State private var showsCustomChore = false
    private let service = RoomChoreSetupService()

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                VStack(spacing: 0) {
                    if !draft.isComplete { progressHeader }
                    ScrollView { content.padding(16).padding(.bottom, 10) }
                    bottomBar
                }
            }
            .navigationTitle(draft.isComplete ? "Room Ready" : "Add Room and Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(draft.isCreating) } }
            .interactiveDismissDisabled(draft.isCreating)
            .alert("Add Custom Chore", isPresented: $showsCustomChore) {
                TextField("Chore Name", text: $customName)
                Button("Cancel", role: .cancel) { customName = "" }
                Button("Add") { addCustomChore() }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .task { await loadMembers() }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(draft.step + 1) of 8").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            ProgressView(value: Double(draft.step + 1), total: 8).tint(HomeyColors.primary)
        }.padding(.horizontal, 18).padding(.vertical, 12).background(.white.opacity(0.76))
    }

    @ViewBuilder private var content: some View {
        if draft.isComplete { successStep }
        else if draft.isCreating || draft.errorMessage != nil { creationStep }
        else {
            switch draft.step {
            case 0: roomNameStep
            case 1: roomTypeStep
            case 2: cleaningDayStep
            case 3: choresStep
            case 4: scheduleStep
            case 5: pointsStep
            case 6: assignmentStep
            default: summaryStep
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View { content().frame(maxWidth: .infinity, alignment: .leading).homeyCard() }
    private func intro(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(HomeyTypography.title); Text(body).foregroundStyle(HomeyColors.secondaryText) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roomNameStep: some View { card {
        VStack(alignment: .leading, spacing: 20) {
            intro("Add a Room", "Let's set up a room and the chores that keep it clean.")
            VStack(alignment: .leading, spacing: 7) { Text("Room Name").font(.headline); TextField("Master Bedroom", text: $draft.roomName).textInputAutocapitalization(.words).homeyTextField() }
        }
    } }
    private var roomTypeStep: some View { card {
        VStack(alignment: .leading, spacing: 20) {
            intro("Verify Room Type", "Homey uses this to suggest the right chores. You always have final control.")
            Picker("Room Type", selection: $draft.roomType) { ForEach(SetupRoomType.allCases) { Text($0.name).tag($0) } }.pickerStyle(.menu).padding().background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 14))
            LabeledContent("Room", value: draft.roomName)
        }
    } }
    private var cleaningDayStep: some View { card {
        VStack(alignment: .leading, spacing: 18) {
            intro("Preferred Cleaning Day", "What day do you usually want to take care of this room?")
            ForEach(SetupWeekday.allCases) { day in selectionRow(day.name, selected: draft.weekday == day) { draft.weekday = day } }
        }
    } }
    private var choresStep: some View { card {
        VStack(alignment: .leading, spacing: 14) {
            intro("Suggested Chores", "Choose the chores you want for \(draft.roomName).")
            ForEach($draft.chores) { $chore in
                Button { chore.isSelected.toggle() } label: { HStack { Image(systemName: chore.isSelected ? "checkmark.circle.fill" : "circle"); Text(chore.name); Spacer(); Text(chore.frequency.name).font(.caption).foregroundStyle(HomeyColors.secondaryText) } }.buttonStyle(.plain).foregroundStyle(chore.isSelected ? HomeyColors.primary : HomeyColors.text).padding(.vertical, 7)
            }
            Button { showsCustomChore = true } label: { Label("Add Custom Chore", systemImage: "plus.circle.fill") }.padding(.top, 6)
        }
    } }
    private var scheduleStep: some View { VStack(spacing: 12) {
        intro("Chore Schedule", "Each suggestion starts with the room's preferred day and can be changed.").padding(.horizontal, 4)
        ForEach($draft.chores) { $chore in if chore.isSelected { card { VStack(alignment: .leading, spacing: 12) { Text(chore.name).font(.headline); Picker("Repeats", selection: $chore.frequency) { ForEach(SetupFrequency.allCases) { Text($0.name).tag($0) } }; if chore.frequency.usesWeekday { Picker("Day", selection: $chore.weekday) { ForEach(SetupWeekday.allCases) { Text($0.name).tag($0) } } } } } } }
    } }
    private var pointsStep: some View { card {
        VStack(alignment: .leading, spacing: 16) {
            intro("Reward Points", "Review the iPad setup's suggested rewards and adjust them if needed.")
            ForEach($draft.chores) { $chore in if chore.isSelected { HStack { Text(chore.name); Spacer(); Stepper("\(chore.points) pts", value: $chore.points, in: 0...10_000, step: 5).fixedSize() }.padding(.vertical, 5) } }
        }
    } }
    private var assignmentStep: some View { card {
        VStack(alignment: .leading, spacing: 15) {
            intro("Assign Household Members", "Choose who can handle each chore.")
            if draft.members.isEmpty {
                Text("No household members are available. These chores will be open to anyone.")
                    .font(.footnote)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
            ForEach($draft.chores) { $chore in
                if chore.isSelected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(chore.name)
                            .font(.headline)
                        ForEach(draft.members) { member in
                            Toggle(
                                member.name,
                                isOn: Binding(
                                    get: { chore.assigneeIDs.contains(member.userID) },
                                    set: { isSelected in
                                        if isSelected {
                                            chore.assigneeIDs.insert(member.userID)
                                        } else {
                                            chore.assigneeIDs.remove(member.userID)
                                        }
                                        chore.isOpen = chore.assigneeIDs.isEmpty
                                    }
                                )
                            )
                            .tint(HomeyColors.primary)
                        }
                    }
                    .padding(14)
                    .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                }
            }
        }
    } }
    private var summaryStep: some View { VStack(spacing: 14) {
        card { VStack(alignment: .leading, spacing: 12) { Text(draft.roomName).font(.title.bold()); LabeledContent("Room Type", value: draft.roomType.name); LabeledContent("Preferred Day", value: draft.weekday.name) } }
        ForEach(draft.selected) { chore in card { VStack(alignment: .leading, spacing: 7) { Text(chore.name).font(.headline); Text(scheduleText(chore)); Text("\(chore.points) Points"); Text(assignmentText(chore)).foregroundStyle(HomeyColors.secondaryText) } } }
        Text("Nothing is written to Homey until you press Create Room & Chores.").font(.footnote).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
    } }
    private var creationStep: some View { card {
        VStack(spacing: 20) {
            Image(systemName: draft.errorMessage == nil ? "wand.and.stars" : "exclamationmark.triangle.fill").font(.system(size: 42)).foregroundStyle(draft.errorMessage == nil ? HomeyColors.primary : HomeyColors.danger)
            Text(draft.errorMessage == nil ? "Creating \(draft.roomName)" : "Setup couldn't finish").font(HomeyTypography.title).multilineTextAlignment(.center)
            ProgressView(value: Double(draft.createdCount), total: Double(max(draft.selected.count, 1))).tint(HomeyColors.primary)
            Text("\(draft.createdCount) of \(draft.selected.count) chores created").font(.headline)
            if let item = draft.currentItem { Text(item).foregroundStyle(HomeyColors.secondaryText) }
            if let error = draft.errorMessage { HomeyErrorView(message: "Homey created \(draft.createdCount) of \(draft.selected.count) chores. \(error) Retry continues only with unfinished chores.") }
        }.frame(maxWidth: .infinity)
    } }
    private var successStep: some View { card { VStack(spacing: 18) { Image(systemName: "checkmark.seal.fill").font(.system(size: 58)).foregroundStyle(HomeyColors.success); Text("\(draft.roomName) is ready!").font(.title.bold()); Text("\(draft.createdCount) chores created").foregroundStyle(HomeyColors.secondaryText) }.frame(maxWidth: .infinity).padding(.vertical, 22) } }

    @ViewBuilder private var bottomBar: some View {
        HStack(spacing: 12) {
            if draft.isComplete { Button("Done") { onFinished(); dismiss() }.buttonStyle(HomeyButtonStyle()) }
            else if draft.isCreating { Text("Please keep this open while setup finishes.").font(.footnote).foregroundStyle(HomeyColors.secondaryText).frame(maxWidth: .infinity) }
            else if draft.errorMessage != nil { Button("Back to Review") { draft.errorMessage = nil }.buttonStyle(HomeyButtonStyle(secondary: true)); Button("Retry") { Task { await create() } }.buttonStyle(HomeyButtonStyle()) }
            else { Button("Back") { draft.step -= 1 }.buttonStyle(HomeyButtonStyle(secondary: true)).disabled(draft.step == 0); Button(draft.step == 7 ? "Create" : "Continue") { advance() }.buttonStyle(HomeyButtonStyle()).disabled(!canAdvance) }
        }.padding(16).background(.white.opacity(0.86))
    }

    private var canAdvance: Bool {
        if draft.step == 0 { return !draft.roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if draft.step >= 3 { return !draft.selected.isEmpty && draft.selected.allSatisfy { $0.isOpen || !$0.assigneeIDs.isEmpty || draft.step < 7 } }
        return true
    }
    private func advance() {
        if draft.step == 0 { draft.roomName = draft.roomName.trimmingCharacters(in: .whitespacesAndNewlines); draft.roomType = SetupCatalog.roomType(for: draft.roomName) }
        if draft.step == 1 { draft.loadSuggestions() }
        if draft.step == 2 { draft.applyWeekday() }
        if draft.step == 7 { Task { await create() }; return }
        draft.step += 1
    }
    private func addCustomChore() { let name = customName.trimmingCharacters(in: .whitespacesAndNewlines); draft.chores.append(.init(name: name, frequency: .weekly, weekday: draft.weekday, points: 10, contributesToRoomCleaning: false, isSelected: true, isCustom: true)); customName = "" }
    private func selectionRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View { Button(action: action) { HStack { Image(systemName: selected ? "checkmark.circle.fill" : "circle"); Text(title); Spacer() }.contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(selected ? HomeyColors.primary : HomeyColors.text) }
    private func scheduleText(_ chore: SetupChore) -> String { chore.frequency.usesWeekday ? "\(chore.frequency.name) • \(chore.weekday.name)" : chore.frequency.name }
    private func assignmentText(_ chore: SetupChore) -> String { chore.isOpen ? "Open to Anyone" : draft.members.filter { chore.assigneeIDs.contains($0.userID) }.map(\.name).joined(separator: " + ") }
    private func loadMembers() async { guard let homeID else { return }; draft.members = (try? await service.members(homeID: homeID)) ?? [] }
    private func create() async {
        guard role == .owner || role == .admin else { draft.errorMessage = "Only an owner or admin can create rooms and chores."; return }
        guard let homeID else { draft.errorMessage = "Select a Home before running setup."; return }
        draft.isCreating = true; draft.errorMessage = nil
        do {
            let roomID: UUID
            if let existingRoomID = draft.createdRoomID {
                roomID = existingRoomID
            } else {
                roomID = try await service.createRoom(homeID: homeID, name: draft.roomName, type: draft.roomType, weekday: draft.weekday)
            }
            draft.createdRoomID = roomID
            for index in draft.chores.indices where draft.chores[index].isSelected && draft.chores[index].createdTemplateID == nil {
                draft.currentItem = draft.chores[index].name
                let id = try await service.createChore(homeID: homeID, roomID: roomID, chore: draft.chores[index], timezone: timezone)
                draft.chores[index].createdTemplateID = id
                draft.createdCount += 1
            }
            draft.isCreating = false; draft.isComplete = true; onFinished()
            NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
        } catch {
            draft.isCreating = false; draft.errorMessage = error.localizedDescription
            #if DEBUG
            print("[Homey] ROOM CHORE SETUP: \(String(reflecting: error))")
            #endif
        }
    }
}

private extension Notification.Name { static let homeyChoresDidChange = Notification.Name("homeyChoresDidChange") }

private struct RoomChoreSetupService {
    private let client = SupabaseManager.shared.client
    func members(homeID: UUID) async throws -> [SetupMember] { try await client.rpc("get_home_members", params: HomeMembersParams(targetHomeID: homeID)).execute().value }
    func createRoom(homeID: UUID, name: String, type: SetupRoomType, weekday: SetupWeekday) async throws -> UUID {
        let userID = try await client.auth.session.user.id
        let response: CreatedID = try await client.from("chore_rooms").insert(RoomPayload(homeID: homeID, name: name, roomType: type.rawValue, preferredCleaningFrequency: "weekly", preferredCleaningWeekday: weekday.rawValue, sortOrder: 0, createdBy: userID)).select("id").single().execute().value
        return response.id
    }
    func createChore(homeID: UUID, roomID: UUID, chore: SetupChore, timezone: String) async throws -> UUID {
        let start = startDate(for: chore, timezone: timezone)
        let parameters = SaveTemplateParams(homeID: homeID, roomID: roomID, chore: chore, timezone: timezone, startDate: dateString(start, timezone: timezone))
        let templateID: UUID = try await client.rpc("save_chore_template", params: parameters).execute().value
        try await client.from("chore_templates").update(RoomCleaningPayload(roomID: roomID, contributes: chore.contributesToRoomCleaning)).eq("id", value: templateID.uuidString).execute()
        let through = Calendar.current.date(byAdding: .day, value: 90, to: max(Date(), start)) ?? start
        let _: [UUID] = try await client.rpc("generate_chore_occurrences", params: GenerateParams(templateID: templateID, through: dateString(through, timezone: timezone))).execute().value
        return templateID
    }
    private func startDate(for chore: SetupChore, timezone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let now = calendar.startOfDay(for: Date())
        guard chore.frequency.usesWeekday else { return now }
        return calendar.nextDate(after: calendar.date(byAdding: .day, value: -1, to: now)!, matching: DateComponents(weekday: chore.weekday.rawValue), matchingPolicy: .nextTime) ?? now
    }
    private func dateString(_ date: Date, timezone: String) -> String { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timezone) ?? .current; let parts = calendar.dateComponents([.year, .month, .day], from: date); return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!) }
}

private struct HomeMembersParams: Encodable { let targetHomeID: UUID; enum CodingKeys: String, CodingKey { case targetHomeID = "target_home_id" } }
private struct CreatedID: Decodable { let id: UUID }
private struct RoomPayload: Encodable {
    let homeID: UUID, name: String, roomType: String, preferredCleaningFrequency: String
    let preferredCleaningWeekday: Int, sortOrder: Int, createdBy: UUID
    enum CodingKeys: String, CodingKey { case homeID = "home_id", name, roomType = "room_type", preferredCleaningWeekday = "preferred_cleaning_weekday", preferredCleaningFrequency = "preferred_cleaning_frequency", sortOrder = "sort_order", createdBy = "created_by" }
}
private struct RoomCleaningPayload: Encodable { let roomID: UUID; let contributes: Bool; enum CodingKeys: String, CodingKey { case roomID = "room_id", contributes = "contributes_to_room_cleaning" } }
private struct GenerateParams: Encodable { let templateID: UUID; let through: String; enum CodingKeys: String, CodingKey { case templateID = "requested_template_id", through = "generate_through" } }
private struct SaveTemplateParams: Encodable {
    let requestedHomeID: UUID; let requestedTemplateID: UUID? = nil; let requestedTitle: String
    let requestedDescription: String? = nil; let requestedInstructions: String? = nil; let requestedCategoryID: UUID? = nil
    let requestedRoomID: UUID; let requestedAssignmentMode: String; let requestedCompletionMode: String
    let requestedPointsValue: Int; let requestedRequiresApproval = true; let requestedRequiresPhoto = false
    let requestedFrequency: String; let requestedIntervalValue: Int; let requestedStartDate: String
    let requestedDueTime: String? = nil; let requestedDurationMinutes = 30; let requestedIsAllDay = true
    let requestedWeekdays: [Int]; let requestedDayOfMonth: Int?; let requestedMonthOfYear: Int?
    let requestedEndType: String; let requestedEndsOn: String? = nil; let requestedOccurrenceCount: Int?; let requestedTimezone: String; let requestedAssigneeIDs: [UUID]
    init(homeID: UUID, roomID: UUID, chore: SetupChore, timezone: String, startDate: String) {
        requestedHomeID = homeID; requestedTitle = chore.name; requestedRoomID = roomID
        requestedAssignmentMode = chore.isOpen ? "open" : "assigned"; requestedCompletionMode = chore.isOpen || chore.assigneeIDs.count <= 1 ? "single" : "everyone"
        requestedPointsValue = max(0, chore.points); requestedFrequency = chore.frequency.backendFrequency; requestedIntervalValue = chore.frequency.interval
        requestedStartDate = startDate; requestedWeekdays = chore.frequency.usesWeekday ? [chore.weekday.postgresValue] : []
        let day = Int(startDate.suffix(2)); let month = Int(startDate.dropFirst(5).prefix(2))
        requestedDayOfMonth = [.monthly, .annually, .biannually].contains(chore.frequency) ? day : nil
        requestedMonthOfYear = [.annually, .biannually].contains(chore.frequency) ? month : nil
        requestedEndType = chore.frequency == .oneTime ? "after_count" : "never"; requestedOccurrenceCount = chore.frequency == .oneTime ? 1 : nil
        requestedTimezone = timezone; requestedAssigneeIDs = chore.isOpen ? [] : Array(chore.assigneeIDs)
    }
    enum CodingKeys: String, CodingKey {
        case requestedHomeID = "requested_home_id", requestedTemplateID = "requested_template_id", requestedTitle = "requested_title", requestedDescription = "requested_description", requestedInstructions = "requested_instructions", requestedCategoryID = "requested_category_id", requestedRoomID = "requested_room_id", requestedAssignmentMode = "requested_assignment_mode", requestedCompletionMode = "requested_completion_mode", requestedPointsValue = "requested_points_value", requestedRequiresApproval = "requested_requires_approval", requestedRequiresPhoto = "requested_requires_photo", requestedFrequency = "requested_frequency", requestedIntervalValue = "requested_interval_value", requestedStartDate = "requested_start_date", requestedDueTime = "requested_due_time", requestedDurationMinutes = "requested_duration_minutes", requestedIsAllDay = "requested_is_all_day", requestedWeekdays = "requested_weekdays", requestedDayOfMonth = "requested_day_of_month", requestedMonthOfYear = "requested_month_of_year", requestedEndType = "requested_end_type", requestedEndsOn = "requested_ends_on", requestedOccurrenceCount = "requested_occurrence_count", requestedTimezone = "requested_timezone", requestedAssigneeIDs = "requested_assignee_ids"
    }
}
