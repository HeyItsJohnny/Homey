import Combine
import SwiftUI

struct ChoreHistoryView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = ChoreHistoryViewModel()

    private var currentRole: HomeMemberRole? {
        homeService.selectedHomeRole(currentUserID: authenticationService.currentUser?.id)
    }

    var body: some View {
        ChoreShellCard(title: "Chore History", systemImage: "clock.arrow.circlepath") {
            if viewModel.isLoading && viewModel.occurrences.isEmpty {
                ChoreLoadingState(message: "Loading chore history...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load History",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else if viewModel.occurrences.isEmpty {
                ChoreMessageState(
                    title: "No History Yet",
                    message: "Completed chores will appear here.",
                    systemImage: "clock"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.occurrences) { occurrence in
                        ChoreOccurrenceRow(occurrence: occurrence)

                        if occurrence.id != viewModel.occurrences.last?.id {
                            Divider()
                                .overlay(HomeyDashboardTheme.softBorder)
                        }
                    }
                }
            }
        }
        .task(id: ChoreHistoryLoadKey(homeId: homeService.selectedHomeID, role: currentRole)) {
            await viewModel.load(homeId: homeService.selectedHomeID, role: currentRole)
        }
    }
}

private struct ChoreHistoryLoadKey: Equatable {
    let homeId: UUID?
    let role: HomeMemberRole?
}

@MainActor
private final class ChoreHistoryViewModel: ObservableObject {
    @Published private(set) var occurrences: [ChoreOccurrence] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?
    private var activeRole: HomeMemberRole?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    func load(homeId: UUID?, role: HomeMemberRole?) async {
        guard let homeId else {
            activeHomeId = nil
            activeRole = nil
            occurrences = []
            errorMessage = nil
            isLoading = false
            return
        }

        activeHomeId = homeId
        activeRole = role
        isLoading = true
        errorMessage = nil

        do {
            let range = ChoreDateRange.recentHistory()
            occurrences = try await repository.fetchHouseholdHistory(
                homeId: homeId,
                from: range.start,
                through: range.end,
                currentRole: role
            )
        } catch {
            occurrences = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId, role: activeRole)
        }
    }
}
