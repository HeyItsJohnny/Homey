import Combine
import Foundation
import PostgREST
import Supabase

@MainActor
final class HomeService: ObservableObject {
    // MARK: - Published State

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
    @Published var selectedHomeID: UUID?
    @Published var errorMessage: String?
    @Published var membersErrorMessage: String?
    @Published var invitationsErrorMessage: String?
    @Published var myInvitationsErrorMessage: String?

    // MARK: - Private Properties

    private let client = SupabaseManager.shared.client
    private var loadedMembersHomeID: UUID?
    private var loadedInvitationsHomeID: UUID?
    private var loadedInvitationUserID: UUID?

    // MARK: - Loading

    func loadHomes(for userID: UUID) async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            homes = try await fetchHomes(for: userID)
            restoreOrSelectHome()
        } catch {
            homes = []
            setSelectedHomeID(nil)
            errorMessage = "Unable to load your Homes."

            #if DEBUG
            print("Failed to load Homes: \(error)")
            #endif
        }

        isLoading = false
    }

    func createHome(name: String, timezone: String, userID: UUID) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a Home name."
            return false
        }

        guard !trimmedTimezone.isEmpty else {
            errorMessage = "Enter a timezone."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            #if DEBUG
            print("Creating Home...")
            print("home_name: \(trimmedName)")
            print("home_timezone: \(trimmedTimezone)")
            #endif

            let createdHomeID: UUID = try await client
                .rpc(
                    "create_home",
                    params: CreateHomeRPCParameters(
                        homeName: trimmedName,
                        homeTimezone: trimmedTimezone
                    )
                )
                .execute()
                .value

            homes = try await fetchHomes(for: userID)
            setSelectedHomeID(createdHomeID)
            restoreOrSelectHome()
            isLoading = false
            return true
        } catch {
            errorMessage = "Unable to create Home."

            #if DEBUG
            print("Failed to create Home: \(error)")
            #endif

            isLoading = false
            return false
        }
    }

    func updateHomeSettings(homeID: UUID, name: String, timezone: String, weekStartsOn: Int, userID: UUID) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Home name is required."
            return false
        }

        guard !trimmedTimezone.isEmpty else {
            errorMessage = "Choose a timezone."
            return false
        }

        guard weekStartsOn == 1 || weekStartsOn == 2 else {
            errorMessage = "Choose Sunday or Monday as the week start."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try await client
                .from("homes")
                .update(
                    UpdateHomeSettingsParams(
                        name: trimmedName,
                        timezone: trimmedTimezone,
                        weekStartsOn: weekStartsOn
                    )
                )
                .eq("id", value: homeID.uuidString)
                .execute()

            homes = try await fetchHomes(for: userID)
            setSelectedHomeID(homeID)
            restoreOrSelectHome()
            isLoading = false
            return true
        } catch {
            errorMessage = homeErrorMessage(for: error)

            #if DEBUG
            print("Failed to update Home settings: \(error)")
            #endif

            isLoading = false
            return false
        }
    }

    func selectHome(id: UUID?) {
        setSelectedHomeID(id)
    }

    func restoreSelectedHome(from storedValue: String?) {
        setSelectedHomeID(storedValue.flatMap(UUID.init(uuidString:)))
        restoreOrSelectHome()
    }

    func selectedHome() -> HomeSummary? {
        guard let selectedHomeID else {
            return nil
        }

        return homes.first { $0.id == selectedHomeID }
    }

    func membersForSelectedHome() -> [HomeMemberDisplay] {
        guard loadedMembersHomeID == selectedHomeID else {
            return []
        }

        return members
    }

    func memberCountForSelectedHome() -> Int? {
        guard loadedMembersHomeID == selectedHomeID else {
            return nil
        }

        return members.count
    }

    func hasLoadedMembersForSelectedHome() -> Bool {
        loadedMembersHomeID == selectedHomeID
    }

    func loadMembers(for homeID: UUID, currentUser: UserProfile, forceRefresh: Bool = false) async {
        guard !isLoadingMembers else {
            return
        }

        if !forceRefresh && loadedMembersHomeID == homeID {
            return
        }

        isLoadingMembers = true
        membersErrorMessage = nil

        if loadedMembersHomeID != homeID {
            members = []
        }

        do {
            let loadedMembers = try await fetchMembers(for: homeID, currentUser: currentUser)
            members = HomeMemberDisplay.sorted(loadedMembers)
            loadedMembersHomeID = homeID
        } catch {
            membersErrorMessage = homeErrorMessage(for: error)

            #if DEBUG
            print("Failed to load Home members via RPC get_home_members")
            print("target_home_id: \(homeID.uuidString)")
            print(String(reflecting: error))
            if let postgrestError = error as? PostgrestError {
                print("PostgREST code: \(postgrestError.code ?? "")")
                print("PostgREST message: \(postgrestError.message)")
                print("PostgREST detail: \(postgrestError.detail ?? "")")
                print("PostgREST hint: \(postgrestError.hint ?? "")")
            }
            #endif
        }

        isLoadingMembers = false
    }

    func refreshMembers(for homeID: UUID, currentUser: UserProfile) async {
        await loadMembers(for: homeID, currentUser: currentUser, forceRefresh: true)
    }

    func invitationsForSelectedHome() -> [HomeInvitationDisplay] {
        guard loadedInvitationsHomeID == selectedHomeID else {
            return []
        }

        return pendingInvitations
    }

    func hasLoadedInvitationsForSelectedHome() -> Bool {
        loadedInvitationsHomeID == selectedHomeID
    }

    func loadPendingInvitations(for homeID: UUID, forceRefresh: Bool = false) async {
        guard !isLoadingInvitations else {
            return
        }

        if !forceRefresh && loadedInvitationsHomeID == homeID {
            return
        }

        isLoadingInvitations = true
        invitationsErrorMessage = nil

        if loadedInvitationsHomeID != homeID {
            pendingInvitations = []
        }

        do {
            pendingInvitations = HomeInvitationDisplay.sorted(try await fetchPendingInvitations(for: homeID))
            loadedInvitationsHomeID = homeID
        } catch {
            invitationsErrorMessage = invitationErrorMessage(for: error)

            #if DEBUG
            print("Failed to load Home invitations: \(error)")
            #endif
        }

        isLoadingInvitations = false
    }

    func refreshPendingInvitations(for homeID: UUID) async {
        await loadPendingInvitations(for: homeID, forceRefresh: true)
    }

    func loadMyPendingInvitations(for userID: UUID, forceRefresh: Bool = false) async {
        guard !isLoadingMyInvitations else {
            return
        }

        if !forceRefresh && loadedInvitationUserID == userID {
            return
        }

        isLoadingMyInvitations = true
        myInvitationsErrorMessage = nil

        if loadedInvitationUserID != userID {
            myPendingInvitations = []
        }

        do {
            myPendingInvitations = HomeInvitationDisplay.sorted(try await fetchMyPendingInvitations())
            loadedInvitationUserID = userID
        } catch {
            myInvitationsErrorMessage = invitationErrorMessage(for: error)

            #if DEBUG
            print("Failed to load my Home invitations: \(error)")
            #endif
        }

        isLoadingMyInvitations = false
    }

    func refreshMyPendingInvitations(for userID: UUID) async {
        await loadMyPendingInvitations(for: userID, forceRefresh: true)
    }

    func createInvitation(homeID: UUID, email: String, role: HomeMemberRole) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedEmail.isEmpty else {
            invitationsErrorMessage = "Enter a valid email address."
            return false
        }

        guard role.canBeInvited else {
            invitationsErrorMessage = "Choose a supported role."
            return false
        }

        guard !isCreatingInvitation else {
            return false
        }

        isCreatingInvitation = true
        invitationsErrorMessage = nil

        do {
            if try await pendingInvitationExists(homeID: homeID, email: normalizedEmail) {
                invitationsErrorMessage = "An invitation is already pending for this email."
                isCreatingInvitation = false
                return false
            }

            try await client
                .rpc(
                    "create_home_invitation",
                    params: CreateHomeInvitationRPCParameters(
                        targetHomeID: homeID,
                        inviteeEmail: normalizedEmail,
                        invitationRole: role
                    )
                )
                .execute()

            await refreshPendingInvitations(for: homeID)
            isCreatingInvitation = false
            return true
        } catch {
            invitationsErrorMessage = invitationErrorMessage(for: error)

            #if DEBUG
            print("Failed to create Home invitation: \(error)")
            #endif

            isCreatingInvitation = false
            return false
        }
    }

    func cancelInvitation(_ invitation: HomeInvitationDisplay) async -> Bool {
        guard cancellingInvitationID == nil else {
            return false
        }

        cancellingInvitationID = invitation.id
        invitationsErrorMessage = nil

        do {
            try await client
                .rpc(
                    "cancel_home_invitation",
                    params: InvitationIdRPCParameters(targetInvitationID: invitation.id)
                )
                .execute()

            await refreshPendingInvitations(for: invitation.homeID)
            cancellingInvitationID = nil
            return true
        } catch {
            invitationsErrorMessage = invitationErrorMessage(for: error)

            #if DEBUG
            print("Failed to cancel Home invitation: \(error)")
            #endif

            cancellingInvitationID = nil
            return false
        }
    }

    func acceptInvitation(_ invitation: HomeInvitationDisplay, currentUserID: UUID) async -> AcceptedHomeInvitationResult? {
        guard acceptingInvitationID == nil else {
            return nil
        }

        acceptingInvitationID = invitation.id
        myInvitationsErrorMessage = nil

        do {
            let acceptedHomeID: UUID = try await client
                .rpc(
                    "accept_home_invitation",
                    params: InvitationIdRPCParameters(targetInvitationID: invitation.id)
                )
                .execute()
                .value

            let result = AcceptedHomeInvitationResult(
                homeID: acceptedHomeID,
                homeName: invitation.homeName ?? "Home"
            )

            myPendingInvitations.removeAll { $0.id == invitation.id }
            await loadHomes(for: currentUserID)
            loadedInvitationUserID = nil
            await refreshMyPendingInvitations(for: currentUserID)
            acceptingInvitationID = nil
            return result
        } catch {
            myInvitationsErrorMessage = invitationErrorMessage(for: error)

            #if DEBUG
            print("Failed to accept Home invitation: \(error)")
            #endif

            acceptingInvitationID = nil
            return nil
        }
    }

    func declineInvitation(_ invitation: HomeInvitationDisplay, currentUserID: UUID) async -> Bool {
        guard decliningInvitationID == nil else {
            return false
        }

        decliningInvitationID = invitation.id
        myInvitationsErrorMessage = nil

        do {
            try await client
                .rpc(
                    "decline_home_invitation",
                    params: InvitationIdRPCParameters(targetInvitationID: invitation.id)
                )
                .execute()

            myPendingInvitations.removeAll { $0.id == invitation.id }
            loadedInvitationUserID = nil
            await refreshMyPendingInvitations(for: currentUserID)
            decliningInvitationID = nil
            return true
        } catch {
            myInvitationsErrorMessage = invitationErrorMessage(for: error)

            #if DEBUG
            print("Failed to decline Home invitation: \(error)")
            #endif

            decliningInvitationID = nil
            return false
        }
    }

    func clearAuthenticatedState() {
        homes = []
        members = []
        pendingInvitations = []
        myPendingInvitations = []
        isLoading = false
        isLoadingMembers = false
        isLoadingInvitations = false
        isLoadingMyInvitations = false
        isCreatingInvitation = false
        cancellingInvitationID = nil
        acceptingInvitationID = nil
        decliningInvitationID = nil
        selectedHomeID = nil
        errorMessage = nil
        membersErrorMessage = nil
        invitationsErrorMessage = nil
        myInvitationsErrorMessage = nil
        loadedMembersHomeID = nil
        loadedInvitationsHomeID = nil
        loadedInvitationUserID = nil
    }

    // MARK: - Private Helpers

    private func fetchHomes(for userID: UUID) async throws -> [HomeSummary] {
        let memberships: [HomeMembershipResponse] = try await client
            .from("home_members")
            .select("role, homes(id, name, timezone, week_starts_on, created_at)")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        var summaries: [HomeSummary] = []

        for membership in memberships {
            guard let home = membership.home else {
                continue
            }

            let memberCount = try await loadMemberCount(homeID: home.id)
            summaries.append(
                HomeSummary(
                    id: home.id,
                    name: home.name,
                    timezone: home.timezone,
                    role: membership.role,
                    createdAt: home.createdAt,
                    memberCount: memberCount,
                    weekStartsOn: home.weekStartsOn
                )
            )
        }

        return summaries
    }

    private func loadMemberCount(homeID: UUID) async throws -> Int {
        let members: [HomeMemberResponse] = try await client
            .from("home_members")
            .select("id")
            .eq("home_id", value: homeID.uuidString)
            .execute()
            .value

        return members.count
    }

    private func fetchMembers(for homeID: UUID, currentUser: UserProfile) async throws -> [HomeMemberDisplay] {
        let responses: [HomeMemberListResponse] = try await client
            .rpc(
                "get_home_members",
                params: GetHomeMembersParameters(targetHomeId: homeID)
            )
            .execute()
            .value

        return responses.map { response in
            HomeMemberDisplay(
                id: response.membershipID,
                homeId: response.homeID,
                userId: response.userID,
                role: response.role,
                joinedAt: response.joinedAt,
                firstName: response.firstName,
                lastName: response.lastName,
                profileDisplayName: response.displayName,
                email: response.email,
                avatarURL: response.avatarURL,
                isCurrentUser: response.userID == currentUser.id
            )
        }
    }

    private func fetchPendingInvitations(for homeID: UUID) async throws -> [HomeInvitationDisplay] {
        let responses: [HomeInvitationResponse] = try await client
            .from("home_invitations")
            .select("id, home_id, email, role, status, invited_by, created_at, expires_at")
            .eq("home_id", value: homeID.uuidString)
            .eq("status", value: HomeInvitationStatus.pending.rawValue)
            .execute()
            .value

        return responses.map { response in
            HomeInvitationDisplay(
                id: response.id,
                homeID: response.homeID,
                email: response.email,
                role: response.role,
                status: response.status,
                invitedBy: response.invitedBy,
                createdAt: response.createdAt,
                expiresAt: response.expiresAt
            )
        }
    }

    private func pendingInvitationExists(homeID: UUID, email: String) async throws -> Bool {
        let existingInvitations: [HomeInvitationIDResponse] = try await client
            .from("home_invitations")
            .select("id")
            .eq("home_id", value: homeID.uuidString)
            .eq("email", value: email)
            .eq("status", value: HomeInvitationStatus.pending.rawValue)
            .execute()
            .value

        return !existingInvitations.isEmpty
    }

    private func fetchMyPendingInvitations() async throws -> [HomeInvitationDisplay] {
        let responses: [MyHomeInvitationResponse] = try await client
            .rpc("get_my_pending_home_invitations")
            .execute()
            .value

        return responses.map { response in
            HomeInvitationDisplay(
                id: response.invitationID,
                homeID: response.homeID,
                email: response.email,
                role: response.role,
                status: response.status,
                invitedBy: response.invitedBy,
                createdAt: response.createdAt,
                expiresAt: response.expiresAt,
                homeName: response.homeName,
                inviterDisplayName: response.inviterName
            )
        }
    }

    private func homeErrorMessage(for error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.message
        }

        return error.localizedDescription
    }

    private func invitationErrorMessage(for error: Error) -> String {
        let message = homeErrorMessage(for: error)
        let lowercasedMessage = message.lowercased()

        if lowercasedMessage.contains("duplicate") || lowercasedMessage.contains("unique") {
            return "An invitation is already pending for this email."
        }

        if lowercasedMessage.contains("permission") || lowercasedMessage.contains("policy") || lowercasedMessage.contains("rls") {
            return "You do not have permission to manage invitations for this home."
        }

        if lowercasedMessage.contains("expired") {
            return "This invitation has expired."
        }

        if lowercasedMessage.contains("cancelled") || lowercasedMessage.contains("canceled") || lowercasedMessage.contains("revoked") {
            return "This invitation is no longer available."
        }

        if lowercasedMessage.contains("different email") || lowercasedMessage.contains("email") && lowercasedMessage.contains("match") {
            return "This invitation was sent to a different email address."
        }

        if lowercasedMessage.contains("already") && lowercasedMessage.contains("member") {
            return "You are already a member of this home."
        }

        return message.isEmpty ? "The invitation could not be updated. Please try again." : message
    }

    private func restoreOrSelectHome(preferredHomeName: String? = nil) {
        guard !homes.isEmpty else {
            setSelectedHomeID(nil)
            return
        }

        if let selectedHomeID, homes.contains(where: { $0.id == selectedHomeID }) {
            return
        }

        if let preferredHomeName,
           let preferredHome = homes.first(where: { $0.name == preferredHomeName }) {
            setSelectedHomeID(preferredHome.id)
        } else {
            setSelectedHomeID(homes[0].id)
        }
    }

    private func setSelectedHomeID(_ id: UUID?) {
        guard selectedHomeID != id else {
            return
        }

        selectedHomeID = id
        members = []
        loadedMembersHomeID = nil
        membersErrorMessage = nil
        pendingInvitations = []
        loadedInvitationsHomeID = nil
        invitationsErrorMessage = nil
    }
}

