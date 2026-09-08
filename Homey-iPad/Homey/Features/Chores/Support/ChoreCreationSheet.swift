import Foundation

enum ChoreCreationSheet: Identifiable {
    case chore
    case room
    case reward

    var id: String {
        switch self {
        case .chore:
            return "chore"
        case .room:
            return "room"
        case .reward:
            return "reward"
        }
    }
}
