import Combine
import Foundation

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot = HomeDashboardSnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadedAt: Date?
    private let service = HomeDashboardService()
    private var loadedHomeID: UUID?
    private var activeLoadID = UUID()

    func load(home: HomeSummary, role: HomeMemberRole?, force: Bool = false) async {
        if !force, loadedHomeID == home.id, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 60 { return }
        let loadID = UUID()
        activeLoadID = loadID
        if loadedHomeID != home.id { snapshot = .empty; lastLoadedAt = nil }
        isLoading = true
        let loadedSnapshot = await service.load(home: home, role: role)
        guard activeLoadID == loadID else { return }
        snapshot = loadedSnapshot
        loadedHomeID = home.id
        lastLoadedAt = Date()
        isLoading = false
    }
}
