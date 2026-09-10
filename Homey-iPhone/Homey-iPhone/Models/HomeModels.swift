import Foundation

enum HomeMemberRole: String, Codable, CaseIterable, Identifiable {
    case owner, admin, member
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct HomeSummary: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let timezone: String?
    let role: HomeMemberRole?
    let createdAt: String?
    let memberCount: Int
    let weekStartsOn: Int
}

private struct HomeRecord: Decodable {
    let id: UUID
    let name: String
    let timezone: String?
    let weekStartsOn: Int
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case weekStartsOn = "week_starts_on"
        case createdAt = "created_at"
    }
}

struct HomeMembershipResponse: Decodable {
    let role: HomeMemberRole?
    fileprivate let home: HomeRecord?
    enum CodingKeys: String, CodingKey { case role; case home = "homes" }

    func summary(memberCount: Int = 0) -> HomeSummary? {
        guard let home else { return nil }
        return HomeSummary(id: home.id, name: home.name, timezone: home.timezone, role: role,
                           createdAt: home.createdAt, memberCount: memberCount, weekStartsOn: home.weekStartsOn)
    }
}
