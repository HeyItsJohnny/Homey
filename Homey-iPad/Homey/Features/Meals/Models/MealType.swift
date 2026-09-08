import Foundation

enum MealType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case dessert
    case drink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast:
            return "Breakfast"
        case .lunch:
            return "Lunch"
        case .dinner:
            return "Dinner"
        case .snack:
            return "Snack"
        case .dessert:
            return "Dessert"
        case .drink:
            return "Drink"
        }
    }

    var systemImageName: String {
        switch self {
        case .breakfast:
            return "sunrise.fill"
        case .lunch:
            return "takeoutbag.and.cup.and.straw.fill"
        case .dinner:
            return "fork.knife"
        case .snack:
            return "carrot.fill"
        case .dessert:
            return "birthday.cake.fill"
        case .drink:
            return "cup.and.saucer.fill"
        }
    }
}
