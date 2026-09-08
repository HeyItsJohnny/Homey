import Foundation

struct HomeSummary: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let timezone: String?
    let role: HomeMemberRole?
    let createdAt: String?
    let memberCount: Int
    let weekStartsOn: Int
}
