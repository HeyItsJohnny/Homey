import SwiftUI
import Supabase
import UIKit

struct ChoreDetailView: View {
    let templateID: UUID
    let occurrenceID: UUID
    let home: HomeSummary
    let onSaveCompleted: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSession
    @State private var detail: PhoneChoreDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var showingEditor = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                        .font(.headline).padding(.horizontal, 20).frame(height: 46)
                        .background(.white.opacity(0.9), in: Capsule())
                }
            }
            .buttonStyle(.plain).foregroundStyle(HomeyColors.primary)
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail?.title ?? "Chore")
                            .font(ChoreDetailFont.scaled(24, weight: .bold, style: .title2, rounded: true))
                            .foregroundStyle(HomeyColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    if loading {
                        HStack { ProgressView(); Text("Loading your chore…") }
                            .frame(maxWidth: .infinity).padding(24).homeyCard()
                    } else if let error {
                        VStack(spacing: 12) {
                            HomeyErrorView(message: error)
                            Button("Try Again") { Task { await load() } }.buttonStyle(HomeyButtonStyle())
                        }.padding(20).homeyCard()
                    } else if let detail {
                        badgeRow(detail)
                        if let description = detail.description.phoneNilIfBlank {
                            textCard(label: "Description", text: description)
                        }
                        detailCard(detail, stacked: geometry.size.width < 390 || dynamicTypeSize.isAccessibilitySize)
                        if let instructions = detail.instructions.phoneNilIfBlank {
                            instructionsCard(instructions)
                        }
                        if !detail.canSafelyEdit {
                            HomeyErrorView(message: detail.legacyExplanation)
                        }
                    }
                    }.padding(.horizontal, 20).padding(.bottom, 28).frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }
        }
        .background(HomeyColors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(templateID)-\(occurrenceID)-\(home.id)") { await load() }
        .onChange(of: appSession.activeHome?.id) { _, id in if id != home.id { dismiss() } }
        .sheet(isPresented: $showingEditor, onDismiss: { Task { await load() } }) {
            if let detail {
                EditChoreView(home: home, initial: detail) {
                    await onSaveCompleted()
                }
            }
        }
    }

    private func badgeRow(_ detail: PhoneChoreDetail) -> some View {
        HStack(spacing: 10) {
            ChoreDetailBadge(symbol: "house.fill", text: detail.roomName,
                foreground: Color(red: 0.42, green: 0.45, blue: 0.62), background: Color(red: 0.92, green: 0.92, blue: 0.98))
            ChoreDetailBadge(symbol: "star.fill", text: "\(detail.pointsValue) \(detail.pointsValue == 1 ? "point" : "points")",
                foreground: Color(red: 0.96, green: 0.65, blue: 0.05), background: Color(red: 1.0, green: 0.95, blue: 0.82))
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func textCard(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(ChoreDetailFont.scaled(12, weight: .semibold, style: .caption1, rounded: true)).foregroundStyle(HomeyColors.secondaryText)
            Text(text).font(ChoreDetailFont.scaled(14, style: .body)).foregroundStyle(HomeyColors.text).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).choreDetailCard()
    }

    private func detailCard(_ detail: PhoneChoreDetail, stacked: Bool) -> some View {
        VStack(spacing: 0) {
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ChoreDetailFact(symbol: "person.fill", tint: .purple, label: "Assigned To",
                    value: detail.assigneeNames.isEmpty ? "Open Chore" : detail.assigneeNames.joined(separator: ", "))
                ChoreDetailFact(symbol: "dollarsign.circle.fill", tint: .green, label: "Points", value: "\(detail.pointsValue)")
            }
            Divider().opacity(0.55)
            layout {
                ChoreDetailFact(symbol: "calendar", tint: .blue, label: "Next Due", value: detail.nextDueDisplay, singleLineValue: true)
                ChoreDetailFact(symbol: "arrow.triangle.2.circlepath", tint: .pink, label: "Recurrence",
                    value: detail.recurrenceTitle, secondary: detail.recurrenceEndDescription)
            }
            Divider().opacity(0.55)
            ChoreDetailFact(symbol: "checkmark.circle", tint: .purple, label: "Requires Approval",
                value: detail.requiresApproval ? "Yes" : "No")
        }.padding(.horizontal, 15).choreDetailCard()
    }

    private func instructionsCard(_ instructions: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ChoreDetailIcon(symbol: "doc.text.fill", tint: .blue)
            VStack(alignment: .leading, spacing: 7) {
                Text("Instructions").font(ChoreDetailFont.scaled(12, weight: .semibold, style: .caption1, rounded: true)).foregroundStyle(HomeyColors.secondaryText)
                Text(instructions).font(ChoreDetailFont.scaled(14, style: .body)).foregroundStyle(HomeyColors.text).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(20).choreDetailCard()
    }

    private func load() async {
        loading = true; error = nil
        do {
            detail = try await service.load(templateID: templateID, occurrenceID: occurrenceID, homeID: home.id)
        } catch { self.error = "Unable to load this chore. Please try again." }
        loading = false
    }
}

