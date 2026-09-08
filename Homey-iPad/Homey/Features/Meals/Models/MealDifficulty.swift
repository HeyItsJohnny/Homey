import Foundation

enum MealDifficulty: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy:
            return "Easy"
        case .medium:
            return "Medium"
        case .hard:
            return "Hard"
        }
    }
}
