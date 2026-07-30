import SwiftUI

struct HomeSelectionView: View {
    @EnvironmentObject private var homeService: HomeService
    @AppStorage("selectedHomeID") private var storedSelectedHomeID = ""

    var restoresStoredSelectionOnAppear = true
    var onHomeSelected: () -> Void = {}

    @State private var switchingHomeID: UUID?
    @State private var previousHomeID: UUID?
    @State private var showSwitchError = false

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var hasOneHome: Bool {
        homeService.homes.count == 1
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if homeService.homes.isEmpty {
                        emptyState
                    } else {
                        currentHomeSection
                        homesSection
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if restoresStoredSelectionOnAppear {
                homeService.restoreSelectedHome(from: storedSelectedHomeID)
            }
        }
        .onChange(of: homeService.selectedHomeID) { _, selectedHomeID in
            storedSelectedHomeID = selectedHomeID?.uuidString ?? ""
        }
        .alert("Unable to Change Home", isPresented: $showSwitchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't switch homes. Please try again.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Change Home")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Choose which home you want to view and manage.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentHomeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Current Home",
                subtitle: "The home currently shown on your dashboard."
            )

            if let selectedHome {
                ChangeHomeCard(
                    home: selectedHome,
                    isCurrent: true,
                    isSwitching: switchingHomeID == selectedHome.id,
                    action: {}
                )
                .disabled(true)
                .accessibilityLabel("Current home, \(selectedHome.name)")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Home Selected")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text("Choose a home below to continue.")
                        .font(.subheadline)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dashboardCard(cornerRadius: 28)
            }
        }
    }

    private var homesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Your Homes",
                subtitle: "Select a home to switch your dashboard."
            )

            VStack(spacing: 12) {
                ForEach(homeService.homes) { home in
                    let isCurrent = home.id == homeService.selectedHomeID

                    ChangeHomeCard(
                        home: home,
                        isCurrent: isCurrent,
                        isSwitching: switchingHomeID == home.id
                    ) {
                        select(home)
                    }
                    .disabled(isCurrent || switchingHomeID != nil)
                    .accessibilityLabel(isCurrent ? "Current home, \(home.name)" : "Switch to \(home.name)")
                }

                if hasOneHome {
                    Text("You currently belong to one home.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)

            Text("No Homes Available")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text("Create or join a home to get started.")
                .font(.body)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(34)
        .frame(maxWidth: .infinity, minHeight: 260)
        .dashboardCard(cornerRadius: 30)
    }

    // MARK: - Actions

    private func select(_ home: HomeSummary) {
        guard switchingHomeID == nil else {
            return
        }

        guard home.id != homeService.selectedHomeID else {
            return
        }

        previousHomeID = homeService.selectedHomeID
        switchingHomeID = home.id

        storedSelectedHomeID = home.id.uuidString
        homeService.selectHome(id: home.id)
        switchingHomeID = nil
        onHomeSelected()
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }
}

private struct ChangeHomeCard: View {
    let home: HomeSummary
    let isCurrent: Bool
    let isSwitching: Bool
    let action: () -> Void

    private var memberText: String {
        "\(home.memberCount) \(home.memberCount == 1 ? "Member" : "Members")"
    }

    private var timezoneText: String? {
        home.timezone
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                homeIcon

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        Text(home.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                            .lineLimit(1)

                        if isCurrent {
                            Text("Current")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text(memberText)

                        if let timezoneText, !timezoneText.isEmpty {
                            Text("•")
                            Text(timezoneText)
                                .lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer(minLength: 18)

                trailingIndicator
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                isCurrent ? HomeyDashboardTheme.selectedSidebarBackground.opacity(0.72) : HomeyDashboardTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(isCurrent ? HomeyDashboardTheme.warmBrown.opacity(0.22) : HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .shadow(color: HomeyDashboardTheme.shadow, radius: 14, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var homeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(HomeyDashboardTheme.warmBeige.opacity(isCurrent ? 0.90 : 0.70))
                .frame(width: 52, height: 52)

            Image(systemName: "house.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isSwitching {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
                .accessibilityLabel("Switching Home")
        } else if isCurrent {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .accessibilityLabel("Selected")
        } else {
            Image(systemName: "chevron.right")
                .font(.body.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.7))
                .accessibilityHidden(true)
        }
    }
}

#Preview("Change Home") {
    NavigationStack {
        HomeSelectionView(restoresStoredSelectionOnAppear: false)
            .environmentObject(HomeService())
    }
}
