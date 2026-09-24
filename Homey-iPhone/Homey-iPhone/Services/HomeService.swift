import Combine
import Foundation
import PostgREST
import Supabase

@MainActor
final class HomeService: ObservableObject {
    @Published private(set) var homes: [HomeSummary] = []
    @Published private(set) var members: [HomeMemberDisplay] = []
    @Published private(set) var pendingInvitations: [HomeInvitationDisplay] = []
    @Published private(set) var myPendingInvitations: [HomeInvitationDisplay] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMembers = false
    @Published private(set) var isLoadingInvitations = false
    @Published private(set) var isLoadingMyInvitations = false
    @Published private(set) var isCreatingInvitation = false
    @Published private(set) var cancellingInvitationID: UUID?
    @Published private(set) var acceptingInvitationID: UUID?
    @Published private(set) var decliningInvitationID: UUID?
    @Published var selectedHome: HomeSummary?
    @Published var errorMessage: String?
    @Published var membersErrorMessage: String?
    @Published var invitationsErrorMessage: String?
    @Published var myInvitationsErrorMessage: String?
    private let client = SupabaseManager.shared.client
    private var loadedMembersHomeID: UUID?
    private var loadingMembersHomeID: UUID?
    private var loadedInvitationsHomeID: UUID?
    private var loadingInvitationsHomeID: UUID?
    private var loadedInvitationUserID: UUID?
    private var loadingInvitationUserID: UUID?
    private var homesLoadID = UUID()

    func loadHomes(for userID: UUID, preferredHomeID: UUID?) async {
        let loadID = UUID()
        homesLoadID = loadID
        isLoading = true; errorMessage = nil
        defer { if homesLoadID == loadID { isLoading = false } }
        do {
            let loadedHomes = try await fetchHomes(for: userID)
            guard homesLoadID == loadID else { return }
            homes = loadedHomes
            if homes.count == 1 { setSelectedHome(homes[0]) }
            else if let preferredHomeID { setSelectedHome(homes.first { $0.id == preferredHomeID }) }
            else { setSelectedHome(nil) }
        } catch {
            guard homesLoadID == loadID else { return }
            homes = []; setSelectedHome(nil)
            errorMessage = "We couldn't load your Homes. Check your connection and try again."
            debugLog(error, context: "LOAD HOMES")
        }
    }

    /// Refreshes the membership list without discarding a coherent active Home when the
    /// network request fails. This is used by Change Home, where the existing dashboard
    /// must remain recoverable until a destination membership is established.
    @discardableResult
    func refreshHomes(for userID: UUID, preservingHomeID: UUID?) async -> Bool {
        let loadID = UUID()
        homesLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer { if homesLoadID == loadID { isLoading = false } }
        do {
            let loadedHomes = try await fetchHomes(for: userID)
            guard homesLoadID == loadID else { return false }
            homes = loadedHomes
            if let preservingHomeID, let current = loadedHomes.first(where: { $0.id == preservingHomeID }) {
                setSelectedHome(current)
            } else if loadedHomes.count == 1 {
                setSelectedHome(loadedHomes[0])
            } else {
                setSelectedHome(nil)
            }
            return true
        } catch {
            guard homesLoadID == loadID else { return false }
            errorMessage = "We couldn't refresh your Homes. Check your connection and try again."
            debugLog(error, context: "REFRESH HOMES")
            return false
        }
    }

    /// Re-reads the destination membership immediately before switching so the Home and
    /// role are committed together. No membership row is mutated by this operation.
    func validatedHome(homeID: UUID, userID: UUID) async throws -> HomeSummary {
        let memberships: [HomeMembershipResponse] = try await client
            .from("home_members")
            .select("role, homes(id, name, timezone, week_starts_on, created_at)")
            .eq("user_id", value: userID.uuidString)
            .eq("home_id", value: homeID.uuidString)
            .limit(1)
            .execute().value
        guard let home = memberships.first?.summary() else { throw HomeSelectionError.membershipUnavailable }
        return home
    }

