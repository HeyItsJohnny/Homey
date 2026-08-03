import SwiftUI

struct HomePermissions: Equatable, Hashable, Sendable {
    let meals: MealPermissions

    init(meals: MealPermissions) {
        self.meals = meals
    }

    init(role: HomeMemberRole?) {
        self.meals = MealPermissions(role: role)
    }

    static let restrictive = HomePermissions(meals: .restrictive)
}

enum PermissionResolutionState: Equatable, Hashable, Sendable {
    case loading
    case resolved(HomePermissions)
    case unavailable

    var permissions: HomePermissions {
        switch self {
        case .loading, .unavailable:
            return .restrictive
        case .resolved(let permissions):
            return permissions
        }
    }

    var isResolved: Bool {
        if case .resolved = self {
            return true
        }
        return false
    }
}

private struct HomePermissionsEnvironmentKey: EnvironmentKey {
    static let defaultValue = HomePermissions.restrictive
}

private struct PermissionResolutionEnvironmentKey: EnvironmentKey {
    static let defaultValue = PermissionResolutionState.unavailable
}

extension EnvironmentValues {
    var homePermissions: HomePermissions {
        get { self[HomePermissionsEnvironmentKey.self] }
        set { self[HomePermissionsEnvironmentKey.self] = newValue }
    }

    var homePermissionResolution: PermissionResolutionState {
        get { self[PermissionResolutionEnvironmentKey.self] }
        set { self[PermissionResolutionEnvironmentKey.self] = newValue }
    }
}
