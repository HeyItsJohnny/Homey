import Foundation

enum ChoresTab: String, CaseIterable, Identifiable {
    case myChores
    case myRewards
    case houseChores
    case rewardCenter
    case choreHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myChores:
            return "My Chores"
        case .myRewards:
            return "My Rewards"
        case .houseChores:
            return "House Chores"
        case .rewardCenter:
            return "Reward Center"
        case .choreHistory:
            return "Chore History"
        }
    }

    static let memberVisibleTabs: [ChoresTab] = [
        .myChores,
        .myRewards,
        .choreHistory
    ]

    static let ownerAdminVisibleTabs: [ChoresTab] = [
        .myChores,
        .myRewards,
        .houseChores,
        .rewardCenter,
        .choreHistory
    ]
}
