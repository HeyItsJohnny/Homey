import Combine
import Foundation

@MainActor
final class HomeDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot = HomeDashboardSnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var lastLoadedAt: Date?

    private let service = HomeDashboardService()
    private var activeScope: DashboardLoadScope?
    private var inFlightTask: Task<HomeDashboardSnapshot, Error>?
    private var activeLoadID = UUID()

    func load(home: HomeSummary, currentUserID: UUID?, role: HomeMemberRole?, force: Bool = false) async {
        let scope = DashboardLoadScope(homeID: home.id, userID: currentUserID, role: role)

        if activeScope == scope, let inFlightTask {
            _ = try? await inFlightTask.value
            return
        }

        let sameScope = activeScope == scope
        if !force, sameScope, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 60 { return }

        if !sameScope {
            inFlightTask?.cancel()
            snapshot = .empty
            lastLoadedAt = nil
        }

        activeScope = scope
        isLoading = true
        let previousSnapshot = snapshot
        let loadID = UUID()
        activeLoadID = loadID
        let task = Task {
            try await service.load(home: home, currentUserID: currentUserID, role: role)
        }
        inFlightTask = task

        do {
            let loadedSnapshot = try await task.value
            guard activeScope == scope, activeLoadID == loadID else { return }
            snapshot = loadedSnapshot.preservingSuccessfulData(from: previousSnapshot)
            lastLoadedAt = Date()
        } catch is CancellationError {
            // Navigation and Home changes legitimately cancel obsolete work.
        } catch {
            // Section-level service errors are represented in the snapshot.
            #if DEBUG
            print("[Home Dashboard] Dashboard orchestration failed: \(String(reflecting: error))")
            #endif
        }

        guard activeScope == scope, activeLoadID == loadID else { return }
        inFlightTask = nil
        isLoading = false
    }
}

private struct DashboardLoadScope: Equatable {
    let homeID: UUID
    let userID: UUID?
    let role: HomeMemberRole?
}

private extension HomeDashboardSnapshot {
    func preservingSuccessfulData(from previous: HomeDashboardSnapshot) -> HomeDashboardSnapshot {
        var result = self

        if !calendarDataLoaded, previous.calendarDataLoaded {
            result.todayEvents = previous.todayEvents
            result.calendarDataLoaded = true
        }
        if !mealDataLoaded, previous.mealDataLoaded {
            result.todayMeals = previous.todayMeals
            result.mealCounts = previous.mealCounts
            result.mealDataLoaded = true
        }
        if choreRoleResolved, !choreDataLoaded, previous.choreRoleResolved, previous.choreDataLoaded {
            result.todayChores = previous.todayChores
            result.choreDataLoaded = true
        }

        result.preserveAttentionItem(id: "approvals", from: previous, when: failedSections.contains(.approvals))
        result.preserveAttentionItem(id: "rewards", from: previous, when: failedSections.contains(.rewards))
        result.preserveAttentionItem(id: "meals", from: previous, when: failedSections.contains(.meals))
        return result
    }

    mutating func preserveAttentionItem(id: String, from previous: HomeDashboardSnapshot, when shouldPreserve: Bool) {
        guard shouldPreserve,
              !attentionItems.contains(where: { $0.id == id }),
              let item = previous.attentionItems.first(where: { $0.id == id })
        else { return }
        attentionItems.append(item)
    }
}