private struct ChoreDetailBadge: View {
    let symbol: String
    let text: String
    let foreground: Color
    let background: Color
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(foreground)
            Text(text).foregroundStyle(HomeyColors.text)
        }
            .font(ChoreDetailFont.scaled(12, weight: .medium, style: .caption1, rounded: true))
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(background, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private struct ChoreDetailIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 35, height: 35).background(tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ChoreDetailFact: View {
    let symbol: String
    let tint: Color
    let label: String
    let value: String
    var secondary: String? = nil
    var singleLineValue = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChoreDetailIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(ChoreDetailFont.scaled(12, weight: .semibold, style: .caption1, rounded: true)).foregroundStyle(HomeyColors.secondaryText)
                Text(value)
                    .font(ChoreDetailFont.scaled(14, style: .body))
                    .foregroundStyle(HomeyColors.text)
                    .lineLimit(singleLineValue ? 1 : nil)
                    .minimumScaleFactor(singleLineValue ? 0.8 : 1)
                    .fixedSize(horizontal: false, vertical: !singleLineValue)
                if let secondary {
                    Text(secondary).font(ChoreDetailFont.scaled(12, style: .subheadline)).foregroundStyle(HomeyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func choreDetailCard() -> some View {
        background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private enum ChoreDetailFont {
    static func scaled(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular,
        style: UIFont.TextStyle,
        rounded: Bool = false
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let designed = rounded
            ? base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            : base
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: designed))
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
    var nextDueLocalDate: String?
    var rooms: [PhoneEditRoom]
    var members: [ChoreAssigneeOption]

    var canSafelyEdit: Bool { assignmentMode == "assigned" && assigneeIDs.count == 1 }
    var legacyExplanation: String {
        assignmentMode == "open"
            ? "This is a legacy Open chore. It can be viewed, but editing is disabled to preserve its assignment configuration."
            : "This chore has multiple or missing assignees. Editing is disabled to preserve its existing assignments."
    }
    var recurrenceTitle: String {
        if frequency == .none { return "One Time" }
        if intervalValue == 1 { return frequency.displayName }
        let unit: String
        switch frequency { case .daily: unit = "days"; case .weekly: unit = "weeks"; case .monthly: unit = "months"; case .yearly: unit = "years"; case .none: unit = "times" }
        return "Every \(intervalValue) \(unit)"
    }
    var recurrenceEndDescription: String? {
        if frequency == .none { return nil }
        switch endType {
        case .never: return "Never ends"
        case .onDate: return "Ends \(endsOn.map(displayDate) ?? "on date")"
        case .afterCount: return "Ends after \(occurrenceCount ?? 0) occurrences"
        }
    }
    var nextDueDisplay: String {
        guard let nextDueLocalDate else { return "No upcoming date" }
        let pieces = nextDueLocalDate.split(separator: "-")
        guard pieces.count == 3 else { return "No upcoming date" }
        return "\(pieces[1])/\(pieces[2])/\(pieces[0])"
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
private struct PhoneNextDueRow: Decodable { let dueLocalDate: String; enum CodingKeys: String, CodingKey { case dueLocalDate = "due_local_date" } }
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: recurrence.timezone) ?? .current
        let todayStart = calendar.startOfDay(for: Date())
        let nextRows: [PhoneNextDueRow] = try await client.from("chore_occurrences")
            .select("due_local_date")
            .eq("home_id", value: homeID.uuidString)
            .eq("template_id", value: templateID.uuidString)
            .eq("status", value: "not_started")
            .gte("due_at", value: ChoreCalendarDateFormatting.timestamp(todayStart))
            .order("due_at", ascending: true).limit(1).execute().value
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
            nextDueLocalDate: nextRows.first?.dueLocalDate,
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
