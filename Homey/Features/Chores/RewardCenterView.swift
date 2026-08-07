import SwiftUI

struct RewardCenterView: View {
    @State private var selectedSection: RewardCenterSection = .rewards

    var body: some View {
        ChoreShellCard(title: "Reward Center", systemImage: "gift.fill") {
            HStack(spacing: 10) {
                ForEach(RewardCenterSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedSection == section ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 42)
                            .background(
                                selectedSection == section ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            RewardCenterPlaceholderView(section: selectedSection)
        }
    }
}

private enum RewardCenterSection: String, CaseIterable, Identifiable {
    case rewards
    case redemptions
    case pointAdjustments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewards:
            return "Rewards"
        case .redemptions:
            return "Redemptions"
        case .pointAdjustments:
            return "Point Adjustments"
        }
    }

    var systemImage: String {
        switch self {
        case .rewards:
            return "gift"
        case .redemptions:
            return "arrow.triangle.2.circlepath"
        case .pointAdjustments:
            return "plusminus.circle"
        }
    }
}

private struct RewardCenterPlaceholderView: View {
    let section: RewardCenterSection

    var body: some View {
        ChoreMessageState(
            title: section.title,
            message: message,
            systemImage: section.systemImage
        )
    }

    private var message: String {
        switch section {
        case .rewards:
            return "Reward catalog management will appear here."
        case .redemptions:
            return "Reward redemption review will appear here."
        case .pointAdjustments:
            return "Manual point adjustments will appear here."
        }
    }
}
