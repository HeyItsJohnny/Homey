import Foundation

enum DashboardDestination: Hashable { case calendar, meals, chores, groceries }

struct HomeAttentionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let destination: DashboardDestination
}

struct HomeUpcomingItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let colorHex: String?
    let destination: DashboardDestination
}

struct HomeDashboardSnapshot {
    var attentionItems: [HomeAttentionItem] = []
    var upcomingEvents: [HomeUpcomingItem] = []
    var tonightMeal: String?
    var choresDueToday: Int?
    var dinnersPlanned: Int?
    var upcomingEventCount: Int?
    var failedSections: Set<DashboardSection> = []

    static let empty = HomeDashboardSnapshot()
}

enum DashboardSection: String, Hashable { case chores, rewards, calendar, meals }
