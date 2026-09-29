import Foundation

enum DashboardDestination: Hashable { case calendar, meals, chores, groceries }

struct HomeAttentionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let destination: DashboardDestination
}

struct DashboardTodayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startsAt: Date
    let isAllDay: Bool
    let location: String?
    let colorHex: String?
}

struct DashboardTodayMeal: Identifiable, Hashable {
    let id: String
    let mealID: UUID
    let title: String
    let mealType: MealType
    let photoPath: String?
}

struct DashboardTodayChore: Identifiable {
    let id: UUID
    let title: String
    let roomName: String?
    let assigneeNames: [String]
    let status: PhoneChoreOccurrenceStatus
}

struct DashboardMealCounts: Hashable {
    var breakfast = 0
    var lunch = 0
    var dinner = 0

    subscript(type: MealType) -> Int {
        switch type {
        case .breakfast: breakfast
        case .lunch: lunch
        case .dinner: dinner
        default: 0
        }
    }
}

struct HomeDashboardSnapshot {
    var attentionItems: [HomeAttentionItem] = []
    var todayEvents: [DashboardTodayEvent] = []
    var todayMeals: [DashboardTodayMeal] = []
    var todayChores: [DashboardTodayChore] = []
    var mealCounts = DashboardMealCounts()
    var calendarDataLoaded = false
    var mealDataLoaded = false
    var choreRoleResolved = false
    var choreDataLoaded = false
    var failedSections: Set<DashboardSection> = []

    static let empty = HomeDashboardSnapshot()
}

enum DashboardSection: String, Hashable { case approvals, chores, rewards, calendar, meals }
