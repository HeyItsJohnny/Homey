import Foundation
import Supabase

struct UserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String
    var firstName: String?
    var lastName: String?
    var displayName: String?
    var avatarURL: URL?

    init(id: UUID, email: String, firstName: String? = nil, lastName: String? = nil, displayName: String? = nil, avatarURL: URL? = nil) {
        self.id = id; self.email = email; self.firstName = firstName; self.lastName = lastName
        self.displayName = displayName; self.avatarURL = avatarURL
    }

    init(user: User) { self.init(id: user.id, email: user.email ?? "") }

    var preferredDisplayName: String {
        let fullName = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        return [displayName, fullName, email.split(separator: "@").first.map(String.init), "Homey Member"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Homey Member"
    }

    var initials: String {
        let parts = preferredDisplayName.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "HM" : value.uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id, email
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}
