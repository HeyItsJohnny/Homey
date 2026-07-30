import SwiftUI

struct HomeInvitationOnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var homeService: HomeService

    @State private var isShowingInvitations = false
    @State private var isShowingCreateHome = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var invitationCount: Int {
        homeService.myPendingInvitations.count
    }

    private var primaryInvitation: HomeInvitationDisplay? {
        homeService.myPendingInvitations.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthenticationBackground()

                if isRegularWidth {
                    regularLayout
                } else {
                    compactLayout
                }
            }
            .navigationDestination(isPresented: $isShowingInvitations) {
                HomeInvitationsView(onClose: {})
            }
            .navigationDestination(isPresented: $isShowingCreateHome) {
                CreateHomeView()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var regularLayout: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 76) {
                AuthenticationHeroView(isCompact: false)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                AuthenticationFormCard {
                    invitationChoiceCard
                }
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 1400)
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 720)
        }
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 22) {
                AuthenticationHeroView(isCompact: true)

                AuthenticationFormCard(isCompact: true) {
                    invitationChoiceCard
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var invitationChoiceCard: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Welcome to Homey",
                subtitle: invitationSubtitle
            )

            if let primaryInvitation {
                VStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 56, height: 56)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(primaryInvitation.homeName ?? "A Homey Home")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Role: \(primaryInvitation.formattedRole)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(HomeyDashboardTheme.selectedSidebarBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            Button {
                isShowingInvitations = true
            } label: {
                Text(invitationCount == 1 ? "View Invitation" : "View Invitations")
            }
            .buttonStyle(AuthenticationPrimaryButtonStyle())

            Button {
                isShowingCreateHome = true
            } label: {
                Text("Create My Own Home")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
        }
    }

    private var invitationSubtitle: String {
        if invitationCount == 1 {
            return "You have been invited to join a home."
        }

        return "You have been invited to join \(invitationCount) homes."
    }
}

#Preview("Home Invitation Onboarding") {
    HomeInvitationOnboardingView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
