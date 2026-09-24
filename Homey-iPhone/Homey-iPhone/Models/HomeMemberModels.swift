import Foundation

struct HomeMemberDisplay: Identifiable, Hashable {
    let id: UUID
    let homeID: UUID
    let userID: UUID
    let role: HomeMemberRole
    let joinedAt: String?
    let firstName: String?
    let lastName: String?
    let profileDisplayName: String?
    let email: String?
    let avatarURL: URL?
    let isCurrentUser: Bool

    var displayName: String {
        let customName = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customName.isEmpty { return customName }

        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }

        let emailName = email?.split(separator: "@").first.map(String.init) ?? ""
        return emailName.isEmpty ? "Home Member" : emailName
    }

    var initials: String {
        let parts = displayName.split { !$0.isLetter && !$0.isNumber }.prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "HM" : value.uppercased()
    }

    var joinedDateText: String? {
        guard let joinedAt, let date = HomeMemberDateParser.date(from: joinedAt) else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var roleSortRank: Int {
        switch role {
        case .owner: 0
        case .admin: 1
        case .member: 2
        }
    }

    static func sorted(_ members: [HomeMemberDisplay]) -> [HomeMemberDisplay] {
        members.sorted { lhs, rhs in
            if lhs.roleSortRank != rhs.roleSortRank { return lhs.roleSortRank < rhs.roleSortRank }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}

enum HomeInvitationStatus: String, Codable {
    case pending, accepted, declined, cancelled, expired

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .cancelled: "Cancelled"
        case .expired: "Expired"
        }
    }
}

struct HomeInvitationDisplay: Identifiable, Hashable {
    let id: UUID
    let homeID: UUID
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID?
    let createdAt: String?
    let expiresAt: String?
    var homeName: String?
    var inviterDisplayName: String?

    var invitedDateText: String {
        guard let createdAt, let date = HomeMemberDateParser.date(from: createdAt) else { return "Invited recently" }
        return "Invited \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var expirationText: String? {
        guard let expiresAt, let date = HomeMemberDateParser.date(from: expiresAt) else { return nil }
        return "Expires \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    static func sorted(_ invitations: [HomeInvitationDisplay]) -> [HomeInvitationDisplay] {
        invitations.sorted { lhs, rhs in
            let lhsDate = lhs.createdAt.flatMap(HomeMemberDateParser.date(from:)) ?? .distantPast
            let rhsDate = rhs.createdAt.flatMap(HomeMemberDateParser.date(from:)) ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
        }
    }
}

struct AcceptedHomeInvitationResult: Hashable {
    let homeID: UUID
    let homeName: String
}

private enum HomeMemberDateParser {
    nonisolated static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
