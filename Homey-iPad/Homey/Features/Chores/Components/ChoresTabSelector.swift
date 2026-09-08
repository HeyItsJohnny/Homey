import SwiftUI

struct ChoresTabSelector: View {
    let tabs: [ChoresTab]
    @Binding var selectedTab: ChoresTab
    var title: (ChoresTab) -> String = { $0.title }
    var badgeCount: (ChoresTab) -> Int? = { _ in nil }

    var body: some View {
        ModuleTabSelector(
            tabs: tabs,
            selectedTab: $selectedTab,
            accessibilityLabel: "Chores section",
            title: title,
            badgeCount: badgeCount,
            accessibilityLabelForTab: accessibilityLabel(for:badgeCount:)
        )
    }

    private func accessibilityLabel(for tab: ChoresTab, badgeCount: Int?) -> String {
        let tabTitle = title(tab)
        guard let badgeCount, badgeCount > 0 else {
            return tabTitle
        }

        switch tab {
        case .myChores:
            return "\(tabTitle), \(badgeCount) items need attention"
        case .myRewards:
            return "\(tabTitle), \(badgeCount) rewards pending"
        case .houseChores:
            return "\(tabTitle), \(badgeCount) approvals pending"
        case .rewardCenter:
            return "\(tabTitle), \(badgeCount) redemptions pending"
        case .choreHistory:
            return tabTitle
        }
    }
}

struct ModuleTabSelector<Tab: Identifiable & Equatable>: View {
    let tabs: [Tab]
    @Binding var selectedTab: Tab
    let accessibilityLabel: String
    let title: (Tab) -> String
    var badgeCount: (Tab) -> Int? = { _ in nil }
    var accessibilityLabelForTab: (Tab, Int?) -> String

    init(
        tabs: [Tab],
        selectedTab: Binding<Tab>,
        accessibilityLabel: String,
        title: @escaping (Tab) -> String,
        badgeCount: @escaping (Tab) -> Int? = { _ in nil },
        accessibilityLabelForTab: ((Tab, Int?) -> String)? = nil
    ) {
        self.tabs = tabs
        _selectedTab = selectedTab
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.badgeCount = badgeCount
        self.accessibilityLabelForTab = accessibilityLabelForTab ?? { tab, _ in title(tab) }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 7) {
                                Text(title(tab))
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
                        .accessibilityLabel(accessibilityLabelForTab(tab, badgeCount(tab)))
                    }
                }
                .padding(4)
                .frame(width: pickerWidth(for: proxy.size.width))
                .frame(minWidth: proxy.size.width, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: 48)
        .accessibilityLabel(accessibilityLabel)
    }

    private func pickerWidth(for availableWidth: CGFloat) -> CGFloat {
        let mealsPickerWidth: CGFloat = 520
        let mealsSegmentWidth = mealsPickerWidth / 3

        guard tabs.count > 3 else {
            return min(availableWidth, mealsPickerWidth)
        }

        return CGFloat(tabs.count) * mealsSegmentWidth
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
