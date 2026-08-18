import Foundation

enum ChoreCreationSheet: Identifiable {
    case chore
    case reward

    var id: String {
        switch self {
        case .chore:
            return "chore"
        case .reward:
            return "reward"
        }
    }
}
