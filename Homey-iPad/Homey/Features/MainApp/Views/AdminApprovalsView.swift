import SwiftUI
import Supabase
import Combine

struct AdminPendingChoreApproval: Decodable, Identifiable, Equatable, Sendable {
    let submissionID: UUID
    let occurrenceID: UUID
    let submittedBy: UUID
    let memberDisplayName: String
    let memberAvatarURL: String?
    let choreTitle: String
    let choreDescription: String?
    let roomName: String?
    let pointsValue: Int
    let submittedAt: Date
    let dueLocalDate: String?
    let requiresPhoto: Bool

    var id: UUID { submissionID }

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
        case occurrenceID = "occurrence_id"
        case submittedBy = "submitted_by"
        case memberDisplayName = "member_display_name"
        case memberAvatarURL = "member_avatar_url"
        case choreTitle = "chore_title"
        case choreDescription = "chore_description"
        case roomName = "room_name"
        case pointsValue = "points_value"
        case submittedAt = "submitted_at"
        case dueLocalDate = "due_local_date"
        case requiresPhoto = "requires_photo"
    }
}

private enum AdminChoreReviewDecision: String {
    case approved
    case needsRedo = "needs_redo"
}

private enum AdminApprovalServiceError: LocalizedError {
    case sessionExpired
    case loadFailed
    case reviewFailed

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Admin session expired. Enter a PIN to continue."
        case .loadFailed:
            return "Approvals could not be loaded. Please try again."
        case .reviewFailed:
            return "Chore could not be reviewed. Please try again."
        }
    }
}

private struct AdminChoreApprovalService {
    private let client = SupabaseManager.shared.client

