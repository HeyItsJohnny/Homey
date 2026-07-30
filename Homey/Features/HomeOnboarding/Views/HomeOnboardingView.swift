import SwiftUI

struct HomeOnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Layouts

    private var regularLayout: some View {
        ScrollView {
            HStack(alignment: .center, spacing: 76) {
                AuthenticationHeroView(isCompact: false)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                AuthenticationFormCard {
                    introCard
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
        .scrollDismissesKeyboard(.interactively)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 22) {
                AuthenticationHeroView(isCompact: true)

                AuthenticationFormCard(isCompact: true) {
                    introCard
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Content

    private var introCard: some View {
        VStack(spacing: 20) {
            AuthenticationFormHeader(
                title: "Welcome to Homey",
                subtitle: "Let's create your first Home."
            )

            NavigationLink {
                CreateHomeView()
            } label: {
                Text("Create Home")
            }
            .buttonStyle(AuthenticationPrimaryButtonStyle())
        }
    }
}

#Preview("iPhone Home Onboarding") {
    HomeOnboardingView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}

#Preview("iPad Home Onboarding") {
    HomeOnboardingView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
