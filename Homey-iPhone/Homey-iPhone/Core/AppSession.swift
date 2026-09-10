import Combine
import Foundation

enum AppState: Equatable {
    case loading, unauthenticated, emailVerificationRequired, needsHome, selectingHome, authenticated
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var state: AppState = .loading
    let authentication = AuthenticationService()
    let homes = HomeService()
    private let selectedHomeKey = "selectedHomeID"

    var currentUser: UserProfile? { authentication.currentUser }
    var activeHome: HomeSummary? { homes.selectedHome }
    var activeRole: HomeMemberRole? { activeHome?.role }
    var activeTimezone: TimeZone { activeHome?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current }

    func launch() async {
        state = .loading
        guard await authentication.restoreSession(), authentication.currentUser != nil else {
            state = .unauthenticated; return
        }
        await resolveHomes()
    }

    func didAuthenticate() async { state = .loading; await resolveHomes() }
    func requireEmailVerification() { state = .emailVerificationRequired }
    func returnToLogin() { state = .unauthenticated }

    func resolveHomes() async {
        guard let userID = authentication.currentUser?.id else { state = .unauthenticated; return }
        let preferredID = UserDefaults.standard.string(forKey: selectedHomeKey).flatMap(UUID.init(uuidString:))
        await homes.loadHomes(for: userID, preferredHomeID: preferredID)
        routeFromHomes()
    }

    func selectHome(_ home: HomeSummary) {
        homes.select(home)
        UserDefaults.standard.set(home.id.uuidString, forKey: selectedHomeKey)
        state = .authenticated
    }

    func homeWasCreated() {
        if let home = homes.selectedHome { selectHome(home) } else { routeFromHomes() }
    }

    func chooseAnotherHome() { state = homes.homes.count > 1 ? .selectingHome : .authenticated }

    func signOut() async {
        await authentication.signOut()
        homes.reset()
        UserDefaults.standard.removeObject(forKey: selectedHomeKey)
        state = .unauthenticated
    }

    private func routeFromHomes() {
        if homes.homes.isEmpty { state = .needsHome }
        else if homes.homes.count == 1, let home = homes.homes.first { selectHome(home) }
        else if homes.selectedHome != nil { state = .authenticated }
        else { state = .selectingHome }
    }
}
