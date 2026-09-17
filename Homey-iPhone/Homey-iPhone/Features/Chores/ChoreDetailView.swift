import SwiftUI
import Supabase

struct ChoreDetailView: View {
    let templateID: UUID
    let occurrenceID: UUID
    let home: HomeSummary
    let onSaveCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSession
    @State private var detail: PhoneChoreDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var showingEditor = false
    private let service = PhoneChoreDetailService()

    private var canEdit: Bool { home.role == .owner || home.role == .admin }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Label("Chores", systemImage: "chevron.left").font(.headline).frame(minHeight: 44)
                }
                Spacer()
                if canEdit, detail != nil {
                    Button("Edit") { showingEditor = true }
                        .font(.headline).frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain).foregroundStyle(HomeyColors.primary)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(detail?.title ?? "Chore").font(HomeyTypography.hero)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("View and manage your chore details.")
                        .font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                    if loading {
                        HStack { ProgressView(); Text("Loading your chore…") }
                            .frame(maxWidth: .infinity).padding(24).homeyCard()
                    } else if let error {
                        VStack(spacing: 12) {
                            HomeyErrorView(message: error)
                            Button("Try Again") { Task { await load() } }.buttonStyle(HomeyButtonStyle())
                        }.padding(20).homeyCard()
                    } else if let detail {
                        detailCard(detail)
                        if !detail.canSafelyEdit {
                            HomeyErrorView(message: detail.legacyExplanation)
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: 640)
            }
        }
        .background(HomeyColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(templateID)-\(occurrenceID)-\(home.id)") { await load() }
        .onChange(of: appSession.activeHome?.id) { _, id in if id != home.id { dismiss() } }
        .sheet(isPresented: $showingEditor, onDismiss: { Task { await load() } }) {
            if let detail {
                EditChoreView(home: home, initial: detail) {
                    onSaveCompleted()
                }
            }
        }
    }

    private func detailCard(_ detail: PhoneChoreDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("Room", detail.roomName)
            if let value = detail.description.phoneNilIfBlank { detailRow("Description", value) }
            if let value = detail.instructions.phoneNilIfBlank { detailRow("Instructions", value) }
            detailRow("Assigned To", detail.assigneeNames.isEmpty ? "Open Chore" : detail.assigneeNames.joined(separator: ", "))
            detailRow("Points", "\(detail.pointsValue)")
            detailRow("Status", detail.status.displayName)
            detailRow("Schedule", detail.scheduleDescription)
            detailRow("Recurrence", detail.recurrenceDescription)
            detailRow("Start Date", detail.displayDate(detail.startDate))
            detailRow("Due Time", detail.isAllDay ? "All Day" : detail.dueTimeDisplay)
            detailRow("Approval", detail.requiresApproval ? "Required" : "Not Required")
            detailRow("Photo", detail.requiresPhoto ? "Required" : "Not Required")
            detailRow("Completion", detail.completionMode.displayName)
        }.homeyCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            Text(value).font(.body).foregroundStyle(HomeyColors.text).fixedSize(horizontal: false, vertical: true)
            Divider().padding(.top, 10)
        }.padding(.horizontal, 18).padding(.top, 14)
    }

    private func load() async {
        loading = true; error = nil
        do {
            detail = try await service.load(templateID: templateID, occurrenceID: occurrenceID, homeID: home.id)
        } catch { self.error = "Unable to load this chore. Please try again." }
        loading = false
    }
}

enum PhoneEditFrequency: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly
    var id: String { rawValue }
    var displayName: String { rawValue == "none" ? "One Time" : rawValue.capitalized }
}
enum PhoneEditEndType: String, Codable, CaseIterable, Identifiable {
    case never, onDate = "on_date", afterCount = "after_count"
    var id: String { rawValue }
    var displayName: String { self == .onDate ? "On Date" : self == .afterCount ? "After Count" : "Never" }
}
enum PhoneEditCompletionMode: String, Codable {
    case single, anyAssignee = "any_assignee", everyone
    var displayName: String { self == .anyAssignee ? "Any Assignee" : rawValue.capitalized }
}

extension PhoneChoreOccurrenceStatus {
    var displayName: String {
        switch self {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .awaitingApproval: "Pending Approval"
        case .completed: "Completed"
        case .needsRedo: "Needs Redo"
        case .skipped: "Skipped"
        case .cancelled: "Cancelled"
        }
    }
}

