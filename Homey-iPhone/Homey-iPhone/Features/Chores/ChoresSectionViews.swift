import SwiftUI
import Supabase
import Combine

struct ChoresMainView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var model = PhoneChoresViewModel()

    var body: some View {
        Group {
            if model.isLoading && model.rooms.isEmpty {
                ProgressView("Loading chores…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage, model.rooms.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        HomeyErrorView(message: error)
                        Button("Try Again") { Task { await load() } }.buttonStyle(HomeyButtonStyle())
                    }.padding(20).homeyCard().padding()
                }
            } else if model.rooms.isEmpty {
                ChorePlaceholderView(title: "No rooms yet", message: "Use Add Room and Chores to set up your first room.", symbol: "door.left.hand.open")
            } else {
                List {
                    ForEach(model.rooms) { room in
                        Section {
                            let chores = model.chores(for: room.id)
                            if chores.isEmpty {
                                Text("No chores in this room")
                                    .font(.subheadline)
                                    .foregroundStyle(HomeyColors.secondaryText)
                            }
                            ForEach(chores) { chore in
                                PhoneRoomChoreRow(
                                    chore: chore,
                                    isProcessing: model.processingOccurrenceIDs.contains(chore.occurrence.id)
                                )
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if chore.canSubmit(currentUserID: appSession.currentUser?.id) {
                                        Button {
                                            Task { await model.submit(chore) }
                                        } label: {
                                            Label("Submit", systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(HomeyColors.primary)
                                        .disabled(model.processingOccurrenceIDs.contains(chore.occurrence.id))
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if chore.canSkip(currentUserID: appSession.currentUser?.id) {
                                        Button(role: .destructive) {
                                            Task { await model.skip(chore) }
                                        } label: {
                                            Label("Skip", systemImage: "forward.end.fill")
                                        }
                                        .disabled(model.processingOccurrenceIDs.contains(chore.occurrence.id))
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(room.name)
                                        .font(HomeyTypography.headline)
                                        .foregroundStyle(HomeyColors.text)
                                    Text(room.detail)
                                        .font(.caption)
                                        .foregroundStyle(HomeyColors.secondaryText)
                                }
                                Spacer()
                                Text("\(model.chores(for: room.id).count)")
                                    .font(.headline)
                                    .foregroundStyle(HomeyColors.primary)
                            }
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(HomeyColors.background)
                .refreshable { await load() }
            }
        }
        .task(id: loadTaskID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyChoresDidChange"))) { _ in Task { await load() } }
        .alert("Unable to Update Chore", isPresented: Binding(
            get: { model.actionErrorMessage != nil },
            set: { if !$0 { model.actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionErrorMessage = nil }
        } message: {
            Text(model.actionErrorMessage ?? "Please try again.")
        }
    }

    private var loadTaskID: String {
        "\(appSession.activeHome?.id.uuidString ?? "no-home")-\(appSession.currentUser?.id.uuidString ?? "no-user")-\(appSession.activeRole?.rawValue ?? "no-role")"
    }

    private func load() async {
        await model.load(
            homeID: appSession.activeHome?.id,
            currentUserID: appSession.currentUser?.id,
            role: appSession.activeRole
        )
    }
}

private struct PhoneChoreRoom: Decodable, Identifiable {
    let id: UUID
    let name: String
    let roomType: String?
    let preferredCleaningWeekday: Int?
    var detail: String {
        let type = (roomType ?? "other").replacingOccurrences(of: "_", with: " ").capitalized
        guard let weekday = preferredCleaningWeekday, (1...7).contains(weekday) else { return type }
        return "\(type) • \(Calendar.current.weekdaySymbols[weekday - 1])"
    }
    enum CodingKeys: String, CodingKey { case id, name, roomType = "room_type", preferredCleaningWeekday = "preferred_cleaning_weekday" }
}

private struct PhoneChoreTemplate: Decodable, Identifiable {
    let id: UUID
    let roomID: UUID?
    let title: String
    let description: String?
    let instructions: String?
    let pointsValue: Int
    enum CodingKeys: String, CodingKey {
        case id, title, description, instructions
        case roomID = "room_id"
        case pointsValue = "points_value"
    }
}

private enum PhoneChoreAssignmentMode: String, Decodable { case assigned, open }
private enum PhoneChoreOccurrenceStatus: String, Decodable {
    case notStarted = "not_started", inProgress = "in_progress", awaitingApproval = "awaiting_approval"
    case completed, needsRedo = "needs_redo", skipped, cancelled
}
private enum PhoneChoreAssigneeStatus: String, Decodable {
    case assigned, inProgress = "in_progress", awaitingApproval = "awaiting_approval"
    case completed, needsRedo = "needs_redo", skipped, cancelled
}

private struct PhoneChoreOccurrence: Decodable, Identifiable {
    let id: UUID
    let templateID: UUID
    let assignmentMode: PhoneChoreAssignmentMode
    let pointsValue: Int
    let requiresApproval: Bool
    let dueLocalDate: String
    let status: PhoneChoreOccurrenceStatus
    let claimedBy: UUID?
    enum CodingKeys: String, CodingKey {
        case id, status
        case templateID = "template_id"
        case assignmentMode = "assignment_mode"
        case pointsValue = "points_value_snapshot"
        case requiresApproval = "requires_approval_snapshot"
        case dueLocalDate = "due_local_date"
        case claimedBy = "claimed_by"
    }
}

private struct PhoneOccurrenceAssignee: Decodable {
    let occurrenceID: UUID
    let userID: UUID
    let status: PhoneChoreAssigneeStatus
    enum CodingKeys: String, CodingKey {
        case occurrenceID = "occurrence_id"
        case userID = "user_id"
        case status
    }
}

private struct PhoneChoreMember: Decodable {
    let userID: UUID
    let firstName: String?
    let lastName: String?
    let profileDisplayName: String?
    let email: String?
    var displayName: String {
        let preferred = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }
        let fullName = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return email?.split(separator: "@").first.map(String.init) ?? "Home Member"
    }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case profileDisplayName = "display_name"
        case email
    }
}

private struct PhoneRoomChore: Identifiable {
    let template: PhoneChoreTemplate
    let occurrence: PhoneChoreOccurrence
    let assignees: [PhoneOccurrenceAssignee]
    let assigneeText: String
    let roomName: String
    var id: UUID { template.id }
    var title: String { template.title }
    var pointsValue: Int { occurrence.pointsValue }
}

private struct PhoneRoomChoreRow: View {
    let chore: PhoneRoomChore
    let isProcessing: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: chore.statusSymbol)
                        .foregroundStyle(chore.statusColor)
                }
            }
            .frame(width: 20, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chore.title).font(.body).foregroundStyle(HomeyColors.text).lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(chore.pointsValue) pts").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(chore.assigneeText).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Due: \(chore.occurrence.dueLocalDate.phoneDueDate)")
                }
                .font(.caption)
                .foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .opacity(isProcessing ? 0.65 : 1)
    }
}

