import Foundation

enum HomeMemberRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case admin
    case member

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let role = HomeMemberRole(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Home member role: \(rawValue)"
            )
        }

        self = role
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .owner:
            return "Owner"
        case .admin:
            return "Admin"
        case .member:
            return "Member"
        }
    }

    var canBeInvited: Bool {
        switch self {
        case .admin, .member:
            return true
        case .owner:
            return false
        }
    }

    static var invitationOptions: [HomeMemberRole] {
        [.member, .admin]
    }

    var canManageCalendarCategories: Bool {
        switch self {
        case .owner, .admin:
            return true
        case .member:
            return false
        }
    }
}

enum HomeInvitationStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case declined
    case cancelled
    case expired

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        case .declined:
            return "Declined"
        case .cancelled:
            return "Cancelled"
        case .expired:
            return "Expired"
        }
    }
}