struct PhoneChoreDetail: Identifiable, Equatable {
    let id: UUID
    let occurrenceID: UUID
    let homeID: UUID
    var title: String
    var description: String
    var instructions: String
    var categoryID: UUID?
    var roomID: UUID?
    var roomName: String
    var assignmentMode: String
    var completionMode: PhoneEditCompletionMode
    var assigneeIDs: [UUID]
    var assigneeNames: [String]
    var pointsValue: Int
    var requiresApproval: Bool
    var requiresPhoto: Bool
    var contributesToRoomCleaning: Bool
    var frequency: PhoneEditFrequency
    var intervalValue: Int
    var startDate: Date
    var dueTime: String?
    var durationMinutes: Int
    var isAllDay: Bool
    var weekdays: Set<Int>
    var dayOfMonth: Int?
    var monthOfYear: Int?
    var endType: PhoneEditEndType
    var endsOn: Date?
    var occurrenceCount: Int?
    var timezone: String
    var status: PhoneChoreOccurrenceStatus
    var rooms: [PhoneEditRoom]
    var members: [ChoreAssigneeOption]

    var canSafelyEdit: Bool { assignmentMode == "assigned" && assigneeIDs.count == 1 }
    var legacyExplanation: String {
        assignmentMode == "open"
            ? "This is a legacy Open chore. It can be viewed, but editing is disabled to preserve its assignment configuration."
            : "This chore has multiple or missing assignees. Editing is disabled to preserve its existing assignments."
    }
    var recurrenceDescription: String {
        if frequency == .none { return "One Time" }
        let interval = intervalValue == 1 ? frequency.displayName : "Every \(intervalValue) \(frequency.rawValue.capitalized)s"
        switch endType {
        case .never: return "\(interval) • Never ends"
        case .onDate: return "\(interval) • Ends \(endsOn.map(displayDate) ?? "on date")"
        case .afterCount: return "\(interval) • \(occurrenceCount ?? 0) times"
        }
    }
    var scheduleDescription: String {
        frequency == .weekly && !weekdays.isEmpty
            ? weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0] }.joined(separator: ", ")
            : recurrenceDescription
    }
    var dueTimeDisplay: String {
        guard let dueTime else { return "Not Set" }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        guard let date = formatter.date(from: dueTime) else { return dueTime }
        formatter.timeStyle = .short; formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    func displayDate(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .omitted) }
}

struct PhoneEditRoom: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let roomType: String?
    var displayName: String { roomType == "other" || name.caseInsensitiveCompare("Other") == .orderedSame ? "General" : name }
    enum CodingKeys: String, CodingKey { case id, name; case roomType = "room_type" }
}

private struct PhoneTemplateDetailRow: Decodable {
    let id, homeID: UUID; let title: String; let description, instructions: String?; let categoryID, roomID: UUID?
    let assignmentMode: String; let completionMode: PhoneEditCompletionMode; let pointsValue: Int
    let requiresApproval, requiresPhoto: Bool; let contributesToRoomCleaning: Bool?
    enum CodingKeys: String, CodingKey {
        case id, title, description, instructions
        case homeID = "home_id", categoryID = "category_id", roomID = "room_id", assignmentMode = "assignment_mode"
        case completionMode = "completion_mode", pointsValue = "points_value", requiresApproval = "requires_approval"
        case requiresPhoto = "requires_photo", contributesToRoomCleaning = "contributes_to_room_cleaning"
    }
}
private struct PhoneRecurrenceRow: Decodable {
    let frequency: PhoneEditFrequency; let intervalValue: Int; let startDate: String; let dueTime: String?
    let durationMinutes: Int; let isAllDay: Bool; let weekdays: [Int]?; let dayOfMonth, monthOfYear: Int?
    let endType: PhoneEditEndType; let endsOn: String?; let occurrenceCount: Int?; let timezone: String
    enum CodingKeys: String, CodingKey {
        case frequency, weekdays, timezone
        case intervalValue = "interval_value", startDate = "start_date", dueTime = "due_time", durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day", dayOfMonth = "day_of_month", monthOfYear = "month_of_year"
        case endType = "end_type", endsOn = "ends_on", occurrenceCount = "occurrence_count"
    }
}
private struct PhoneTemplateAssigneeRow: Decodable { let userID: UUID; enum CodingKeys: String, CodingKey { case userID = "user_id" } }
private struct PhoneDetailMemberRow: Decodable {
    let userID: UUID; let firstName, lastName, displayName, email: String?
    var name: String { displayName?.phoneNilIfBlank ?? [firstName, lastName].compactMap { $0?.phoneNilIfBlank }.joined(separator: " ").phoneNilIfBlank ?? email?.split(separator: "@").first.map(String.init) ?? "Home Member" }
    enum CodingKeys: String, CodingKey { case userID = "user_id", firstName = "first_name", lastName = "last_name", displayName = "display_name", email }
}
private struct PhoneDetailOccurrenceRow: Decodable { let status: PhoneChoreOccurrenceStatus }
private struct PhoneDetailMembersParams: Encodable { let homeID: UUID; enum CodingKeys: String, CodingKey { case homeID = "target_home_id" } }