    func createHome(name: String, timezone: String, userID: UUID) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { errorMessage = "Enter a Home name."; return false }
        guard !timezone.isEmpty else { errorMessage = "Choose a timezone."; return false }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let homeID: UUID = try await client.rpc("create_home", params: CreateHomeParameters(homeName: cleanName, homeTimezone: timezone)).execute().value
            let loadedHomes = try await fetchHomes(for: userID)
            guard let createdHome = loadedHomes.first(where: { $0.id == homeID }) else {
                throw HomeSelectionError.membershipUnavailable
            }
            homes = loadedHomes
            setSelectedHome(createdHome)
            return selectedHome != nil
        } catch {
            errorMessage = "We couldn't create your Home. Please try again."
            debugLog(error, context: "CREATE HOME")
            return false
        }
    }

    func membersForSelectedHome() -> [HomeMemberDisplay] {
        loadedMembersHomeID == selectedHome?.id ? members : []
    }

    func invitationsForSelectedHome() -> [HomeInvitationDisplay] {
        loadedInvitationsHomeID == selectedHome?.id ? pendingInvitations : []
    }

    func hasLoadedMembers(for homeID: UUID) -> Bool { loadedMembersHomeID == homeID }
    func hasLoadedInvitations(for homeID: UUID) -> Bool { loadedInvitationsHomeID == homeID }

    func loadMembers(homeID: UUID, currentUserID: UUID, forceRefresh: Bool = false) async {
        if loadingMembersHomeID == homeID { return }
        if !forceRefresh, loadedMembersHomeID == homeID { return }

        loadingMembersHomeID = homeID
        isLoadingMembers = true
        membersErrorMessage = nil
        if loadedMembersHomeID != homeID {
            members = []
            loadedMembersHomeID = nil
        }

        do {
            let rows: [HomeMemberListResponse] = try await client
                .rpc("get_home_members", params: GetHomeMembersParameters(homeID: homeID))
                .execute()
                .value
            guard loadingMembersHomeID == homeID, selectedHome?.id == homeID else { return }
            members = HomeMemberDisplay.sorted(rows.map { $0.display(currentUserID: currentUserID) })
            loadedMembersHomeID = homeID
            if let currentMembership = members.first(where: { $0.userID == currentUserID }) {
                refreshSelectedHomeSummary(role: currentMembership.role, memberCount: members.count)
            }
        } catch {
            guard loadingMembersHomeID == homeID, selectedHome?.id == homeID else { return }
            membersErrorMessage = memberErrorMessage(for: error)
            debugLog(error, context: "LOAD HOME MEMBERS")
        }

        if loadingMembersHomeID == homeID { loadingMembersHomeID = nil }
        if selectedHome?.id == homeID { isLoadingMembers = false }
    }

    func loadPendingInvitations(homeID: UUID, forceRefresh: Bool = false) async {
        if loadingInvitationsHomeID == homeID { return }
        if !forceRefresh, loadedInvitationsHomeID == homeID { return }

        loadingInvitationsHomeID = homeID
        isLoadingInvitations = true
        invitationsErrorMessage = nil
        if loadedInvitationsHomeID != homeID {
            pendingInvitations = []
            loadedInvitationsHomeID = nil
        }

        do {
            let rows: [HomeInvitationResponse] = try await client
                .from("home_invitations")
                .select("id, home_id, email, role, status, invited_by, created_at, expires_at")
                .eq("home_id", value: homeID.uuidString)
                .eq("status", value: HomeInvitationStatus.pending.rawValue)
                .execute()
                .value
            guard loadingInvitationsHomeID == homeID, selectedHome?.id == homeID else { return }
            pendingInvitations = HomeInvitationDisplay.sorted(rows.map(\.display))
            loadedInvitationsHomeID = homeID
        } catch {
            guard loadingInvitationsHomeID == homeID, selectedHome?.id == homeID else { return }
            invitationsErrorMessage = invitationErrorMessage(for: error)
            debugLog(error, context: "LOAD HOME INVITATIONS")
        }

        if loadingInvitationsHomeID == homeID { loadingInvitationsHomeID = nil }
        if selectedHome?.id == homeID { isLoadingInvitations = false }
    }

    func createInvitation(homeID: UUID, email: String, role: HomeMemberRole) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { invitationsErrorMessage = "Enter a valid email address."; return false }
        guard role.canBeInvited else { invitationsErrorMessage = "Choose a supported role."; return false }
        guard !isCreatingInvitation else { return false }

        isCreatingInvitation = true
        invitationsErrorMessage = nil
        defer { isCreatingInvitation = false }
        do {
            try await client.rpc(
                "create_home_invitation",
                params: CreateHomeInvitationParameters(homeID: homeID, email: normalizedEmail, role: role)
            ).execute()
            loadedInvitationsHomeID = nil
            await loadPendingInvitations(homeID: homeID, forceRefresh: true)
            return invitationsErrorMessage == nil
        } catch {
            invitationsErrorMessage = invitationErrorMessage(for: error)
            debugLog(error, context: "CREATE HOME INVITATION")
            return false
        }
    }

    func cancelInvitation(_ invitation: HomeInvitationDisplay) async -> Bool {
        guard cancellingInvitationID == nil else { return false }
        cancellingInvitationID = invitation.id
        invitationsErrorMessage = nil
        defer { cancellingInvitationID = nil }
        do {
            try await client.rpc(
                "cancel_home_invitation",
                params: InvitationIDParameters(invitationID: invitation.id)
            ).execute()
            pendingInvitations.removeAll { $0.id == invitation.id }
            return true
        } catch {
            invitationsErrorMessage = invitationErrorMessage(for: error)
            debugLog(error, context: "CANCEL HOME INVITATION")
            return false
        }
    }

    func loadMyPendingInvitations(userID: UUID, forceRefresh: Bool = false) async {
        if isLoadingMyInvitations { return }
        if !forceRefresh, loadedInvitationUserID == userID { return }
        isLoadingMyInvitations = true
        loadingInvitationUserID = userID
        myInvitationsErrorMessage = nil
        if loadedInvitationUserID != userID { myPendingInvitations = [] }
        do {
            let rows: [MyHomeInvitationResponse] = try await client
                .rpc("get_my_pending_home_invitations")
                .execute()
                .value
            guard loadingInvitationUserID == userID else { return }
            myPendingInvitations = HomeInvitationDisplay.sorted(rows.map(\.display))
            loadedInvitationUserID = userID
        } catch {
            guard loadingInvitationUserID == userID else { return }
            myInvitationsErrorMessage = invitationErrorMessage(for: error)
            debugLog(error, context: "LOAD MY HOME INVITATIONS")
        }
        if loadingInvitationUserID == userID {
            loadingInvitationUserID = nil
            isLoadingMyInvitations = false
        }
    }

    func acceptInvitation(_ invitation: HomeInvitationDisplay, currentUserID: UUID) async -> AcceptedHomeInvitationResult? {
        guard acceptingInvitationID == nil else { return nil }
        acceptingInvitationID = invitation.id
        myInvitationsErrorMessage = nil
        defer { acceptingInvitationID = nil }
        do {
            let homeID: UUID = try await client.rpc(
                "accept_home_invitation",
                params: InvitationIDParameters(invitationID: invitation.id)
            ).execute().value
            myPendingInvitations.removeAll { $0.id == invitation.id }
            loadedInvitationUserID = nil
            let previousHomeID = selectedHome?.id
            _ = await refreshHomes(for: currentUserID, preservingHomeID: previousHomeID)
            await loadMyPendingInvitations(userID: currentUserID, forceRefresh: true)
            NotificationCenter.default.post(name: .homeyMembersDidChange, object: homeID)
            return AcceptedHomeInvitationResult(homeID: homeID, homeName: invitation.homeName ?? "Home")
        } catch {
            myInvitationsErrorMessage = invitationErrorMessage(for: error)
            debugLog(error, context: "ACCEPT HOME INVITATION")
            return nil
        }
    }

    func declineInvitation(_ invitation: HomeInvitationDisplay, currentUserID: UUID) async -> Bool {
        guard decliningInvitationID == nil else { return false }
        decliningInvitationID = invitation.id
        myInvitationsErrorMessage = nil
        defer { decliningInvitationID = nil }
        do {
            try await client.rpc(
                "decline_home_invitation",
                params: InvitationIDParameters(invitationID: invitation.id)
            ).execute()
            myPendingInvitations.removeAll { $0.id == invitation.id }
            loadedInvitationUserID = nil
            await loadMyPendingInvitations(userID: currentUserID, forceRefresh: true)
            return true
        } catch {
            myInvitationsErrorMessage = invitationErrorMessage(for: error)
            debugLog(error, context: "DECLINE HOME INVITATION")
            return false
        }
    }

    func updateHomeSettings(
        homeID: UUID,
        name: String,
        timezone: String,
        weekStartsOn: Int,
        userID: UUID
    ) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { errorMessage = "Home name is required."; return false }
        guard TimeZone(identifier: cleanTimezone) != nil else { errorMessage = "Choose a valid timezone."; return false }
        guard weekStartsOn == 1 || weekStartsOn == 2 else { errorMessage = "Choose Sunday or Monday as the week start."; return false }
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let _: UpdatedHomeID = try await client
                .from("homes")
                .update(UpdateHomeSettingsParameters(name: cleanName, timezone: cleanTimezone, weekStartsOn: weekStartsOn))
                .eq("id", value: homeID.uuidString)
                .select("id")
                .single()
                .execute()
                .value
            await loadHomes(for: userID, preferredHomeID: homeID)
            return selectedHome?.id == homeID
        } catch {
            errorMessage = "We couldn't save these Home settings. Check your permissions and try again."
            debugLog(error, context: "UPDATE HOME SETTINGS")
            return false
        }
    }

    func select(_ home: HomeSummary) { setSelectedHome(home) }
    func reset() {
        homesLoadID = UUID()
        homes = []
        setSelectedHome(nil)
        myPendingInvitations = []
        loadedInvitationUserID = nil
        loadingInvitationUserID = nil
        isLoadingMyInvitations = false
        acceptingInvitationID = nil
        decliningInvitationID = nil
        errorMessage = nil
        myInvitationsErrorMessage = nil
    }

    private func setSelectedHome(_ home: HomeSummary?) {
        guard selectedHome?.id != home?.id else {
            selectedHome = home
            return
        }
        selectedHome = home
        members = []
        pendingInvitations = []
        loadedMembersHomeID = nil
        loadingMembersHomeID = nil
        loadedInvitationsHomeID = nil
        loadingInvitationsHomeID = nil
        isLoadingMembers = false
        isLoadingInvitations = false
        cancellingInvitationID = nil
        membersErrorMessage = nil
        invitationsErrorMessage = nil
    }

    private func refreshSelectedHomeSummary(role: HomeMemberRole, memberCount: Int) {
        guard let current = selectedHome else { return }
        let refreshed = HomeSummary(
            id: current.id,
            name: current.name,
            timezone: current.timezone,
            role: role,
            createdAt: current.createdAt,
            memberCount: memberCount,
            weekStartsOn: current.weekStartsOn
        )
        selectedHome = refreshed
        if let index = homes.firstIndex(where: { $0.id == current.id }) { homes[index] = refreshed }
    }

    private func fetchHomes(for userID: UUID) async throws -> [HomeSummary] {
        let memberships: [HomeMembershipResponse] = try await client
            .from("home_members")
            .select("role, homes(id, name, timezone, week_starts_on, created_at)")
            .eq("user_id", value: userID.uuidString)
            .execute().value
        return memberships.compactMap { $0.summary() }.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : comparison == .orderedAscending
        }
    }

    private func memberErrorMessage(for error: Error) -> String {
        let message = backendMessage(for: error)
        if message.lowercased().contains("permission") || message.lowercased().contains("policy") {
            return "You do not have permission to view members for this Home."
        }
        return message.isEmpty ? "We couldn't load this Home's members." : message
    }

    private func invitationErrorMessage(for error: Error) -> String {
        let message = backendMessage(for: error)
        let normalized = message.lowercased()
        if normalized.contains("duplicate") || normalized.contains("unique") { return "An invitation is already pending for this email." }
        if normalized.contains("permission") || normalized.contains("policy") || normalized.contains("rls") { return "You do not have permission to manage invitations for this Home." }
        if normalized.contains("expired") { return "This invitation has expired." }
        if normalized.contains("cancelled") || normalized.contains("canceled") || normalized.contains("revoked") { return "This invitation is no longer available." }
        if normalized.contains("different email") || (normalized.contains("email") && normalized.contains("match")) { return "This invitation was sent to a different email address." }
        if normalized.contains("already") && normalized.contains("member") { return "You are already a member of this Home." }
        return message.isEmpty ? "The invitation could not be updated. Please try again." : message
    }

    private func backendMessage(for error: Error) -> String {
        (error as? PostgrestError)?.message ?? error.localizedDescription
    }
    private func debugLog(_ error: Error, context: String) {
        #if DEBUG
        print("[Homey] \(context): \(String(reflecting: error))")
        #endif
    }
}

