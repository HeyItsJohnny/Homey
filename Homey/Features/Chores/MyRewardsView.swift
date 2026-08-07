import Combine
import SwiftUI

struct MyRewardsView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = MyRewardsViewModel()

    var body: some View {
        ChoreShellCard(title: "My Rewards", systemImage: "star.fill") {
            if viewModel.isLoading {
                ChoreLoadingState(message: "Loading your rewards...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load Rewards",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.pointBalance)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text("Available chore points")
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            }
        }
        .task(id: homeService.selectedHomeID) {
            await viewModel.load(homeId: homeService.selectedHomeID)
        }
    }
}

@MainActor
private final class MyRewardsViewModel: ObservableObject {
    @Published private(set) var pointBalance = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private var activeHomeId: UUID?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    func load(homeId: UUID?) async {
        guard let homeId else {
            activeHomeId = nil
            pointBalance = 0
            errorMessage = nil
            isLoading = false
            return
        }

        activeHomeId = homeId
        isLoading = true
        errorMessage = nil

        do {
            pointBalance = try await repository.fetchMyPointBalance(homeId: homeId)
        } catch {
            pointBalance = 0
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId)
        }
    }
}
