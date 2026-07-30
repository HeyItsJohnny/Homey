import Foundation

struct HomeInvitationDisplay: Identifiable, Hashable {
    let id: UUID
    let homeID: UUID
    let email: String
    let role: HomeMemberRole
    let status: HomeInvitationStatus
    let invitedBy: UUID?
    let createdAt: String?
    let expiresAt: String?
    var homeName: String? = nil
    var inviterDisplayName: String? = nil

    var formattedRole: String {
        role.displayName
    }

    var formattedStatus: String {
        status.displayName
    }

    var invitedDateText: String {
        guard let createdAt,
              let createdDate = HomeInvitationDateParser.date(from: createdAt) else {
            return "Invited recently"
        }

        return "Invited \(createdDate.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var expirationText: String? {
        guard let expiresAt,
              let expirationDate = HomeInvitationDateParser.date(from: expiresAt) else {
            return nil
        }

        return "Expires \(expirationDate.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    static func sorted(_ invitations: [HomeInvitationDisplay]) -> [HomeInvitationDisplay] {
        invitations.sorted { lhs, rhs in
            let lhsDate = lhs.createdAt.flatMap(HomeInvitationDateParser.date(from:)) ?? .distantPast
            let rhsDate = rhs.createdAt.flatMap(HomeInvitationDateParser.date(from:)) ?? .distantPast

            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
        }
    }
}

private enum HomeInvitationDateParser {
    nonisolated static func date(from value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        return standardFormatter.date(from: value)
    }
}
