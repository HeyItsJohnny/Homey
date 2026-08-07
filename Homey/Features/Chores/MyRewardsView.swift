import Combine
import SwiftUI

struct MyRewardsView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = MyRewardsViewModel()

    var body: some View {
        ChoreShellCard(title: "My Rewards", systemImage: "star.fill") {
            if viewModel.isLoading && viewModel.transactions.isEmpty {
                ChoreLoadingState(message: "Loading your rewards...")
            } else if let errorMessage = viewModel.errorMessage, viewModel.transactions.isEmpty {
                ChoreMessageState(
                    title: "Unable to Load Rewards",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else {
                rewardsContent
            }
        }
        .task(id: homeService.selectedHomeID) {
            await viewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
    }

    private var rewardsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            MyRewardsBalanceCard(pointBalance: viewModel.pointBalance)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Points Activity")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                if viewModel.transactions.isEmpty {
                    MyRewardsEmptyLedgerView()
                } else {
                    MyRewardsLedgerList(transactions: viewModel.transactions)
                }

                if viewModel.hasMoreTransactions {
                    Button {
                        viewModel.loadMore()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(HomeyDashboardTheme.warmBrown)
                            }
                            Text(viewModel.isLoadingMore ? "Loading..." : "Load More")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingMore)
                }
            }
        }
    }
}

private struct MyRewardsBalanceCard: View {
    let pointBalance: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total Available Points")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Text(pointBalance.formatted(.number))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .dashboardCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total Available Points, \(pointBalance.formatted(.number))")
    }
}

private struct MyRewardsLedgerList: View {
    let transactions: [ChorePointTransaction]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(transactions) { transaction in
                MyRewardsLedgerRow(transaction: transaction)

                if transaction.id != transactions.last?.id {
                    Divider()
                        .overlay(HomeyDashboardTheme.softBorder)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

private struct MyRewardsLedgerRow: View {
    let transaction: ChorePointTransaction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)

                Text(transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)

                Text(transaction.transactionType.rewardsDisplayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer(minLength: 10)

            Text(pointsText)
                .font(.headline.weight(.bold))
                .foregroundStyle(pointsColor)
                .lineLimit(1)
                .accessibilityLabel(pointsAccessibilityText)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(transaction.createdAt.formatted(date: .abbreviated, time: .shortened)). \(pointsAccessibilityText). \(transaction.transactionType.rewardsDisplayName).")
    }

    private var title: String {
        let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, !note.isEmpty {
            return note
        }
        return transaction.transactionType.rewardsDisplayName
    }

    private var pointsText: String {
        transaction.pointsDelta >= 0 ? "+\(transaction.pointsDelta)" : "\(transaction.pointsDelta)"
    }

    private var pointsAccessibilityText: String {
        transaction.pointsDelta >= 0 ? "Increased by \(transaction.pointsDelta) points" : "Decreased by \(abs(transaction.pointsDelta)) points"
    }

    private var pointsColor: Color {
        transaction.pointsDelta >= 0 ? HomeyDashboardTheme.sageAccent : HomeyDashboardTheme.destructiveRed
    }
}

private struct MyRewardsEmptyLedgerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No point activity yet.")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Complete chores to start earning points.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
    }
}

@MainActor
private final class MyRewardsViewModel: ObservableObject {
    @Published private(set) var pointBalance = 0
    @Published private(set) var transactions: [ChorePointTransaction] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMoreTransactions = false
    @Published private(set) var errorMessage: String?

    private let repository: ChoresRepository
    private let pageSize = 10
    private var activeHomeId: UUID?

    init(repository: ChoresRepository? = nil) {
        self.repository = repository ?? ChoresRepository()
    }

    func load(homeId: UUID?) async {
        guard let homeId else {
            reset()
            return
        }

        activeHomeId = homeId
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        do {
            async let loadedBalance = repository.fetchMyPointBalance(homeId: homeId)
            async let loadedTransactions = repository.fetchMyPointTransactions(homeId: homeId, limit: pageSize, offset: 0)
            pointBalance = try await loadedBalance
            transactions = try await loadedTransactions
            hasMoreTransactions = transactions.count == pageSize
        } catch {
            pointBalance = 0
            transactions = []
            hasMoreTransactions = false
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() {
        guard let activeHomeId, !isLoadingMore, hasMoreTransactions else {
            return
        }

        isLoadingMore = true
        errorMessage = nil

        Task {
            do {
                let nextPage = try await repository.fetchMyPointTransactions(
                    homeId: activeHomeId,
                    limit: pageSize,
                    offset: transactions.count
                )
                transactions.append(contentsOf: nextPage)
                hasMoreTransactions = nextPage.count == pageSize
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoadingMore = false
        }
    }

    func reload() {
        Task {
            await load(homeId: activeHomeId)
        }
    }

    private func reset() {
        activeHomeId = nil
        pointBalance = 0
        transactions = []
        errorMessage = nil
        hasMoreTransactions = false
        isLoading = false
        isLoadingMore = false
    }
}

private extension ChorePointTransactionType {
    var rewardsDisplayName: String {
        switch self {
        case .choreEarned:
            return "Chore Earned"
        case .adminAdjustment:
            return "Adjustment"
        case .rewardRedemption:
            return "Reward Redeemed"
        case .rewardRefund:
            return "Reward Refund"
        }
    }
}
