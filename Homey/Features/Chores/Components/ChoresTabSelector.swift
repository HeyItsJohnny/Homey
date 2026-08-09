import SwiftUI

struct ChoresTabSelector: View {
    let tabs: [ChoresTab]
    @Binding var selectedTab: ChoresTab
    var badgeCount: (ChoresTab) -> Int? = { _ in nil }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 7) {
                                Text(tab.title)
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)

                                AttentionBadge(count: badgeCount(tab))
                            }
                            .foregroundStyle(selectedTab == tab ? Color.white : HomeyDashboardTheme.primaryText)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .frame(maxWidth: .infinity)
                            .background(
                                selectedTab == tab ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: tab))
                    }
                }
                .padding(4)
                .frame(width: pickerWidth(for: proxy.size.width))
                .frame(minWidth: proxy.size.width, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: 48)
        .accessibilityLabel("Chores section")
    }

    private func pickerWidth(for availableWidth: CGFloat) -> CGFloat {
        let mealsPickerWidth: CGFloat = 520
        let mealsSegmentWidth = mealsPickerWidth / 3

        guard tabs.count > 3 else {
            return min(availableWidth, mealsPickerWidth)
        }

        return CGFloat(tabs.count) * mealsSegmentWidth
    }

    private func accessibilityLabel(for tab: ChoresTab) -> String {
        guard let count = badgeCount(tab), count > 0 else {
            return tab.title
        }

        switch tab {
        case .myChores:
            return "\(tab.title), \(count) items need attention"
        case .myRewards:
            return "\(tab.title), \(count) rewards pending"
        case .houseChores:
            return "\(tab.title), \(count) approvals pending"
        case .rewardCenter:
            return "\(tab.title), \(count) redemptions pending"
        case .choreHistory:
            return tab.title
        }
    }
}

struct AttentionBadge: View {
    let count: Int?
    var color: Color = HomeyDashboardTheme.destructiveRed

    private var badgeText: String? {
        guard let count, count > 0 else {
            return nil
        }

        return count > 99 ? "99+" : count.formatted(.number)
    }

    var body: some View {
        if let badgeText {
            Text(badgeText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, badgeText.count > 1 ? 6 : 5)
                .frame(minWidth: 20, minHeight: 20)
                .background(color, in: Capsule())
                .accessibilityHidden(true)
        }
    }
}