    func pendingApprovals(homeID: UUID) async throws -> [AdminPendingChoreApproval] {
        do {
            let approvals: [AdminPendingChoreApproval] = try await client.rpc(
                "get_pending_chore_approvals",
                params: AdminApprovalHomeParameters(homeID: homeID)
            ).execute().value
            return approvals
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func review(
        homeID: UUID,
        sessionToken: String,
        submissionID: UUID,
        decision: AdminChoreReviewDecision,
        adminNote: String? = nil
    ) async throws -> UUID {
        #if DEBUG
        print("[Homey] ADMIN APPROVAL REQUEST")
        print("submission_id: \(submissionID.uuidString)")
        print("decision: \(decision.rawValue)")
        print("home_id: \(homeID.uuidString)")
        #endif

        do {
            let approvalID: UUID = try await client.rpc(
                "review_chore_submission_with_admin_session",
                params: AdminChoreReviewParameters(
                    homeID: homeID,
                    sessionToken: sessionToken,
                    submissionID: submissionID,
                    decision: decision.rawValue,
                    adminNote: normalized(adminNote),
                    pointsAwarded: nil
                )
            ).execute().value

            #if DEBUG
            print("[Homey] ADMIN APPROVAL RPC SUCCESS")
            print("approval_id: \(approvalID.uuidString)")
            #endif
            return approvalID
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AdminApprovalServiceError {
            logMutationError(error)
            throw error
        } catch {
            logMutationError(error)
            let message = ((error as? PostgrestError)?.message ?? error.localizedDescription).lowercased()
            if message.contains("admin session") &&
                (message.contains("invalid") || message.contains("expired")) {
                throw AdminApprovalServiceError.sessionExpired
            }
            throw AdminApprovalServiceError.reviewFailed
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func logMutationError(_ error: Error) {
        #if DEBUG
        print("[Homey] ADMIN APPROVAL ERROR")
        print("type: \(String(reflecting: type(of: error)))")
        if let postgrestError = error as? PostgrestError {
            print("code: \(postgrestError.code ?? "")")
            print("message: \(postgrestError.message)")
            print("detail: \(postgrestError.detail ?? "")")
            print("hint: \(postgrestError.hint ?? "")")
        } else {
            print("code:")
            print("message: \(error.localizedDescription)")
            print("detail: \(String(reflecting: error))")
            print("hint:")
        }
        #endif
    }
}

private struct AdminApprovalHomeParameters: Encodable {
    let homeID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
    }
}

private struct AdminChoreReviewParameters: Encodable {
    let homeID: UUID
    let sessionToken: String
    let submissionID: UUID
    let decision: String
    let adminNote: String?
    let pointsAwarded: Int?

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case sessionToken = "requested_session_token"
        case submissionID = "requested_submission_id"
        case decision = "requested_decision"
        case adminNote = "requested_admin_note"
        case pointsAwarded = "requested_points_awarded"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(sessionToken, forKey: .sessionToken)
        try container.encode(submissionID, forKey: .submissionID)
        try container.encode(decision, forKey: .decision)
        try container.encodeIfPresent(adminNote, forKey: .adminNote)
        if adminNote == nil {
            try container.encodeNil(forKey: .adminNote)
        }
        try container.encodeNil(forKey: .pointsAwarded)
    }
}

@MainActor
private final class AdminApprovalsViewModel: ObservableObject {
    @Published private(set) var approvals: [AdminPendingChoreApproval] = []
    @Published private(set) var isLoading = false
    @Published private(set) var processingSubmissionIDs: Set<UUID> = []
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var actionErrorMessage: String?

    private let service = AdminChoreApprovalService()
    private var activeHomeID: UUID?
    private var loadID = UUID()

    func load(homeID: UUID, clearExisting: Bool = false) async {
        activeHomeID = homeID
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        loadErrorMessage = nil
        actionErrorMessage = nil
        if clearExisting {
            approvals = []
        }

        do {
            let loadedApprovals = try await service.pendingApprovals(homeID: homeID)
            guard activeHomeID == homeID, loadID == requestID else { return }
            approvals = loadedApprovals
            loadErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard activeHomeID == homeID, loadID == requestID else { return }
            loadErrorMessage = AdminApprovalServiceError.loadFailed.localizedDescription
        }

        guard activeHomeID == homeID, loadID == requestID else { return }
        isLoading = false
    }

    func review(
        _ approval: AdminPendingChoreApproval,
        decision: AdminChoreReviewDecision,
        homeID: UUID,
        sessionToken: String,
        controller: HomeAdminAccessController
    ) async {
        guard activeHomeID == homeID,
              !processingSubmissionIDs.contains(approval.submissionID) else {
            return
        }

        processingSubmissionIDs.insert(approval.submissionID)
        actionErrorMessage = nil
        defer { processingSubmissionIDs.remove(approval.submissionID) }

        do {
            _ = try await service.review(
                homeID: homeID,
                sessionToken: sessionToken,
                submissionID: approval.submissionID,
                decision: decision
            )
        } catch is CancellationError {
            return
        } catch AdminApprovalServiceError.sessionExpired {
            reset()
            controller.lock()
            return
        } catch {
            guard activeHomeID == homeID else { return }
            actionErrorMessage = error.localizedDescription
            return
        }

        NotificationCenter.default.post(name: .homeyChoresDidChange, object: nil)
        NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
        guard activeHomeID == homeID else { return }
        loadID = UUID()
        withAnimation(.easeInOut(duration: 0.2)) {
            approvals.removeAll { $0.submissionID == approval.submissionID }
        }
        controller.extendSessionAfterAdminActivity()
        await reconcileAfterSuccessfulReview(homeID: homeID)
    }

    private func reconcileAfterSuccessfulReview(homeID: UUID) async {
        let requestID = UUID()
        loadID = requestID

        do {
            let reconciledApprovals = try await service.pendingApprovals(homeID: homeID)
            guard activeHomeID == homeID, loadID == requestID else { return }
            approvals = reconciledApprovals
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            print("[Homey] ADMIN APPROVAL REFRESH ERROR")
            print("type: \(String(reflecting: type(of: error)))")
            if let postgrestError = error as? PostgrestError {
                print("code: \(postgrestError.code ?? "")")
                print("message: \(postgrestError.message)")
                print("detail: \(postgrestError.detail ?? "")")
                print("hint: \(postgrestError.hint ?? "")")
            } else {
                print("code:")
                print("message: \(error.localizedDescription)")
                print("detail: \(String(reflecting: error))")
                print("hint:")
            }
            #endif
        }
    }

    func reset() {
        activeHomeID = nil
        loadID = UUID()
        approvals = []
        processingSubmissionIDs = []
        isLoading = false
        loadErrorMessage = nil
        actionErrorMessage = nil
    }
}

struct AdminApprovalsView: View {
    let homeID: UUID
    let session: HomeAdminSession
    @ObservedObject var controller: HomeAdminAccessController
    @StateObject private var viewModel = AdminApprovalsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                approvalsHeader

                if viewModel.isLoading && viewModel.approvals.isEmpty {
                    loadingState
                } else if let loadErrorMessage = viewModel.loadErrorMessage,
                          viewModel.approvals.isEmpty {
                    loadErrorState(loadErrorMessage)
                } else if viewModel.approvals.isEmpty {
                    emptyState
                } else {
                    if let loadErrorMessage = viewModel.loadErrorMessage {
                        errorBanner(loadErrorMessage)
                    }

                    if let actionErrorMessage = viewModel.actionErrorMessage {
                        errorBanner(actionErrorMessage)
                    }

                    ForEach(viewModel.approvals) { approval in
                        AdminApprovalCard(
                            approval: approval,
                            isProcessing: viewModel.processingSubmissionIDs.contains(approval.submissionID),
                            onNeedsMoreWork: {
                                review(approval, decision: .needsRedo)
                            },
                            onApprove: {
                                review(approval, decision: .approved)
                            }
                        )
                    }
                }
            }
            .padding(4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.load(homeID: homeID)
        }
        .task(id: homeID) {
            await viewModel.load(homeID: homeID, clearExisting: true)
        }
        .onDisappear {
            viewModel.reset()
        }
    }

    private var approvalsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Approvals", systemImage: "checkmark.seal.fill")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Spacer()

            Text("\(viewModel.approvals.count) Pending")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
            Text("Loading approvals…")
                .font(.headline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .dashboardCard(cornerRadius: 28)
    }

    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(HomeyDashboardTheme.softRed)
            Text(message)
                .font(.headline)
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load(homeID: homeID) }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .background(HomeyDashboardTheme.warmBrown, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(28)
        .dashboardCard(cornerRadius: 28)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(HomeyDashboardTheme.sageAccent)
            Text("All caught up!")
                .font(.title2.bold())
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text("No chores are waiting for approval.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(28)
        .dashboardCard(cornerRadius: 28)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.softRed)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyDashboardTheme.softRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func review(_ approval: AdminPendingChoreApproval, decision: AdminChoreReviewDecision) {
        Task {
            await viewModel.review(
                approval,
                decision: decision,
                homeID: homeID,
                sessionToken: session.token,
                controller: controller
            )
        }
    }
}

private struct AdminApprovalCard: View {
    let approval: AdminPendingChoreApproval
    let isProcessing: Bool
    let onNeedsMoreWork: () -> Void
    let onApprove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                AvatarView(
                    imageURL: approval.memberAvatarURL.flatMap(URL.init(string:)),
                    initials: initials,
                    size: 58,
                    accessibilityLabel: "\(approval.memberDisplayName) avatar"
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(approval.choreTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)

                    Text(approvalMetadata)
                        .font(.headline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)

                    if let description = normalized(approval.choreDescription) {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 18)

                Text("\(approval.pointsValue) pts")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
            }

