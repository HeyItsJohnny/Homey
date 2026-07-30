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
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    init(user: User) {
        self.id = user.id
        self.email = user.email ?? ""
        self.firstName = nil
        self.lastName = nil
        self.displayName = nil
        self.avatarURL = nil
    }

    var generatedDisplayName: String {
        ProfileNameFormatter.generatedDisplayName(firstName: firstName ?? "", lastName: lastName ?? "")
    }

    var preferredDisplayName: String {
        let candidates = [
            displayName,
            generatedDisplayName,
            email.split(separator: "@").first.map(String.init),
            "Homey Member"
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Homey Member"
    }

    var bestDisplayName: String {
        preferredDisplayName
    }

    func withAvatarURL(_ avatarURL: URL?) -> UserProfile {
        UserProfile(
            id: id,
            email: email,
            firstName: firstName,
            lastName: lastName,
            displayName: displayName,
            avatarURL: avatarURL
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

        let displayInitials = preferredDisplayName
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()

        return displayInitials.isEmpty ? "HM" : displayInitials.uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}

enum ProfileNameFormatter {
    static func generatedDisplayName(firstName: String, lastName: String) -> String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
