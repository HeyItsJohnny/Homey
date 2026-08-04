import Foundation

enum AutoPlanRecipePoolMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case includeFavorites
    case allRecipes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .includeFavorites:
            return "Include Favorites"
        case .allRecipes:
            return "All Recipes"
        }
    }

    var description: String {
        switch self {
        case .includeFavorites:
            return "Uses your full recipe library while aiming to include a balanced mix of family members' personal favorites."
        case .allRecipes:
            return "Plans from all eligible recipes without prioritizing favorites."
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "householdFavoritesOnly", "householdFavoritesFirst", "includeFavorites":
            self = .includeFavorites
        case "allRecipes":
            self = .allRecipes
        default:
            self = .includeFavorites
        }
    }
}

struct AutoPlanConfiguration: Hashable, Sendable {
    static let defaultFavoriteTargetRatio = 0.35

    var selectedDates: Set<Date>
    var selectedMealTypes: Set<MealType>
    var recipePool: AutoPlanRecipePoolMode
    var allowsRepeats: Bool

    static func defaultConfiguration(weekDays: [Date]) -> AutoPlanConfiguration {
        AutoPlanConfiguration(
            selectedDates: Set(weekDays),
            selectedMealTypes: [.breakfast, .lunch, .dinner, .snack],
            recipePool: .includeFavorites,
            allowsRepeats: false
        )
    }
}

struct AutoPlanSlotID: Hashable, Sendable, CustomStringConvertible {
    let dayKey: String
    let mealType: MealType

    var description: String {
        "\(dayKey)-\(mealType.rawValue)"
    }
}

struct AutoPlanSlot: Identifiable, Hashable, Sendable {
    let id: AutoPlanSlotID
    let date: Date
    let mealType: MealType
    var existingPlannedMeals: [PlannedMeal]
    var suggestion: AutoPlanSuggestion?

    var isFilled: Bool {
        !existingPlannedMeals.isEmpty
    }
}

enum AutoPlanSuggestionStatus: Hashable, Sendable {
    case existing
    case suggested
    case manuallySelected
    case noSuggestion

    var title: String {
        switch self {
        case .existing:
            return "Existing"
        case .suggested:
            return "Suggested"
        case .manuallySelected:
            return "Manually Selected"
        case .noSuggestion:
            return "No Suggestion"
        }
    }
}

struct AutoPlanSuggestion: Identifiable, Hashable, Sendable {
    let id = UUID()
    var meal: Meal?
    var status: AutoPlanSuggestionStatus
    var attributedMemberId: UUID?
    var favoriteMemberIds: [UUID]
    var score: Int
    var explanation: String

    var isCreatable: Bool {
        status == .suggested || status == .manuallySelected
    }
}

struct AutoPlanDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    let homeId: UUID
    let weekStart: Date
    let weekEnd: Date
    var configuration: AutoPlanConfiguration
    var slots: [AutoPlanSlot]
    var memberSuggestionCounts: [UUID: Int]
    var generatedAt: Date

    var creatableSlots: [AutoPlanSlot] {
        slots.filter { $0.suggestion?.isCreatable == true && $0.suggestion?.meal != nil }
    }
}

struct AutoPlanMember: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
}

struct AutoPlanResultSummary: Hashable, Sendable {
    let plannedCount: Int
    let skippedCount: Int
    let failedCount: Int

    var message: String {
        var parts: [String] = []
        if plannedCount == 1 {
            parts.append("1 meal was planned")
        } else {
            parts.append("\(plannedCount) meals were planned")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped because the slot was already filled")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) could not be scheduled")
        }
        return parts.joined(separator: ". ") + "."
    }
}
