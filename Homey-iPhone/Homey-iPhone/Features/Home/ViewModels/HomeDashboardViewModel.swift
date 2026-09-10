import Combine
import Foundation

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot = HomeDashboardSnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadedAt: Date?
    private let service = HomeDashboardService()
    private var loadedHomeID: UUID?

    func load(home: HomeSummary, role: HomeMemberRole?, force: Bool = false) async {
        if !force, loadedHomeID == home.id, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 60 { return }
        guard !isLoading else { return }
        isLoading = true
        snapshot = await service.load(home: home, role: role)
        loadedHomeID = home.id; lastLoadedAt = Date(); isLoading = false
    }
}