private extension PhoneRoomChore {
    func canSubmit(currentUserID: UUID?) -> Bool {
        guard let currentUserID else { return false }
        if occurrence.assignmentMode == .open {
            return occurrence.claimedBy == currentUserID
                && occurrence.status != .awaitingApproval
        }
        guard let status = assignees.first(where: { $0.userID == currentUserID })?.status else { return false }
        return status == .assigned || status == .inProgress || status == .needsRedo
    }

    func canSkip(currentUserID: UUID?) -> Bool {
        guard let currentUserID else { return false }
        if occurrence.assignmentMode == .open {
            return occurrence.claimedBy == currentUserID && occurrence.status == .notStarted
        }
        return assignees.first(where: { $0.userID == currentUserID })?.status == .assigned
    }

    var statusSymbol: String {
        switch occurrence.status {
        case .inProgress: "circle.lefthalf.filled"
        case .awaitingApproval: "clock.fill"
        case .completed: "checkmark.circle.fill"
        case .needsRedo: "arrow.counterclockwise.circle.fill"
        case .skipped, .cancelled: "minus.circle.fill"
        case .notStarted: "circle"
        }
    }
    var statusColor: Color {
        switch occurrence.status {
        case .awaitingApproval: .yellow
        case .completed: HomeyColors.success
        case .needsRedo: HomeyColors.danger
        case .skipped, .cancelled: HomeyColors.secondaryText
        case .notStarted, .inProgress: HomeyColors.primary
        }
    }
}

private extension String {
    var phoneDueDate: String {
        let pieces = split(separator: "-")
        guard pieces.count == 3 else { return self }
        return "\(pieces[1])/\(pieces[2])/\(pieces[0])"
    }
}

private struct PhoneGetChoreMembersParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "target_home_id" }
}

private struct PhoneOccurrenceActionParameters: Encodable {
    let occurrenceID: UUID
    enum CodingKeys: String, CodingKey { case occurrenceID = "requested_occurrence_id" }
}

private struct PhoneSubmitChoreParameters: Encodable {
    let occurrenceID: UUID
    let note: String?
    let photoPath: String? = nil
    enum CodingKeys: String, CodingKey {
        case occurrenceID = "requested_occurrence_id"
        case note = "requested_completion_note"
        case photoPath = "requested_photo_path"
    }

