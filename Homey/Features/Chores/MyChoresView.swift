import Combine
import SwiftUI

struct MyChoresView: View {
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel = MyChoresViewModel()

    var body: some View {
        ChoreShellCard(title: "My Chores", systemImage: "checklist") {
            if viewModel.isLoading && viewModel.occurrences.isEmpty {
                ChoreLoadingState(message: "Loading your chores...")
            } else if let errorMessage = viewModel.errorMessage {
                ChoreMessageState(
                    title: "Unable to Load Chores",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    buttonTitle: "Try Again"
                ) {
                    viewModel.reload()
                }
            } else if viewModel.occurrences.isEmpty {
                ChoreMessageState(
                    title: "No Chores Yet",
                    message: "Assigned chores will appear here.",
                    systemImage: "checkmark.circle"
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
        .task(id: homeService.selectedHomeID) {
            await viewModel.load(homeId: homeService.selectedHomeID)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .homeyChoresDidChange) {
                viewModel.reload()
            }
        }
    }
}

@MainActor
private final class MyChoresViewModel: ObservableObject {
    @Published private(set) var occurrences: [ChoreOccurrence] = []
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
            occurrences = []
            errorMessage = nil
            isLoading = false
            return
        }

        activeHomeId = homeId
        isLoading = true
        errorMessage = nil

        do {
            let range = ChoreDateRange.upcoming()
            occurrences = try await repository.fetchMyActionableOccurrences(
                homeId: homeId,
                from: range.start,
                through: range.end
            )
        } catch {
            occurrences = []
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

enum ChoreDateRange {
    static func upcoming(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 30, to: start) ?? now
        return (start, end)
    }

    static func recentHistory(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let now = Date()
        let end = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let start = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        return (start, end)
    }
}

struct ChoreShellCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: 38, height: 38)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: 30)
    }
}

struct ChoreLoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct ChoreMessageState: View {
    let title: String
    let message: String
    let systemImage: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 52, height: 52)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle {
                Button(buttonTitle) {
                    action?()
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 150)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
    }
}

struct ChoreOccurrenceRow: View {
    let occurrence: ChoreOccurrence

    var body: some View {
        HStack(spacing: 13) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.titleSnapshot)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(occurrence.displayStatus.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let date = occurrence.dueAt.formatted(date: .abbreviated, time: occurrence.isAllDay ? .omitted : .shortened)
        return "\(date) • \(occurrence.pointsValue) \(occurrence.pointsValue == 1 ? "point" : "points")"
    }

    private var statusColor: Color {
        switch occurrence.displayStatus {
        case .overdue:
            return HomeyDashboardTheme.softRed
        case .stored(.completed):
            return HomeyDashboardTheme.sageAccent
        case .stored(.awaitingApproval):
            return HomeyDashboardTheme.orangeAccent
        case .stored:
            return HomeyDashboardTheme.lavenderAccent
        }
    }
}