@MainActor
final class PhoneChoreDetailService {
    private let client = SupabaseManager.shared.client
    func load(templateID: UUID, occurrenceID: UUID, homeID: UUID) async throws -> PhoneChoreDetail {
        _ = try await client.auth.session
        let templates: [PhoneTemplateDetailRow] = try await client.from("chore_templates").select("id,home_id,title,description,instructions,category_id,room_id,assignment_mode,completion_mode,points_value,requires_approval,requires_photo,contributes_to_room_cleaning").eq("id", value: templateID.uuidString).eq("home_id", value: homeID.uuidString).limit(1).execute().value
        guard let template = templates.first else { throw ChoreCalendarInfrastructureError.repositoryOperationFailed }
        let recurrenceRows: [PhoneRecurrenceRow] = try await client.from("chore_recurrence_rules").select("frequency,interval_value,start_date,due_time,duration_minutes,is_all_day,weekdays,day_of_month,month_of_year,end_type,ends_on,occurrence_count,timezone").eq("template_id", value: templateID.uuidString).limit(1).execute().value
        guard let recurrence = recurrenceRows.first else { throw ChoreCalendarInfrastructureError.repositoryOperationFailed }
        let assignees: [PhoneTemplateAssigneeRow] = try await client.from("chore_template_assignees").select("user_id").eq("template_id", value: templateID.uuidString).execute().value
        let rooms: [PhoneEditRoom] = try await client.from("chore_rooms").select("id,name,room_type").eq("home_id", value: homeID.uuidString).order("sort_order").execute().value
        let members: [PhoneDetailMemberRow] = try await client.rpc("get_home_members", params: PhoneDetailMembersParams(homeID: homeID)).execute().value
        let occurrences: [PhoneDetailOccurrenceRow] = try await client.from("chore_occurrences").select("status").eq("id", value: occurrenceID.uuidString).eq("home_id", value: homeID.uuidString).limit(1).execute().value
        guard let occurrence = occurrences.first else { throw ChoreCalendarInfrastructureError.repositoryOperationFailed }
        let names = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.name) })
        return PhoneChoreDetail(id: template.id, occurrenceID: occurrenceID, homeID: template.homeID, title: template.title,
            description: template.description ?? "", instructions: template.instructions ?? "", categoryID: template.categoryID,
            roomID: template.roomID, roomName: rooms.first(where: { $0.id == template.roomID })?.displayName ?? "General",
            assignmentMode: template.assignmentMode, completionMode: template.completionMode, assigneeIDs: assignees.map(\.userID),
            assigneeNames: assignees.compactMap { names[$0.userID] }, pointsValue: template.pointsValue,
            requiresApproval: template.requiresApproval, requiresPhoto: template.requiresPhoto,
            contributesToRoomCleaning: template.contributesToRoomCleaning ?? false, frequency: recurrence.frequency,
            intervalValue: recurrence.intervalValue, startDate: Self.date(recurrence.startDate, timezone: recurrence.timezone),
            dueTime: recurrence.dueTime, durationMinutes: recurrence.durationMinutes, isAllDay: recurrence.isAllDay,
            weekdays: Set(recurrence.weekdays ?? []), dayOfMonth: recurrence.dayOfMonth, monthOfYear: recurrence.monthOfYear,
            endType: recurrence.endType, endsOn: recurrence.endsOn.map { Self.date($0, timezone: recurrence.timezone) },
            occurrenceCount: recurrence.occurrenceCount, timezone: recurrence.timezone, status: occurrence.status,
            rooms: rooms, members: members.map { ChoreAssigneeOption(id: $0.userID, name: $0.name) })
    }
    private static func date(_ value: String, timezone: String) -> Date {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: timezone) ?? .current; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: value) ?? Date()
    }
}

extension String {
    var phoneNilIfBlank: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
}