    // PostgREST resolves the RPC from the complete set of JSON keys. Match the
    // working iPad encoder by preserving nullable arguments as explicit nulls.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(occurrenceID, forKey: .occurrenceID)
        if let note {
            try container.encode(note, forKey: .note)
        } else {
            try container.encodeNil(forKey: .note)
        }
        if let photoPath {
            try container.encode(photoPath, forKey: .photoPath)
        } else {
            try container.encodeNil(forKey: .photoPath)
        }
    }
}

private struct PhoneChoreActionRepository {
    private let client = SupabaseManager.shared.client

    func claim(occurrenceID: UUID) async throws {
        try await client.rpc(
            "claim_open_chore",
            params: PhoneOccurrenceActionParameters(occurrenceID: occurrenceID)
        ).execute()
    }

    func submit(occurrenceID: UUID, note: String?) async throws {
        let _: UUID = try await client.rpc(
            "submit_chore",
            params: PhoneSubmitChoreParameters(occurrenceID: occurrenceID, note: note)
        ).execute().value
    }

    func skip(occurrenceID: UUID) async throws {
        let _: UUID = try await client.rpc(
            "skip_chore",
            params: PhoneOccurrenceActionParameters(occurrenceID: occurrenceID)
        ).execute().value
    }
}

@MainActor
private final class PhoneChoresViewModel: ObservableObject {
    @Published var rooms: [PhoneChoreRoom] = []
    @Published var roomChores: [PhoneRoomChore] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var actionErrorMessage: String?
    @Published private(set) var processingOccurrenceIDs: Set<UUID> = []
    private let client = SupabaseManager.shared.client
    private let actionRepository = PhoneChoreActionRepository()
    private var activeHomeID: UUID?
    private var activeCurrentUserID: UUID?
    private var activeRole: HomeMemberRole?
    private var activeLoadID = UUID()

    func chores(for roomID: UUID) -> [PhoneRoomChore] {
        roomChores
            .filter { $0.template.roomID == roomID }
            .sorted {
                if $0.occurrence.dueLocalDate == $1.occurrence.dueLocalDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.occurrence.dueLocalDate < $1.occurrence.dueLocalDate
            }
    }

    func submit(_ chore: PhoneRoomChore) async {
        await performAction(for: chore) {
            try await actionRepository.submit(occurrenceID: chore.occurrence.id, note: nil)
        }
    }

    func skip(_ chore: PhoneRoomChore) async {
        await performAction(for: chore) {
            try await actionRepository.skip(occurrenceID: chore.occurrence.id)
        }
    }

