import Foundation

struct HomeMemberDisplay: Identifiable, Hashable {
    let id: UUID
    let homeId: UUID
    let userId: UUID
    let role: HomeMemberRole
    let joinedAt: String?
    let firstName: String?
    let lastName: String?
    let profileDisplayName: String?
    let email: String?
    let avatarURL: URL?
    let isCurrentUser: Bool

    init(
        id: UUID,
        homeId: UUID = UUID(),
        userId: UUID,
        role: HomeMemberRole,
        joinedAt: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        profileDisplayName: String? = nil,
        displayName: String? = nil,
        email: String?,
        avatarURL: URL?,
        isCurrentUser: Bool
    ) {
        self.id = id
        self.homeId = homeId
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
        self.firstName = firstName
        self.lastName = lastName
        self.profileDisplayName = profileDisplayName ?? displayName
        self.email = email
        self.avatarURL = avatarURL
        self.isCurrentUser = isCurrentUser
    }

    init(
        id: UUID,
        userId: UUID,
        displayName: String,
        email: String?,
        role: HomeMemberRole,
        avatarURL: URL?,
        isCurrentUser: Bool
    ) {
        self.init(
            id: id,
            userId: userId,
            role: role,
            profileDisplayName: displayName,
            email: email,
            avatarURL: avatarURL,
            isCurrentUser: isCurrentUser
        )
    }

    var displayName: String {
        Self.resolvedDisplayName(
            displayName: profileDisplayName,
            firstName: firstName,
            lastName: lastName,
            email: email
        )
    }

    var initials: String {
        let firstInitial = firstName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0) }
        let lastInitial = lastName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0) }
        let nameInitials = [firstInitial, lastInitial]
            .compactMap { $0 }
            .joined()

        if !nameInitials.isEmpty {
            return nameInitials.uppercased()
        }

        let displayInitials = (profileDisplayName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()

        if !displayInitials.isEmpty {
            return displayInitials.uppercased()
        }

        let emailUsername = email?
            .split(separator: "@")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        if let firstEmailCharacter = emailUsername.first {
            return String(firstEmailCharacter).uppercased()
        }

        return "HM"
    }

    var formattedRole: String {
        role.displayName
    }

    var roleSortRank: Int {
        switch role {
        case .owner:
            return 0
        case .admin:
            return 1
        case .member:
            return 2
        }
    }

    static func sorted(_ members: [HomeMemberDisplay]) -> [HomeMemberDisplay] {
        members.sorted { lhs, rhs in
            if lhs.roleSortRank != rhs.roleSortRank {
                return lhs.roleSortRank < rhs.roleSortRank
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func resolvedDisplayName(displayName: String?, firstName: String?, lastName: String?, email: String?) -> String {
        let customDisplayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        if !customDisplayName.isEmpty {
            return customDisplayName
        }

        let generatedName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !generatedName.isEmpty {
            return generatedName
        }

        let emailUsername = email?
            .split(separator: "@")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        if !emailUsername.isEmpty {
            return emailUsername
        }

        return "Home Member"
    }
}
