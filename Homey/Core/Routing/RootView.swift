import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService
    @AppStorage("selectedHomeID") private var storedSelectedHomeID = ""

    @State private var loadedHomeUserID: UUID?

    var body: some View {
        Group {
            switch authenticationService.authenticationState {
            case .loading:
                ProgressView()
            case .unauthenticated:
                AuthenticationView()
            case .emailVerificationRequired:
                NavigationStack {
                    VerifyEmailView(onBackToLogin: {})
                }
            case .authenticated:
                authenticatedContent
            }
        }
        .task {
            await authenticationService.restoreSession()
        }
        .onChange(of: homeService.selectedHomeID) { _, selectedHomeID in
            storedSelectedHomeID = selectedHomeID?.uuidString ?? ""
        }
        .onChange(of: authenticationService.authenticationState) { _, state in
            if state == .unauthenticated {
                loadedHomeUserID = nil
                storedSelectedHomeID = ""
                homeService.selectHome(id: nil)
            }
        }
    }

    private var authenticatedContent: some View {
        Group {
            if homeService.isLoading || loadedHomeUserID != authenticationService.currentUser?.id {
                ProgressView()
            } else if homeService.homes.isEmpty {
                HomeOnboardingView()
            } else {
                HomeyMainView()
            }
        }
        .task(id: authenticationService.currentUser?.id) {
            await loadHomesForAuthenticatedUser()
        }
    }

    private func loadHomesForAuthenticatedUser() async {
        guard let userID = authenticationService.currentUser?.id else {
            return
        }

        loadedHomeUserID = nil
        homeService.restoreSelectedHome(from: storedSelectedHomeID)
        await homeService.loadHomes(for: userID)
        storedSelectedHomeID = homeService.selectedHomeID?.uuidString ?? ""
        loadedHomeUserID = userID
    }
}
