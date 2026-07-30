import Foundation
import Supabase

struct UserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String
    var firstName: String?
    var lastName: String?
    var displayName: String?

    init(id: UUID, email: String, firstName: String? = nil, lastName: String? = nil, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
    }

    init(user: User) {
        self.id = user.id
        self.email = user.email ?? ""
        self.firstName = nil
        self.lastName = nil
        self.displayName = nil
    }

    var generatedDisplayName: String {
        ProfileNameFormatter.generatedDisplayName(firstName: firstName ?? "", lastName: lastName ?? "")
    }

    var bestDisplayName: String {
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

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
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
