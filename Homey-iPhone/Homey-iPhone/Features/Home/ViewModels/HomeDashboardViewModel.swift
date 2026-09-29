import Combine
import Foundation

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot = HomeDashboardSnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadedAt: Date?
    private let service = HomeDashboardService()
    private var loadedHomeID: UUID?
    private var loadedUserID: UUID?
    private var loadedRole: HomeMemberRole?
    private var activeLoadID = UUID()

    func load(home: HomeSummary, currentUserID: UUID?, role: HomeMemberRole?, force: Bool = false) async {
        let sameScope = loadedHomeID == home.id && loadedUserID == currentUserID && loadedRole == role
        if !force, sameScope, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 60 { return }
        let loadID = UUID()
        activeLoadID = loadID
        if !sameScope { snapshot = .empty; lastLoadedAt = nil }
        isLoading = true
        let loadedSnapshot = await service.load(home: home, currentUserID: currentUserID, role: role)
        guard activeLoadID == loadID else { return }
        snapshot = loadedSnapshot
        loadedHomeID = home.id
        loadedUserID = currentUserID
        loadedRole = role
        lastLoadedAt = Date()
        isLoading = false
    }
}
