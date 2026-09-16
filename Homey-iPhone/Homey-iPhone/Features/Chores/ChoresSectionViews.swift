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
    @StateObject private var rewardModel = PhonePendingRewardApprovalsViewModel()
    @State private var selectedMode: PhoneApprovalsMode = .chores

    var body: some View {
        Group {
            if !canReviewChores {
                ChorePlaceholderView(
                    title: "Approvals",
                    message: "Only Home owners and admins can review chore submissions.",
                    symbol: "lock.shield"
                )
            } else {
                VStack(spacing: 0) {
                    Picker("Approval Type", selection: $selectedMode) {
                        ForEach(PhoneApprovalsMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if selectedMode == .chores {
                        choreApprovalsContent
                    } else {
                        pendingRewardsContent
                    }
                }
                .background(HomeyColors.background)
            }
        }
        .task(id: loadTaskID) {
            selectedMode = .chores
            rewardModel.reset(homeID: appSession.activeHome?.id, role: appSession.activeRole)
            await load()
        }
        .onChange(of: selectedMode) { _, mode in
            guard mode == .pendingRewards else { return }
            Task { await loadPendingRewardsIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("homeyChoresDidChange"))) { notification in
            if notification.object as? PhoneChoreApprovalsViewModel !== model {
                Task { await load() }
            }
            if selectedMode == .pendingRewards,
               notification.object as? PhonePendingRewardApprovalsViewModel !== rewardModel {
                Task { await loadPendingRewards() }
            }
        }
        .alert("Unable to Review Chore", isPresented: Binding(
            get: { model.actionErrorMessage != nil },
            set: { if !$0 { model.actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionErrorMessage = nil }
        } message: {
            Text(model.actionErrorMessage ?? "Please try again.")
        }
        .alert("Unable to Update Reward Redemption", isPresented: Binding(
            get: { rewardModel.actionErrorMessage != nil },
            set: { if !$0 { rewardModel.actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { rewardModel.actionErrorMessage = nil }
        } message: {
            Text(rewardModel.actionErrorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var choreApprovalsContent: some View {
        if model.isLoading && model.rooms.isEmpty {
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

    @ViewBuilder
    private var pendingRewardsContent: some View {
        if rewardModel.isLoading && rewardModel.redemptions.isEmpty {
            ProgressView("Loading pending rewards…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = rewardModel.errorMessage, rewardModel.redemptions.isEmpty {
            ScrollView {
                VStack(spacing: 14) {
                    HomeyErrorView(message: errorMessage)
                    Button("Try Again") { Task { await loadPendingRewards() } }
                        .buttonStyle(HomeyButtonStyle())
                }
                .padding(20)
                .homeyCard()
                .padding()
            }
        } else if rewardModel.redemptions.isEmpty {
            ChorePlaceholderView(
                title: "All caught up",
                message: "No reward redemptions are waiting to be marked redeemed.",
                symbol: "checkmark.circle.fill"
            )
        } else {
            List {
                Section {
                    ForEach(rewardModel.redemptions) { redemption in
                        PhonePendingRewardApprovalRow(
                            redemption: redemption,
                            isProcessing: rewardModel.processingRedemptionIDs.contains(redemption.id)
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task { await rewardModel.markRedeemed(redemption) }
                            } label: {
                                Label("Mark Redeemed", systemImage: "checkmark.circle.fill")
                            }
                            .tint(HomeyColors.success)
                            .disabled(rewardModel.processingRedemptionIDs.contains(redemption.id))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await rewardModel.cancel(redemption) }
                            } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                            .disabled(rewardModel.processingRedemptionIDs.contains(redemption.id))
                        }
                    }
                } header: {
                    HStack {
                        Text("Pending Rewards")
                            .font(HomeyTypography.headline)
                            .foregroundStyle(HomeyColors.text)
                        Spacer()
                        Text("\(rewardModel.redemptions.count)")
                            .font(.headline)
                            .foregroundStyle(HomeyColors.primary)
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(HomeyColors.background)
            .refreshable { await loadPendingRewards() }
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

    private func loadPendingRewardsIfNeeded() async {
        guard !rewardModel.hasLoadedCurrentScope else { return }
        await loadPendingRewards()
    }

    private func loadPendingRewards() async {
        await rewardModel.load(homeID: appSession.activeHome?.id, role: appSession.activeRole)
    }
}

private enum PhoneApprovalsMode: String, CaseIterable, Identifiable {
    case chores
    case pendingRewards

    var id: Self { self }
    var title: String { self == .chores ? "Chores" : "Pending Rewards" }
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

private struct PhonePendingRewardApprovalRecord: Decodable, Identifiable {
    let id: UUID
    let homeID: UUID
    let rewardID: UUID
    let userID: UUID
    let rewardName: String
    let pointCost: Int
    let status: String
    let requestedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case homeID = "home_id"
        case rewardID = "reward_id"
        case userID = "user_id"
        case rewardName = "reward_name_snapshot"
        case pointCost = "point_cost_snapshot"
        case requestedAt = "requested_at"
    }
}

private struct PhonePendingRewardApproval: Identifiable {
    let record: PhonePendingRewardApprovalRecord
    let memberName: String
    var id: UUID { record.id }
}

private struct PhoneMarkRewardRedeemedParameters: Encodable {
    let redemptionID: UUID
    enum CodingKeys: String, CodingKey { case redemptionID = "requested_redemption_id" }
}

private struct PhoneCancelRewardRedemptionParameters: Encodable {
    let redemptionID: UUID
    let cancellationReason: String?

    enum CodingKeys: String, CodingKey {
        case redemptionID = "requested_redemption_id"
        case cancellationReason = "requested_cancellation_reason"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(redemptionID, forKey: .redemptionID)
        if let cancellationReason {
            try container.encode(cancellationReason, forKey: .cancellationReason)
        } else {
            try container.encodeNil(forKey: .cancellationReason)
        }
    }
}

private struct PhonePendingRewardApprovalRepository {
    private let client = SupabaseManager.shared.client

    func markRedeemed(redemptionID: UUID) async throws -> UUID {
        try await client.rpc(
            "mark_chore_reward_redeemed",
            params: PhoneMarkRewardRedeemedParameters(redemptionID: redemptionID)
        ).execute().value
    }

    func cancel(redemptionID: UUID) async throws -> UUID {
        try await client.rpc(
            "cancel_chore_reward_redemption",
            params: PhoneCancelRewardRedemptionParameters(
                redemptionID: redemptionID,
                cancellationReason: nil
            )
        ).execute().value
    }
}

private struct PhonePendingRewardApprovalRow: View {
    let redemption: PhonePendingRewardApproval
    let isProcessing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "gift.fill")
                        .foregroundStyle(HomeyColors.primary)
                }
            }
            .frame(width: 20, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(redemption.record.rewardName)
                        .font(.body)
                        .foregroundStyle(HomeyColors.text)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(redemption.record.pointCost) pts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyColors.secondaryText)
                }

                Text(redemption.memberName)
                    .font(.caption)
                    .foregroundStyle(HomeyColors.secondaryText)

                Text("Pending")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)

                Text("Requested: \(redemption.record.requestedAt.phoneApprovalTimestamp)")
                    .font(.caption)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
        .opacity(isProcessing ? 0.65 : 1)
    }
}

@MainActor
private final class PhonePendingRewardApprovalsViewModel: ObservableObject {
    @Published private(set) var redemptions: [PhonePendingRewardApproval] = []
    @Published private(set) var isLoading = false
    @Published private(set) var processingRedemptionIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?
    @Published var actionErrorMessage: String?

    private let client = SupabaseManager.shared.client
    private let repository = PhonePendingRewardApprovalRepository()
    private var activeHomeID: UUID?
    private var activeRole: HomeMemberRole?
    private var activeLoadID = UUID()
    private(set) var hasLoadedCurrentScope = false

    func reset(homeID: UUID?, role: HomeMemberRole?) {
        activeLoadID = UUID()
        activeHomeID = homeID
        activeRole = role
        redemptions = []
        processingRedemptionIDs = []
        errorMessage = nil
        actionErrorMessage = nil
        isLoading = false
        hasLoadedCurrentScope = false
    }

    func load(homeID: UUID?, role: HomeMemberRole?) async {
        if activeHomeID != homeID || activeRole != role {
            reset(homeID: homeID, role: role)
        }

        guard let homeID, role == .owner || role == .admin else {
            reset(homeID: homeID, role: role)
            return
        }

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if activeLoadID == loadID { isLoading = false }
        }

        do {
            async let redemptionsRequest: [PhonePendingRewardApprovalRecord] = client
                .from("chore_reward_redemptions")
                .select("id,home_id,reward_id,user_id,reward_name_snapshot,point_cost_snapshot,status,requested_at")
                .eq("home_id", value: homeID.uuidString)
                .eq("status", value: "pending")
                .order("requested_at", ascending: true)
                .execute()
                .value
            let members: [PhoneChoreMember] = try await client
                .rpc("get_home_members", params: PhoneGetChoreMembersParameters(homeID: homeID))
                .execute()
                .value

            let records = try await redemptionsRequest
            guard activeLoadID == loadID else { return }
            let namesByUserID = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.displayName) })
            redemptions = records.map {
                PhonePendingRewardApproval(
                    record: $0,
                    memberName: namesByUserID[$0.userID] ?? "Home Member"
                )
            }
            hasLoadedCurrentScope = true
        } catch {
            guard activeLoadID == loadID else { return }
            redemptions = []
            errorMessage = "We couldn't load pending reward redemptions."
            hasLoadedCurrentScope = true
            #if DEBUG
            print("[Homey] PENDING REWARD APPROVALS ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    func markRedeemed(_ redemption: PhonePendingRewardApproval) async {
        guard activeRole == .owner || activeRole == .admin,
              !processingRedemptionIDs.contains(redemption.id) else { return }

        processingRedemptionIDs.insert(redemption.id)
        actionErrorMessage = nil
        defer { processingRedemptionIDs.remove(redemption.id) }

        do {
            _ = try await repository.markRedeemed(redemptionID: redemption.id)
            await load(homeID: activeHomeID, role: activeRole)
            NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: self)
        } catch {
            actionErrorMessage = "Unable to mark reward redeemed. Please try again."
            #if DEBUG
            print("[Homey] PENDING REWARD APPROVAL ACTION ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    func cancel(_ redemption: PhonePendingRewardApproval) async {
        guard activeRole == .owner || activeRole == .admin,
              !processingRedemptionIDs.contains(redemption.id) else { return }

        processingRedemptionIDs.insert(redemption.id)
        actionErrorMessage = nil
        defer { processingRedemptionIDs.remove(redemption.id) }

        do {
            _ = try await repository.cancel(redemptionID: redemption.id)
            await load(homeID: activeHomeID, role: activeRole)
            NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: self)
        } catch {
            actionErrorMessage = "Unable to cancel reward redemption. Please try again."
            #if DEBUG
            print("[Homey] PENDING REWARD CANCELLATION ERROR: \(String(reflecting: error))")
            #endif
        }
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
    @EnvironmentObject private var appSession: AppSession
    @StateObject private var model = PhoneRewardsViewModel()
    @State private var rewardToRedeem: PhoneChoreReward?
    @State private var rewardToEdit: PhoneChoreReward?

    var body: some View {
        Group {
            if (model.isLoading || model.isLoadingUserState) && model.pointBalance == nil {
                ProgressView("Loading rewards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage, model.pointBalance == nil {
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
            } else if model.rewards.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        if canManageRewards {
                            adminRewardsHeader
                        } else {
                            pointsCard
                        }
                        VStack(spacing: 12) {
                            Image(systemName: "gift")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(HomeyColors.primary)
                                .frame(width: 72, height: 72)
                                .background(HomeyColors.field, in: Circle())
                            Text("No rewards yet")
                                .font(HomeyTypography.headline)
                                .foregroundStyle(HomeyColors.text)
                            Text("Rewards added to your Home will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(HomeyColors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .homeyCard()
                    }
                    .padding(16)
                }
                .refreshable { await load() }
            } else {
                List {
                    if canManageRewards {
                        adminRewardsHeader
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        Section { pointsCard }
                    }
                    rewardListSection(
                        title: "Can Afford",
                        rewards: model.affordableRewards,
                        emptyMessage: "Keep earning! You don't have enough points for a reward yet.",
                        isAffordable: true
                    )
                    rewardListSection(
                        title: "All Rewards",
                        rewards: model.unaffordableRewards,
                        emptyMessage: "You can afford every available reward!",
                        isAffordable: false
                    )
                    if canManageRewards, !model.inactiveRewards.isEmpty {
                        rewardListSection(
                            title: "Inactive",
                            rewards: model.inactiveRewards,
                            emptyMessage: "",
                            isAffordable: false,
                            isManagementSection: true
                        )
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
            guard notification.object as? PhoneRewardsViewModel !== model else { return }
            Task { await load() }
        }
        .confirmationDialog(
            rewardToRedeem.map { "Redeem \($0.name)?" } ?? "Redeem Reward?",
            isPresented: Binding(
                get: { rewardToRedeem != nil },
                set: { if !$0 { rewardToRedeem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let rewardToRedeem {
                Button("Redeem for \(rewardToRedeem.pointCost) points") {
                    let reward = rewardToRedeem
                    self.rewardToRedeem = nil
                    Task { await model.redeem(reward) }
                }
            }
            Button("Cancel", role: .cancel) { rewardToRedeem = nil }
        } message: {
            Text("This will spend points and create a pending reward request.")
        }
        .sheet(item: $rewardToEdit) { reward in
            PhoneRewardEditorView(
                homeID: appSession.activeHome?.id,
                currentUserID: appSession.currentUser?.id,
                role: appSession.activeRole,
                reward: reward
            ) {
                Task { await load() }
            }
        }
        .alert("Unable to Redeem Reward", isPresented: Binding(
            get: { model.actionErrorMessage != nil },
            set: { if !$0 { model.actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.actionErrorMessage = nil }
        } message: {
            Text(model.actionErrorMessage ?? "Please try again.")
        }
    }

    private var pointsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedRewardUserID == appSession.currentUser?.id ? "My Points" : "Available Points")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyColors.secondaryText)
                Text(model.selectedRewardUserID == appSession.currentUser?.id
                     ? "Available to spend"
                     : model.selectedRewardUserName)
                    .font(.caption)
                    .foregroundStyle(HomeyColors.secondaryText)
            }
            Spacer()
            Text("\(model.pointBalance ?? 0) pts")
                .font(.title2.bold())
                .foregroundStyle(HomeyColors.primary)
        }
        .homeyCard()
    }

    private var adminRewardsHeader: some View {
        HStack(spacing: 12) {
            userFilterCard
            Text("\(model.pointBalance ?? 0) pts")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyColors.primary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
        }
    }

    private var userFilterCard: some View {
        Menu {
            ForEach(model.members, id: \.userID) { member in
                Button {
                    Task { await model.selectRewardUser(member.userID) }
                } label: {
                    Label(
                        member.displayName,
                        systemImage: member.userID == model.selectedRewardUserID ? "checkmark" : "person"
                    )
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(HomeyColors.primary)
                Text(model.selectedRewardUserLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyColors.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyColors.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
            .overlay {
                RoundedRectangle(cornerRadius: HomeyCornerRadius.field)
                    .stroke(HomeyColors.border, lineWidth: 1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingUserState)
        .accessibilityLabel("Filter rewards by user")
        .accessibilityValue(model.selectedRewardUserLabel)
    }

    @ViewBuilder
    private func rewardListSection(
        title: String,
        rewards: [PhoneChoreReward],
        emptyMessage: String,
        isAffordable: Bool,
        isManagementSection: Bool = false
    ) -> some View {
        Section {
            if rewards.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(HomeyColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(rewards) { reward in
                    PhoneRewardRow(
                        reward: reward,
                        isMuted: !isAffordable,
                        isPending: model.pendingRewardIDs.contains(reward.id),
                        isProcessing: model.redeemingRewardID == reward.id,
                        pointsNeeded: isManagementSection ? nil : model.pointsNeeded(for: reward),
                        onSelect: canManageRewards ? { rewardToEdit = reward } : nil
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if isAffordable && !model.pendingRewardIDs.contains(reward.id) {
                            Button {
                                rewardToRedeem = reward
                            } label: {
                                Label("Redeem", systemImage: "gift.fill")
                            }
                            .tint(HomeyColors.primary)
                            .disabled(model.redeemingRewardID == reward.id)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(title).font(HomeyTypography.headline)
                Spacer()
                Text("\(rewards.count)")
                    .font(.headline)
                    .foregroundStyle(HomeyColors.primary)
            }
            .textCase(nil)
        }
    }

    private var canManageRewards: Bool {
        appSession.activeRole == .owner || appSession.activeRole == .admin
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

struct PhoneChoreReward: Decodable, Identifiable {
    let id: UUID
    let homeID: UUID
    let name: String
    let description: String?
    let pointCost: Int
    let isActive: Bool
    let isArchived: Bool
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case homeID = "home_id"
        case pointCost = "point_cost"
        case isActive = "is_active"
        case isArchived = "is_archived"
    }
}

private struct PhonePointDelta: Decodable {
    let points: Int
}

private struct PhonePendingRewardRedemption: Decodable {
    let rewardID: UUID
    enum CodingKeys: String, CodingKey { case rewardID = "reward_id" }
}

private struct PhoneRedeemRewardParameters: Encodable {
    let homeID: UUID
    let rewardID: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case rewardID = "requested_reward_id"
    }
}

private struct PhoneRedeemRewardAsAdminParameters: Encodable {
    let homeID: UUID
    let rewardID: UUID
    let userID: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case rewardID = "requested_reward_id"
        case userID = "requested_user_id"
    }
}

private struct PhoneRewardRedemptionRepository {
    private let client = SupabaseManager.shared.client

    func redeemReward(homeID: UUID, rewardID: UUID) async throws -> UUID {
        try await client.rpc(
            "redeem_chore_reward",
            params: PhoneRedeemRewardParameters(homeID: homeID, rewardID: rewardID)
        ).execute().value
    }

    func redeemRewardAsAdmin(homeID: UUID, rewardID: UUID, userID: UUID) async throws -> UUID {
        try await client.rpc(
            "redeem_chore_reward_as_admin",
            params: PhoneRedeemRewardAsAdminParameters(
                homeID: homeID,
                rewardID: rewardID,
                userID: userID
            )
        ).execute().value
    }
}

private struct PhoneRewardCreatePayload: Encodable {
    let homeID: UUID
    let name: String
    let description: String?
    let pointCost: Int
    let isActive: Bool
    let isArchived = false
    let createdBy: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "home_id"
        case name, description
        case pointCost = "point_cost"
        case isActive = "is_active"
        case isArchived = "is_archived"
        case createdBy = "created_by"
    }
}

private struct PhoneRewardUpdatePayload: Encodable {
    let name: String
    let description: String?
    let pointCost: Int
    let isActive: Bool
    enum CodingKeys: String, CodingKey {
        case name, description
        case pointCost = "point_cost"
        case isActive = "is_active"
    }
}

private struct PhoneRewardRow: View {
    let reward: PhoneChoreReward
    let isMuted: Bool
    let isPending: Bool
    let isProcessing: Bool
    let pointsNeeded: Int?
    let onSelect: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "gift.fill")
                        .foregroundStyle(isMuted ? HomeyColors.secondaryText : HomeyColors.primary)
                }
            }
            .frame(width: 22, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(reward.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isMuted ? HomeyColors.secondaryText : HomeyColors.text)
                if let description = reward.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(HomeyColors.secondaryText)
                        .lineLimit(2)
                }
                if isPending {
                    Text("Redemption pending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                } else if let pointsNeeded, pointsNeeded > 0 {
                    Text("\(pointsNeeded) more points needed")
                        .font(.caption)
                        .foregroundStyle(HomeyColors.secondaryText)
                } else if !reward.isActive {
                    Text("Inactive")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyColors.secondaryText)
                }
            }

            Spacer(minLength: 8)

            Text("\(reward.pointCost) pts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isMuted ? HomeyColors.secondaryText : HomeyColors.text)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .opacity(isProcessing ? 0.65 : 1)
        .accessibilityAction(named: "Edit") { onSelect?() }
    }
}

@MainActor
private final class PhoneRewardsViewModel: ObservableObject {
    @Published private(set) var rewards: [PhoneChoreReward] = []
    @Published private(set) var members: [PhoneChoreMember] = []
    @Published private(set) var selectedRewardUserID: UUID?
    @Published private(set) var pointBalance: Int?
    @Published private(set) var pendingRewardIDs: Set<UUID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingUserState = false
    @Published private(set) var redeemingRewardID: UUID?
    @Published private(set) var errorMessage: String?
    @Published var actionErrorMessage: String?

    private let client = SupabaseManager.shared.client
    private let redemptionRepository = PhoneRewardRedemptionRepository()
    private var activeHomeID: UUID?
    private var activeCurrentUserID: UUID?
    private var activeRole: HomeMemberRole?
    private var activeLoadID = UUID()
    private var activeUserLoadID = UUID()

    var activeRewards: [PhoneChoreReward] { rewards.filter(\.isActive) }
    var inactiveRewards: [PhoneChoreReward] { rewards.filter { !$0.isActive } }
    var affordableRewards: [PhoneChoreReward] {
        activeRewards.filter { (pointBalance ?? 0) >= $0.pointCost }.sorted(by: Self.rewardSort)
    }
    var unaffordableRewards: [PhoneChoreReward] {
        activeRewards.filter { (pointBalance ?? 0) < $0.pointCost }.sorted(by: Self.rewardSort)
    }

    func pointsNeeded(for reward: PhoneChoreReward) -> Int? {
        guard let pointBalance else { return nil }
        return max(reward.pointCost - pointBalance, 0)
    }

    var selectedRewardUserName: String {
        members.first { $0.userID == selectedRewardUserID }?.displayName ?? "Selected member"
    }

    var selectedRewardUserLabel: String { selectedRewardUserName }

    func load(homeID: UUID?, currentUserID: UUID?, role: HomeMemberRole?) async {
        let loadID = UUID()
        activeLoadID = loadID
        let scopeChanged = activeHomeID != homeID || activeCurrentUserID != currentUserID || activeRole != role
        if scopeChanged {
            rewards = []
            members = []
            selectedRewardUserID = currentUserID
            pointBalance = nil
            pendingRewardIDs = []
        }
        activeHomeID = homeID
        activeCurrentUserID = currentUserID
        activeRole = role

        guard let homeID, let currentUserID else {
            rewards = []
            members = []
            selectedRewardUserID = nil
            pointBalance = nil
            pendingRewardIDs = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { if activeLoadID == loadID { isLoading = false } }

        do {
            let canManageRewards = role == .owner || role == .admin
            if canManageRewards {
                let loadedMembers: [PhoneChoreMember] = try await client
                    .rpc("get_home_members", params: PhoneGetChoreMembersParameters(homeID: homeID))
                    .execute()
                    .value
                guard activeLoadID == loadID else { return }
                members = loadedMembers.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                if selectedRewardUserID == nil || !members.contains(where: { $0.userID == selectedRewardUserID }) {
                    selectedRewardUserID = currentUserID
                }
            } else {
                members = []
                selectedRewardUserID = currentUserID
            }

            var rewardQuery = client
                .from("chore_rewards")
                .select("id,home_id,name,description,point_cost,is_active,is_archived")
                .eq("home_id", value: homeID.uuidString)
                .eq("is_archived", value: false)
            if role != .owner && role != .admin {
                rewardQuery = rewardQuery.eq("is_active", value: true)
            }

            let loadedRewards: [PhoneChoreReward] = try await rewardQuery
                .order("point_cost", ascending: true)
                .order("name", ascending: true)
                .execute()
                .value
            guard activeLoadID == loadID else { return }
            rewards = loadedRewards
            guard let rewardUserID = selectedRewardUserID else { return }
            await loadUserState(for: rewardUserID)
        } catch {
            guard activeLoadID == loadID else { return }
            rewards = []
            members = []
            pointBalance = nil
            pendingRewardIDs = []
            errorMessage = "We couldn't load rewards."
            #if DEBUG
            print("[Homey] CHORE REWARDS ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    func selectRewardUser(_ userID: UUID) async {
        guard activeRole == .owner || activeRole == .admin,
              members.contains(where: { $0.userID == userID }) else { return }
        guard selectedRewardUserID != userID else { return }
        selectedRewardUserID = userID
        pointBalance = nil
        pendingRewardIDs = []
        await loadUserState(for: userID)
    }

    private func loadUserState(for userID: UUID) async {
        guard let activeHomeID else { return }
        let userLoadID = UUID()
        activeUserLoadID = userLoadID
        isLoadingUserState = true
        defer {
            if activeUserLoadID == userLoadID { isLoadingUserState = false }
        }

        do {
            async let pointsRequest: [PhonePointDelta] = client
                .from("chore_point_transactions")
                .select("points")
                .eq("home_id", value: activeHomeID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
            async let pendingRequest: [PhonePendingRewardRedemption] = client
                .from("chore_reward_redemptions")
                .select("reward_id")
                .eq("home_id", value: activeHomeID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .eq("status", value: "pending")
                .execute()
                .value
            let (pointRows, pendingRows) = try await (pointsRequest, pendingRequest)
            guard activeUserLoadID == userLoadID, selectedRewardUserID == userID else { return }
            pointBalance = pointRows.reduce(0) { $0 + $1.points }
            pendingRewardIDs = Set(pendingRows.map(\.rewardID))
        } catch {
            guard activeUserLoadID == userLoadID, selectedRewardUserID == userID else { return }
            pointBalance = nil
            pendingRewardIDs = []
            errorMessage = "We couldn't load rewards."
            #if DEBUG
            print("[Homey] CHORE REWARDS ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    func redeem(_ reward: PhoneChoreReward) async {
        guard let activeHomeID,
              let activeCurrentUserID,
              let selectedRewardUserID,
              reward.isActive,
              (pointBalance ?? 0) >= reward.pointCost,
              !pendingRewardIDs.contains(reward.id),
              redeemingRewardID == nil else { return }
        redeemingRewardID = reward.id
        actionErrorMessage = nil
        defer { redeemingRewardID = nil }

        do {
            if selectedRewardUserID == activeCurrentUserID {
                _ = try await redemptionRepository.redeemReward(
                    homeID: activeHomeID,
                    rewardID: reward.id
                )
            } else {
                guard activeRole == .owner || activeRole == .admin,
                      members.contains(where: { $0.userID == selectedRewardUserID }) else { return }
                _ = try await redemptionRepository.redeemRewardAsAdmin(
                    homeID: activeHomeID,
                    rewardID: reward.id,
                    userID: selectedRewardUserID
                )
            }
            await loadUserState(for: selectedRewardUserID)
            NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: self)
        } catch {
            actionErrorMessage = "Unable to redeem this reward. Please check your balance and try again."
            #if DEBUG
            print("[Homey] CHORE REWARD ACTION ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    private static func rewardSort(_ lhs: PhoneChoreReward, _ rhs: PhoneChoreReward) -> Bool {
        if lhs.pointCost != rhs.pointCost { return lhs.pointCost < rhs.pointCost }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

struct PhoneRewardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID?
    let currentUserID: UUID?
    let role: HomeMemberRole?
    let reward: PhoneChoreReward?
    let onSaved: () -> Void

    @State private var name = ""
    @State private var rewardDescription = ""
    @State private var pointCostText = ""
    @State private var isActive = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = SupabaseManager.shared.client

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorField("Reward Name") {
                        TextField("Movie Night", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(14)
                            .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 14))
                    }
                    editorField("Description") {
                        TextField("Pick the movie for family movie night.", text: $rewardDescription, axis: .vertical)
                            .lineLimit(3...5)
                            .padding(14)
                            .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 14))
                    }
                    editorField("Point Cost") {
                        TextField("100", text: $pointCostText)
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 14))
                            .onChange(of: pointCostText) { _, newValue in
                                pointCostText = newValue.filter(\.isNumber)
                            }
                    }
                    Toggle("Active", isOn: $isActive)
                        .font(.headline)
                        .tint(HomeyColors.success)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyColors.danger)
                    }

                    Button { Task { await save() } } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving…" : "Save Reward")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(HomeyButtonStyle())
                    .disabled(!canSave)
                }
                .padding(20)
            }
            .background(HomeyColors.background.ignoresSafeArea())
            .navigationTitle(reward == nil ? "Add Reward" : "Edit Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .task { populate() }
        .interactiveDismissDisabled(isSaving)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDescription: String { rewardDescription.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pointCost: Int? { Int(pointCostText) }
    private var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && (pointCost ?? 0) > 0
            && (role == .owner || role == .admin) && homeID != nil && currentUserID != nil
    }

    private func editorField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(HomeyColors.text)
            content()
        }
    }

    private func populate() {
        guard let reward, name.isEmpty, pointCostText.isEmpty else { return }
        name = reward.name
        rewardDescription = reward.description ?? ""
        pointCostText = String(reward.pointCost)
        isActive = reward.isActive
    }

    private func save() async {
        guard canSave, let homeID, let currentUserID, let pointCost else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let reward {
                try await client
                    .from("chore_rewards")
                    .update(PhoneRewardUpdatePayload(
                        name: trimmedName,
                        description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                        pointCost: pointCost,
                        isActive: isActive
                    ))
                    .eq("id", value: reward.id.uuidString)
                    .execute()
            } else {
                try await client
                    .from("chore_rewards")
                    .insert(PhoneRewardCreatePayload(
                        homeID: homeID,
                        name: trimmedName,
                        description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                        pointCost: pointCost,
                        isActive: isActive,
                        createdBy: currentUserID
                    ))
                    .execute()
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Unable to save reward. Please try again."
            #if DEBUG
            print("[Homey] CHORE REWARD SAVE ERROR: \(String(reflecting: error))")
            #endif
        }
    }
}

private enum PhonePointAdjustmentType: String, CaseIterable, Identifiable {
    case add = "Add"
    case remove = "Remove"
    var id: Self { self }
}

private struct PhoneAdjustPointsParameters: Encodable {
    let homeID: UUID
    let userID: UUID
    let points: Int
    let description: String
    let transactionAt: String
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case userID = "requested_user_id"
        case points = "requested_points"
        case description = "requested_description"
        case transactionAt = "requested_transaction_at"
    }
}

struct PhonePointAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss
    let homeID: UUID?
    let currentUserID: UUID?
    let role: HomeMemberRole?
    let onSaved: () -> Void

    @State private var members: [PhoneChoreMember] = []
    @State private var selectedUserID: UUID?
    @State private var adjustmentType: PhonePointAdjustmentType = .add
    @State private var transactionDate = Date()
    @State private var amountText = ""
    @State private var adjustmentDescription = ""
    @State private var selectedBalance = 0
    @State private var isLoading = true
    @State private var isLoadingBalance = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let client = SupabaseManager.shared.client

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    userField

                    adjustmentField("Adjustment Type") {
                        Picker("Adjustment Type", selection: $adjustmentType) {
                            ForEach(PhonePointAdjustmentType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    adjustmentField("Date & Time") {
                        DatePicker(
                            "Date & Time",
                            selection: $transactionDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }

                    adjustmentField("Point Amount") {
                        TextField("25", text: $amountText)
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .onChange(of: amountText) { _, newValue in
                                amountText = newValue.filter(\.isNumber)
                            }
                    }

                    adjustmentField("Description") {
                        TextField(
                            "Bonus for helping clean the garage",
                            text: $adjustmentDescription,
                            axis: .vertical
                        )
                        .lineLimit(3...5)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if isLoadingBalance {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading available points…")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeyColors.secondaryText)
                    } else {
                        Text("Available points: \(selectedBalance)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeyColors.secondaryText)
                    }

                    if let visibleMessage = errorMessage ?? validationMessage {
                        Text(visibleMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(HomeyColors.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button { Task { await save() } } label: {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving…" : "Save Adjustment")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(HomeyButtonStyle())
                    .disabled(!canSave)
                }
                .padding(20)
            }
            .background(HomeyColors.background.ignoresSafeArea())
            .navigationTitle("Adjust Points")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .task { await loadMembers() }
        .onChange(of: selectedUserID) { _, _ in Task { await loadSelectedBalance() } }
        .interactiveDismissDisabled(isSaving)
    }

    private var selectedMember: PhoneChoreMember? {
        members.first { $0.userID == selectedUserID }
    }
    private var amount: Int? { Int(amountText) }
    private var trimmedDescription: String {
        adjustmentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var validationMessage: String? {
        guard role == .owner || role == .admin else { return "Only Home owners and admins can adjust points." }
        guard selectedUserID != nil else { return "Choose a member." }
        guard let amount, amount > 0 else { return "Enter a point amount greater than 0." }
        if adjustmentType == .remove && amount > selectedBalance {
            return "Cannot remove more points than this member currently has available."
        }
        guard !trimmedDescription.isEmpty else { return "Description is required." }
        return nil
    }
    private var canSave: Bool {
        !isLoading && !isLoadingBalance && !isSaving && validationMessage == nil
    }

    private var userField: some View {
        adjustmentField("User") {
            Menu {
                ForEach(members, id: \.userID) { member in
                    Button {
                        selectedUserID = member.userID
                    } label: {
                        Label(
                            member.userID == currentUserID ? "\(member.displayName) (You)" : member.displayName,
                            systemImage: member.userID == selectedUserID ? "checkmark" : "person"
                        )
                    }
                }
            } label: {
                HStack {
                    Text(selectedMember.map {
                        $0.userID == currentUserID ? "\($0.displayName) (You)" : $0.displayName
                    } ?? "Select Member")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyColors.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyColors.secondaryText)
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isSaving)
        }
    }

    private func adjustmentField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(HomeyColors.text)
            content()
        }
    }

    private func loadMembers() async {
        guard let homeID, role == .owner || role == .admin else {
            isLoading = false
            errorMessage = "Only Home owners and admins can adjust points."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let loadedMembers: [PhoneChoreMember] = try await client
                .rpc("get_home_members", params: PhoneGetChoreMembersParameters(homeID: homeID))
                .execute()
                .value
            members = loadedMembers.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            selectedUserID = currentUserID.flatMap { currentID in
                members.contains { $0.userID == currentID } ? currentID : nil
            } ?? members.first?.userID
        } catch {
            errorMessage = "Unable to load Home members."
            #if DEBUG
            print("[Homey] POINT ADJUSTMENT ERROR: \(String(reflecting: error))")
            #endif
        }
        isLoading = false
    }

    private func loadSelectedBalance() async {
        guard let homeID, let selectedUserID else {
            selectedBalance = 0
            return
        }
        let requestedUserID = selectedUserID
        isLoadingBalance = true
        errorMessage = nil
        do {
            let rows: [PhonePointDelta] = try await client
                .from("chore_point_transactions")
                .select("points")
                .eq("home_id", value: homeID.uuidString)
                .eq("user_id", value: requestedUserID.uuidString)
                .execute()
                .value
            guard self.selectedUserID == requestedUserID else { return }
            selectedBalance = rows.reduce(0) { $0 + $1.points }
        } catch {
            guard self.selectedUserID == requestedUserID else { return }
            selectedBalance = 0
            errorMessage = "Unable to load available points."
            #if DEBUG
            print("[Homey] POINT ADJUSTMENT BALANCE ERROR: \(String(reflecting: error))")
            #endif
        }
        if self.selectedUserID == requestedUserID { isLoadingBalance = false }
    }

    private func save() async {
        guard canSave,
              let homeID,
              let selectedUserID,
              let amount else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let signedPoints = adjustmentType == .add ? amount : -amount
        do {
            let _: UUID = try await client.rpc(
                "adjust_chore_points",
                params: PhoneAdjustPointsParameters(
                    homeID: homeID,
                    userID: selectedUserID,
                    points: signedPoints,
                    description: trimmedDescription,
                    transactionAt: Self.timestampFormatter.string(from: transactionDate)
                )
            ).execute().value
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Unable to save adjustment. Please verify the member's available points and try again."
            #if DEBUG
            print("[Homey] POINT ADJUSTMENT SAVE ERROR: \(String(reflecting: error))")
            #endif
        }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
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