    private func performAction(
        for chore: PhoneRoomChore,
        action: () async throws -> Void
    ) async {
        guard !processingOccurrenceIDs.contains(chore.occurrence.id) else { return }
        processingOccurrenceIDs.insert(chore.occurrence.id)
        actionErrorMessage = nil
        defer { processingOccurrenceIDs.remove(chore.occurrence.id) }

        do {
            try await action()
            await load(homeID: activeHomeID, currentUserID: activeCurrentUserID, role: activeRole)
        } catch {
            actionErrorMessage = "We couldn't update this chore. Please try again."
            #if DEBUG
            print("[Homey] CHORE ACTION ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    func load(homeID: UUID?, currentUserID: UUID?, role: HomeMemberRole?) async {
        let loadID = UUID()
        activeLoadID = loadID
        if activeHomeID != homeID {
            rooms = []
            roomChores = []
            processingOccurrenceIDs = []
        }
        activeHomeID = homeID
        activeCurrentUserID = currentUserID
        activeRole = role

        guard let homeID else { rooms = []; roomChores = []; return }
        isLoading = true; errorMessage = nil
        defer {
            if activeLoadID == loadID { isLoading = false }
        }
        do {
            // Match the working iPad ChoresRepository.fetchRooms contract and
            // query only the deployed room fields this screen displays.
            let loadedRooms: [PhoneChoreRoom] = try await client
                .from("chore_rooms")
                .select("id,name,room_type,preferred_cleaning_weekday")
                .eq("home_id", value: homeID.uuidString)
                .order("sort_order")
                .execute()
                .value
            // Match ChoresRepository.fetchTemplates: the deployed relation is
            // queried by home and ordered without a server-side archive filter.
            let loadedTemplates: [PhoneChoreTemplate] = try await client
                .from("chore_templates")
                .select("id,room_id,title,description,instructions,points_value")
                .eq("home_id", value: homeID.uuidString)
                .order("title")
                .execute()
                .value
            let occurrences: [PhoneChoreOccurrence] = try await client
                .from("chore_occurrences")
                .select("id,template_id,assignment_mode,points_value_snapshot,requires_approval_snapshot,due_local_date,status,claimed_by")
                .eq("home_id", value: homeID.uuidString)
                .in("status", values: ["not_started", "in_progress", "awaiting_approval", "needs_redo"])
                .order("due_at", ascending: true)
                .execute()
                .value

            var firstOccurrenceByTemplate: [UUID: PhoneChoreOccurrence] = [:]
            for occurrence in occurrences where firstOccurrenceByTemplate[occurrence.templateID] == nil {
                firstOccurrenceByTemplate[occurrence.templateID] = occurrence
            }
            let selectedOccurrences = Array(firstOccurrenceByTemplate.values)
            let occurrenceIDs = selectedOccurrences.map { $0.id.uuidString }
            let loadedAssignees: [PhoneOccurrenceAssignee]
            if occurrenceIDs.isEmpty {
                loadedAssignees = []
            } else {
                loadedAssignees = try await client
                    .from("chore_occurrence_assignees")
                    .select("occurrence_id,user_id,status")
                    .in("occurrence_id", values: occurrenceIDs)
                    .execute()
                    .value
            }
            let members: [PhoneChoreMember] = try await client
                .rpc("get_home_members", params: PhoneGetChoreMembersParameters(homeID: homeID))
                .execute()
                .value
            let namesByUserID = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.displayName) })
            let templatesByID = Dictionary(uniqueKeysWithValues: loadedTemplates.map { ($0.id, $0) })
            let roomNamesByID = Dictionary(uniqueKeysWithValues: loadedRooms.map { ($0.id, $0.name) })

            guard activeLoadID == loadID else { return }
            let householdChores: [PhoneRoomChore] = selectedOccurrences.compactMap { occurrence in
                guard let template = templatesByID[occurrence.templateID] else { return nil }
                let assignees = loadedAssignees.filter { $0.occurrenceID == occurrence.id }
                let assigneeText: String
                if occurrence.assignmentMode == .open {
                    assigneeText = occurrence.claimedBy.flatMap { namesByUserID[$0] }.map { "Claimed by \($0)" } ?? "Open Chore"
                } else {
                    let names = assignees.compactMap { namesByUserID[$0.userID] }
                    assigneeText = names.isEmpty ? "Assigned" : names.joined(separator: ", ")
                }
                return PhoneRoomChore(
                    template: template,
                    occurrence: occurrence,
                    assignees: assignees,
                    assigneeText: assigneeText,
                    roomName: template.roomID.flatMap { roomNamesByID[$0] } ?? "No Room"
                )
            }
            let canViewAllChores = role == .owner || role == .admin
            let visibleChores = householdChores.filter { chore in
                if canViewAllChores { return true }
                guard let currentUserID else { return false }
                if chore.occurrence.assignmentMode == PhoneChoreAssignmentMode.open {
                    return chore.occurrence.claimedBy == nil || chore.occurrence.claimedBy == currentUserID
                }
                return chore.assignees.contains { $0.userID == currentUserID }
            }
            let visibleRoomIDs = Set(visibleChores.compactMap { $0.template.roomID })
            roomChores = visibleChores
            rooms = loadedRooms.filter { visibleRoomIDs.contains($0.id) }
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = "We couldn't load your rooms and chores."
            #if DEBUG
            print("[Homey] LOAD PHONE CHORES: \(String(reflecting: error))")
            #endif
        }
    }
}

private struct PhoneChoreActionSheet: View {
    let chore: PhoneRoomChore
    let currentUserID: UUID?
    let onSuccess: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var completionNote = ""
    @State private var activeAction: PhoneChoreSheetAction?
    @State private var errorMessage: String?
    @State private var confirmingSkip = false
    private let actionRepository = PhoneChoreActionRepository()