            HStack(spacing: 18) {
                Label(submittedText, systemImage: "clock.fill")

                if approval.requiresPhoto {
                    Label("Photo Required", systemImage: "camera.fill")
                        .foregroundStyle(HomeyDashboardTheme.orangeAccent)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)

            HStack(spacing: 14) {
                Button(action: onNeedsMoreWork) {
                    Label("Needs More Work", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .frame(minHeight: 54)
                .background(HomeyDashboardTheme.destructiveRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(HomeyDashboardTheme.destructiveRed.opacity(0.30), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Button(action: onApprove) {
                    HStack(spacing: 9) {
                        if isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(isProcessing ? "Reviewing…" : "Approve")
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(minHeight: 54)
                .background(HomeyDashboardTheme.warmBrown, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 28)
        .opacity(isProcessing ? 0.82 : 1)
    }

    private var initials: String {
        let parts = approval.memberDisplayName.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var approvalMetadata: String {
        var segments = [approval.memberDisplayName]
        if let room = normalized(approval.roomName) {
            segments.append(room)
        }
        if let scheduledDate = scheduledDateText {
            segments.append("Scheduled \(scheduledDate)")
        }
        return segments.joined(separator: " • ")
    }

    private var scheduledDateText: String? {
        guard let dueLocalDate = normalized(approval.dueLocalDate) else { return nil }
        let components = dueLocalDate.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].count == 4,
              components[1].count == 2,
              components[2].count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }
        return String(format: "%02d/%02d/%04d", month, day, year)
    }

    private var submittedText: String {
        "Submitted \(approval.submittedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