private struct CreateHomeRPCParameters: Encodable {
    let homeName: String
    let homeTimezone: String

    enum CodingKeys: String, CodingKey {
        case homeName = "home_name"
        case homeTimezone = "home_timezone"
    }
}

private struct UpdateHomeSettingsParams: Encodable {
    let name: String
    let timezone: String
    let weekStartsOn: Int

    enum CodingKeys: String, CodingKey {
        case name
        case timezone
        case weekStartsOn = "week_starts_on"
    }
}

private struct GetHomeMembersParameters: Encodable {
    let targetHomeId: UUID

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
    }
}

private struct CreateHomeInvitationRPCParameters: Encodable {
    let targetHomeID: UUID
    let inviteeEmail: String
    let invitationRole: HomeMemberRole

    enum CodingKeys: String, CodingKey {
        case targetHomeID = "target_home_id"
        case inviteeEmail = "invitee_email"
        case invitationRole = "invitation_role"
    }
}

struct AcceptedHomeInvitationResult: Hashable {
    let homeID: UUID
    let homeName: String
}

private struct InvitationIdRPCParameters: Encodable {
    let targetInvitationID: UUID

    enum CodingKeys: String, CodingKey {
        case targetInvitationID = "target_invitation_id"
    }
}

private struct HomeMembershipResponse: Decodable {
    let role: HomeMemberRole?
    let home: HomeResponse?

    enum CodingKeys: String, CodingKey {
        case role
        case home = "homes"
    }
}

private struct HomeResponse: Decodable {
    let id: UUID
    let name: String
    let timezone: String?
    let createdAt: String?
    let weekStartsOn: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case timezone
        case createdAt = "created_at"
        case weekStartsOn = "week_starts_on"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        weekStartsOn = try container.decodeIfPresent(Int.self, forKey: .weekStartsOn) ?? 1
    }
}

private struct HomeMemberResponse: Decodable {
    let id: UUID
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
        case id
        case homeID = "home_id"
        case email
        case role
        case status
        case invitedBy = "invited_by"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

private struct HomeInvitationIDResponse: Decodable {
    let id: UUID
}

private struct MyHomeInvitationResponse: Decodable {
    let invitationID: UUID
    let homeID: UUID
    let homeName: String
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID
    let inviterName: String
    let createdAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case invitationID = "invitation_id"
        case homeID = "home_id"
        case homeName = "home_name"
        case email
        case role
        case status
        case invitedBy = "invited_by"
        case inviterName = "inviter_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}