    var body: some View {
        ZStack {
            Color(red: 0.985, green: 0.975, blue: 0.955).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero

                    if let detailText {
                        Text(detailText)
                            .font(.body)
                            .foregroundStyle(HomeyColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    summaryGrid

                    if canSubmit {
                        completionSection

                        if chore.occurrence.requiresApproval {
                            approvalCallout
                        }

                        primaryActionButton

                        if canSkip { skipButton }
                    } else if canClaim {
                        claimButton
                    } else {
                        statusCard
                    }

                    if let errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(errorMessage)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HomeyColors.danger)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HomeyColors.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(activeAction != nil)
        .confirmationDialog("Skip Chore?", isPresented: $confirmingSkip, titleVisibility: .visible) {
            Button("Skip Chore", role: .destructive) { Task { await skip() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to skip “\(chore.title)”? This will update the current occurrence.")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(HomeyColors.primary)
                .frame(width: 68, height: 68)
                .background(HomeyColors.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(HomeyColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(chore.roomName)
                    .font(.title3)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
            .padding(.top, 4)

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyColors.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(activeAction != nil)
            .accessibilityLabel("Close")
        }
    }

    private var detailText: String? {
        let candidates = [chore.template.description, chore.template.instructions]
        return candidates.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
            PhoneChoreSummaryItem(symbol: "house.fill", label: "Room", value: chore.roomName)
            PhoneChoreSummaryItem(symbol: "person.2.fill", label: "Assigned", value: chore.assigneeText)
            PhoneChoreSummaryItem(symbol: "calendar", label: "Due Date", value: chore.occurrence.dueLocalDate.phoneDueDate)
            PhoneChoreSummaryItem(symbol: "star.fill", label: "Points", value: "\(chore.pointsValue)")
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion")
                .font(.title2.bold())
                .foregroundStyle(HomeyColors.text)

            ZStack(alignment: .topLeading) {
                if completionNote.isEmpty {
                    Text("Add a note (optional)\n\nE.g. Finished the whole room, looks great!")
                        .font(.body)
                        .foregroundStyle(HomeyColors.secondaryText.opacity(0.65))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $completionNote)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 142)
                    .onChange(of: completionNote) { _, newValue in
                        if newValue.count > 500 {
                            completionNote = String(newValue.prefix(500))
                        }
                    }

                Text("\(completionNote.count)/500")
                    .font(.caption)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeyColors.border.opacity(0.75), lineWidth: 1)
            }
        }
    }

    private var approvalCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(HomeyColors.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("This chore requires approval")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyColors.text)
                Text("An owner or admin will review your submission before the chore is considered complete.")
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyColors.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var primaryActionButton: some View {
        Button { Task { await submit() } } label: {
            PhoneChoreActionLabel(
                symbol: "checkmark.circle.fill",
                title: chore.occurrence.requiresApproval ? "Submit for Approval" : "Complete Chore",
                subtitle: chore.occurrence.requiresApproval ? "Send this chore for review" : "Mark this chore as completed",
                isLoading: activeAction == .submitting,
                loadingTitle: "Submitting…"
            )
        }
        .buttonStyle(PhoneChorePrimaryButtonStyle())
        .disabled(activeAction != nil)
    }

    private var skipButton: some View {
        Button { confirmingSkip = true } label: {
            PhoneChoreActionLabel(
                symbol: "forward.end.fill",
                title: "Skip Chore",
                subtitle: "Mark this chore as skipped",
                isLoading: activeAction == .skipping,
                loadingTitle: "Skipping…"
            )
        }
        .buttonStyle(PhoneChoreDestructiveButtonStyle())
        .disabled(activeAction != nil)
    }

    private var claimButton: some View {
        Button { Task { await claim() } } label: {
            PhoneChoreActionLabel(
                symbol: "hand.raised.fill",
                title: "Claim Chore",
                subtitle: "Take responsibility for this open chore",
                isLoading: activeAction == .claiming,
                loadingTitle: "Claiming…"
            )
        }
        .buttonStyle(PhoneChorePrimaryButtonStyle())
        .disabled(activeAction != nil)
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isAwaitingApproval ? "clock.fill" : "info.circle.fill")
                .foregroundStyle(isAwaitingApproval ? Color.yellow : HomeyColors.primary)
            Text(statusMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(HomeyColors.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var myAssignee: PhoneOccurrenceAssignee? {
        guard let currentUserID else { return nil }
        return chore.assignees.first { $0.userID == currentUserID }
    }
    private var canClaim: Bool {
        chore.occurrence.assignmentMode == .open && chore.occurrence.claimedBy == nil && currentUserID != nil
    }
    private var canSubmit: Bool {
        guard let currentUserID else { return false }
        if chore.occurrence.assignmentMode == .open { return chore.occurrence.claimedBy == currentUserID }
        guard let status = myAssignee?.status else { return false }
        return status == .assigned || status == .inProgress || status == .needsRedo
    }
    private var canSkip: Bool {
        if chore.occurrence.assignmentMode == .open {
            return chore.occurrence.claimedBy == currentUserID && chore.occurrence.status == .notStarted
        }
        return myAssignee?.status == .assigned
    }
    private var statusMessage: String {
        if isAwaitingApproval { return "This chore is awaiting approval." }
        return "You can view this chore, but there are no actions available for your account."
    }
    private var isAwaitingApproval: Bool {
        chore.occurrence.status == .awaitingApproval || myAssignee?.status == .awaitingApproval
    }

    private func claim() async {
        await perform(.claiming) {
            try await actionRepository.claim(occurrenceID: chore.occurrence.id)
        }
    }
    private func submit() async {
        await perform(.submitting) {
            let note = completionNote.trimmingCharacters(in: .whitespacesAndNewlines)
            try await actionRepository.submit(
                occurrenceID: chore.occurrence.id,
                note: note.isEmpty ? nil : note
            )
        }
    }
    private func skip() async {
        await perform(.skipping) {
            try await actionRepository.skip(occurrenceID: chore.occurrence.id)
        }
    }
    private func perform(_ actionType: PhoneChoreSheetAction, _ action: () async throws -> Void) async {
        guard activeAction == nil else { return }
        activeAction = actionType
        errorMessage = nil
        defer { activeAction = nil }
        do {
            try await action()
            dismiss()
            await onSuccess()
        } catch {
            errorMessage = "We couldn't update this chore. Please try again."
            #if DEBUG
            print("[Homey] CHORE ACTION ERROR: \(String(reflecting: error))")
            #endif
        }
    }
}

private enum PhoneChoreSheetAction {
    case claiming
    case submitting
    case skipping
}

private struct PhoneChoreSummaryItem: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(HomeyColors.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(HomeyColors.secondaryText)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyColors.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PhoneChoreActionLabel: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isLoading: Bool
    let loadingTitle: String

    var body: some View {
        HStack(spacing: 14) {
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isLoading ? loadingTitle : title)
                    .font(.headline)
                if !isLoading {
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.82)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .contentShape(Rectangle())
    }
}

private struct PhoneChorePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .background(HomeyColors.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct PhoneChoreDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(HomeyColors.danger)
            .padding(.horizontal, 20)
            .background(HomeyColors.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeyColors.danger.opacity(0.75), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ChoreApprovalsView: View {
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var model = PhoneChoreApprovalsViewModel()

    var body: some View {
        Group {
            if !canReviewChores {
                ChorePlaceholderView(
                    title: "Approvals",
                    message: "Only Home owners and admins can review chore submissions.",
                    symbol: "lock.shield"
                )
            } else if model.isLoading && model.rooms.isEmpty {
                ProgressView("Loading approvals…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage, model.rooms.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        HomeyErrorView(message: errorMessage)
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(HomeyButtonStyle())
                    }
                    .padding(20)
                    .homeyCard()
                    .padding()
                }
            } else if model.rooms.isEmpty {
                ChorePlaceholderView(
                    title: "All caught up",
                    message: "No chores are waiting for approval.",
                    symbol: "checkmark.circle.fill"
                )
            } else {
                List {
                    ForEach(model.rooms) { room in
                        Section {
                            ForEach(model.approvals(for: room.id)) { approval in
                                PhoneChoreApprovalRow(
                                    approval: approval,
                                    isProcessing: model.processingSubmissionIDs.contains(approval.id)
                                )
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        Task { await model.review(approval, decision: .approved) }
                                    } label: {
                                        Label("Approve", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(HomeyColors.success)
                                    .disabled(model.processingSubmissionIDs.contains(approval.id))
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await model.review(approval, decision: .needsRedo) }
                                    } label: {
                                        Label("Redo", systemImage: "arrow.counterclockwise")
                                    }
                                    .disabled(model.processingSubmissionIDs.contains(approval.id))
                                }
                            }
                        } header: {
                            HStack {
                                Text(room.name)
                                    .font(HomeyTypography.headline)
                                    .foregroundStyle(HomeyColors.text)
                                Spacer()
                                Text("\(model.approvals(for: room.id).count)")
                                    .font(.headline)
                                    .foregroundStyle(HomeyColors.primary)
                            }
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(HomeyColors.background)
                .refreshable { await load() }
            }
        }
        .task(id: loadTaskID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyChoresDidChange"))) { notification in
            guard notification.object as? PhoneChoreApprovalsViewModel !== model else { return }
            Task { await load() }
        }
        .alert("Unable to Review Chore", isPresented: Binding(
            get: { model.actionErrorMessage != nil },
            set: { if !$0 { model.actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionErrorMessage = nil }
        } message: {
            Text(model.actionErrorMessage ?? "Please try again.")
        }
    }

    private var canReviewChores: Bool {
        appSession.activeRole == .owner || appSession.activeRole == .admin
    }

    private var loadTaskID: String {
        "\(appSession.activeHome?.id.uuidString ?? "no-home")-\(appSession.currentUser?.id.uuidString ?? "no-user")-\(appSession.activeRole?.rawValue ?? "no-role")"
    }

    private func load() async {
        await model.load(homeID: appSession.activeHome?.id, role: appSession.activeRole)
    }
}

private enum PhoneChoreApprovalDecision: String {
    case approved
    case needsRedo = "needs_redo"
}

private struct PhonePendingSubmission: Decodable, Identifiable {
    let id: UUID
    let occurrenceID: UUID
    let submittedBy: UUID
    let submittedAt: Date
    enum CodingKeys: String, CodingKey {
        case id
        case occurrenceID = "occurrence_id"
        case submittedBy = "submitted_by"
        case submittedAt = "submitted_at"
    }
}

private struct PhoneApprovalOccurrence: Decodable, Identifiable {
    let id: UUID
    let title: String
    let roomID: UUID?
    let pointsValue: Int
    let dueLocalDate: String
    enum CodingKeys: String, CodingKey {
        case id
        case title = "title_snapshot"
        case roomID = "room_id_snapshot"
        case pointsValue = "points_value_snapshot"
        case dueLocalDate = "due_local_date"
    }
}

private struct PhoneChoreApprovalItem: Identifiable {
    let submission: PhonePendingSubmission
    let occurrence: PhoneApprovalOccurrence
    let roomName: String
    let memberName: String
    var id: UUID { submission.id }
    var roomGroupID: UUID { occurrence.roomID ?? PhoneChoreApprovalsViewModel.otherRoomID }
}

private struct PhoneReviewSubmissionParameters: Encodable {
    let submissionID: UUID
    let decision: String
    let adminNote: String?
    let pointsAwarded: Int?
    enum CodingKeys: String, CodingKey {
        case submissionID = "requested_submission_id"
        case decision = "requested_decision"
        case adminNote = "requested_admin_note"
        case pointsAwarded = "requested_points_awarded"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(submissionID, forKey: .submissionID)
        try container.encode(decision, forKey: .decision)
        try container.encodeNil(forKey: .adminNote)
        if let pointsAwarded {
            try container.encode(pointsAwarded, forKey: .pointsAwarded)
        } else {
            try container.encodeNil(forKey: .pointsAwarded)
        }
    }
}

private struct PhoneChoreApprovalRepository {
    private let client = SupabaseManager.shared.client

    func review(submissionID: UUID, decision: PhoneChoreApprovalDecision, pointsAwarded: Int) async throws {
        try await client.rpc(
            "review_chore_submission",
            params: PhoneReviewSubmissionParameters(
                submissionID: submissionID,
                decision: decision.rawValue,
                adminNote: nil,
                pointsAwarded: pointsAwarded
            )
        ).execute()
    }
}

private struct PhoneChoreApprovalRow: View {
    let approval: PhoneChoreApprovalItem
    let isProcessing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Color.yellow)
                }
            }
            .frame(width: 20, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(approval.occurrence.title)
                        .font(.body)
                        .foregroundStyle(HomeyColors.text)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(approval.occurrence.pointsValue) pts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyColors.secondaryText)
                }

                Text("Pending Approval")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)

                Text(approval.memberName)
                    .font(.caption)
                    .foregroundStyle(HomeyColors.secondaryText)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Due: \(approval.occurrence.dueLocalDate.phoneDueDate)")
                        Spacer(minLength: 8)
                        Text("Submitted: \(approval.submission.submittedAt.phoneApprovalTimestamp)")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Due: \(approval.occurrence.dueLocalDate.phoneDueDate)")
                        Text("Submitted: \(approval.submission.submittedAt.phoneApprovalTimestamp)")
                    }
                }
                .font(.caption)
                .foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .opacity(isProcessing ? 0.65 : 1)
    }
}

private extension Date {
    var phoneApprovalTimestamp: String {
        formatted(
            .dateTime
                .month(.twoDigits)
                .day(.twoDigits)
                .year()
                .hour()
                .minute()
        )
    }
}

@MainActor
private final class PhoneChoreApprovalsViewModel: ObservableObject {
    static let otherRoomID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @Published private(set) var approvals: [PhoneChoreApprovalItem] = []
    @Published private(set) var rooms: [PhoneChoreRoom] = []
    @Published private(set) var isLoading = false
    @Published private(set) var processingSubmissionIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?
    @Published var actionErrorMessage: String?