private enum HomeSelectionError: LocalizedError {
    case membershipUnavailable

    var errorDescription: String? {
        "You no longer have access to that Home. Refresh the list and choose another Home."
    }
}

private struct CreateHomeParameters: Encodable {
    let homeName: String; let homeTimezone: String
    enum CodingKeys: String, CodingKey { case homeName = "home_name"; case homeTimezone = "home_timezone" }
}

private struct UpdateHomeSettingsParameters: Encodable {
    let name: String
    let timezone: String
    let weekStartsOn: Int
    enum CodingKeys: String, CodingKey { case name, timezone; case weekStartsOn = "week_starts_on" }
}

private struct UpdatedHomeID: Decodable { let id: UUID }

private struct GetHomeMembersParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "target_home_id" }
}

private struct CreateHomeInvitationParameters: Encodable {
    let homeID: UUID
    let email: String
    let role: HomeMemberRole
    enum CodingKeys: String, CodingKey {
        case homeID = "target_home_id"
        case email = "invitee_email"
        case role = "invitation_role"
    }
}

private struct InvitationIDParameters: Encodable {
    let invitationID: UUID
    enum CodingKeys: String, CodingKey { case invitationID = "target_invitation_id" }
}

private struct HomeMemberListResponse: Decodable {
    let membershipID: UUID
    let homeID: UUID
    let userID: UUID
    let role: HomeMemberRole
    let joinedAt: String?
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let email: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case membershipID = "membership_id"
        case homeID = "home_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case email
        case avatarURL = "avatar_url"
    }

    func display(currentUserID: UUID) -> HomeMemberDisplay {
        HomeMemberDisplay(
            id: membershipID,
            homeID: homeID,
            userID: userID,
            role: role,
            joinedAt: joinedAt,
            firstName: firstName,
            lastName: lastName,
            profileDisplayName: displayName,
            email: email,
            avatarURL: avatarURL,
            isCurrentUser: userID == currentUserID
        )
    }
}