    private let client = SupabaseManager.shared.client
    private let actionRepository = PhoneChoreApprovalRepository()
    private var activeHomeID: UUID?
    private var activeRole: HomeMemberRole?
    private var activeLoadID = UUID()

    func approvals(for roomID: UUID) -> [PhoneChoreApprovalItem] {
        approvals.filter { $0.roomGroupID == roomID }
    }

    func load(homeID: UUID?, role: HomeMemberRole?) async {
        let loadID = UUID()
        activeLoadID = loadID
        if activeHomeID != homeID || activeRole != role {
            approvals = []
            rooms = []
            processingSubmissionIDs = []
        }
        activeHomeID = homeID
        activeRole = role

        guard let homeID, role == .owner || role == .admin else {
            approvals = []
            rooms = []
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadID == loadID { isLoading = false }
        }

        do {
            let occurrences: [PhoneApprovalOccurrence] = try await client
                .from("chore_occurrences")
                .select("id,title_snapshot,room_id_snapshot,points_value_snapshot,due_local_date")
                .eq("home_id", value: homeID.uuidString)
                .eq("status", value: "awaiting_approval")
                .order("due_at", ascending: true)
                .execute()
                .value

            let occurrenceIDs = occurrences.map { $0.id.uuidString }
            guard !occurrenceIDs.isEmpty else {
                guard activeLoadID == loadID else { return }
                approvals = []
                rooms = []
                return
            }

            async let submissionsRequest: [PhonePendingSubmission] = client
                .from("chore_submissions")
                .select("id,occurrence_id,submitted_by,submitted_at")
                .in("occurrence_id", values: occurrenceIDs)
                .eq("status", value: "pending")
                .order("submitted_at", ascending: true)
                .execute()
                .value
            async let assigneesRequest: [PhoneOccurrenceAssignee] = client
                .from("chore_occurrence_assignees")
                .select("occurrence_id,user_id,status")
                .in("occurrence_id", values: occurrenceIDs)
                .execute()
                .value
            async let roomsRequest: [PhoneChoreRoom] = client
                .from("chore_rooms")
                .select("id,name,room_type,preferred_cleaning_weekday")
                .eq("home_id", value: homeID.uuidString)
                .order("sort_order")
                .execute()
                .value
            let members: [PhoneChoreMember] = try await client
                .rpc("get_home_members", params: PhoneGetChoreMembersParameters(homeID: homeID))
                .execute()
                .value

            let (submissions, assignees, loadedRooms) = try await (
                submissionsRequest,
                assigneesRequest,
                roomsRequest
            )
            guard activeLoadID == loadID else { return }

            let occurrencesByID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
            let roomsByID = Dictionary(uniqueKeysWithValues: loadedRooms.map { ($0.id, $0) })
            let namesByUserID = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.displayName) })
            let awaitingKeys = Set(assignees.filter { $0.status == .awaitingApproval }.map {
                PhoneApprovalAssigneeKey(occurrenceID: $0.occurrenceID, userID: $0.userID)
            })