private struct HomeInvitationResponse: Decodable {
    let id: UUID
    let homeID: UUID
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID?
    let createdAt: String?
    let expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case id, email, role, status
        case homeID = "home_id"
        case invitedBy = "invited_by"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
    var display: HomeInvitationDisplay {
        HomeInvitationDisplay(id: id, homeID: homeID, email: email, role: role, status: status, invitedBy: invitedBy, createdAt: createdAt, expiresAt: expiresAt)
    }
}

private struct MyHomeInvitationResponse: Decodable {
    let invitationID: UUID
    let homeID: UUID
    let homeName: String
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID?
    let inviterName: String?
    let createdAt: String?
    let expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case invitationID = "invitation_id"
        case homeID = "home_id"
        case homeName = "home_name"
        case email, role, status
        case invitedBy = "invited_by"
        case inviterName = "inviter_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
    var display: HomeInvitationDisplay {
        HomeInvitationDisplay(
            id: invitationID,
            homeID: homeID,
            email: email,
            role: role,
            status: status,
            invitedBy: invitedBy,
            createdAt: createdAt,
            expiresAt: expiresAt,
            homeName: homeName,
            inviterDisplayName: inviterName
        )
    }
}

extension Notification.Name {
    static let homeyMembersDidChange = Notification.Name("homeyMembersDidChange")
    static let homeyProfileDidChange = Notification.Name("homeyProfileDidChange")
}