            let loadedApprovals: [PhoneChoreApprovalItem] = submissions.compactMap { submission in
                guard let occurrence = occurrencesByID[submission.occurrenceID],
                      awaitingKeys.contains(PhoneApprovalAssigneeKey(
                        occurrenceID: submission.occurrenceID,
                        userID: submission.submittedBy
                      )) else { return nil }
                return PhoneChoreApprovalItem(
                    submission: submission,
                    occurrence: occurrence,
                    roomName: occurrence.roomID.flatMap { roomsByID[$0]?.name } ?? "Other",
                    memberName: namesByUserID[submission.submittedBy] ?? "Submitted member"
                )
            }
            let visibleRoomIDs = Set(loadedApprovals.map(\.roomGroupID))
            var visibleRooms = loadedRooms.filter { visibleRoomIDs.contains($0.id) }
            if visibleRoomIDs.contains(Self.otherRoomID) {
                visibleRooms.append(PhoneChoreRoom(
                    id: Self.otherRoomID,
                    name: "Other",
                    roomType: nil,
                    preferredCleaningWeekday: nil
                ))
            }
            approvals = loadedApprovals.sorted { $0.submission.submittedAt < $1.submission.submittedAt }
            rooms = visibleRooms
        } catch {
            guard activeLoadID == loadID else { return }
            approvals = []
            rooms = []
            errorMessage = "We couldn't load chore approvals."
            #if DEBUG
            print("[Homey] CHORE APPROVALS ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    func review(_ approval: PhoneChoreApprovalItem, decision: PhoneChoreApprovalDecision) async {
        guard !processingSubmissionIDs.contains(approval.id),
              activeRole == .owner || activeRole == .admin else { return }
        processingSubmissionIDs.insert(approval.id)
        actionErrorMessage = nil
        defer { processingSubmissionIDs.remove(approval.id) }

        do {
            try await actionRepository.review(
                submissionID: approval.id,
                decision: decision,
                pointsAwarded: decision == .approved ? max(0, approval.occurrence.pointsValue) : 0
            )
            await load(homeID: activeHomeID, role: activeRole)
            NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: self)
        } catch {
            actionErrorMessage = decision == .approved
                ? "Unable to approve chore. Please try again."
                : "Unable to request redo. Please try again."
            #if DEBUG
            print("[Homey] CHORE APPROVAL ACTION ERROR: \(String(reflecting: error))")
            #endif
        }
    }
}

private struct PhoneApprovalAssigneeKey: Hashable {
    let occurrenceID: UUID
    let userID: UUID
}

struct ChoreRewardsView: View {
    var body: some View {
        ChorePlaceholderView(
            title: "Rewards",
            message: "Rewards will appear here.",
            symbol: "gift"
        )
    }
}

struct ChorePlaceholderView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(HomeyColors.primary)
                    .frame(width: 72, height: 72)
                    .background(HomeyColors.field, in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(HomeyTypography.headline)
                    .foregroundStyle(HomeyColors.text)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 28)
        }
    }
}
