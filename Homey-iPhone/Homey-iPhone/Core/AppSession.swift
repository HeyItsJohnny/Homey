import Auth
import Combine
import Foundation

enum AppState: Equatable {
    case loading, unauthenticated, emailVerificationRequired, resolvingAccount, accountResolutionFailed, pendingInvitations, needsHome, selectingHome, authenticated
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var state: AppState = .loading
    @Published private(set) var switchingHomeID: UUID?
    @Published private(set) var homeSwitchErrorMessage: String?
    @Published private(set) var accountResolutionErrorMessage: String?
    let authentication = AuthenticationService()
    let homes = HomeService()
    private let selectedHomeKey = "selectedHomeID"
    private var cancellables: Set<AnyCancellable> = []

    init() {
        authentication.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        homes.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var currentUser: UserProfile? { authentication.currentUser }
    var activeHome: HomeSummary? { homes.selectedHome }
    var activeRole: HomeMemberRole? { activeHome?.role }
    var activeTimezone: TimeZone { activeHome?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current }
    var isSwitchingHome: Bool { switchingHomeID != nil }

    func launch() async {
        state = .loading
        guard await authentication.restoreSession(), authentication.currentUser != nil else {
            state = .unauthenticated; return
        }
        await resolveHomes()
    }

    func didAuthenticate() async { await resolveHomes() }
    func requireEmailVerification() { state = .emailVerificationRequired }
    func returnToLogin() { state = .unauthenticated }

    func resolveHomes() async {
        guard let userID = authentication.currentUser?.id,
              let email = authentication.session?.user.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty else {
            state = .unauthenticated
            return
        }

        state = .resolvingAccount
        accountResolutionErrorMessage = nil
        // Invitation discovery intentionally takes no email parameter. The backend RPC
        // is responsible for resolving the normalized email from this authenticated session.
        let preferredID = UserDefaults.standard.string(forKey: selectedHomeKey).flatMap(UUID.init(uuidString:))
        guard await homes.loadHomes(for: userID, preferredHomeID: preferredID) else {
            failAccountResolution(homes.errorMessage ?? "We couldn't load your Homes. Check your connection and try again.")
            return
        }
        guard await homes.loadMyPendingInvitations(userID: userID, forceRefresh: true) else {
            failAccountResolution(homes.myInvitationsErrorMessage ?? "We couldn't load your invitations. Check your connection and try again.")
            return
        }
        routeFromHomesAndInvitations()
    }

    func retryAccountResolution() async { await resolveHomes() }

    func createOwnHomeFromInvitations() {
        guard homes.homes.isEmpty else { routeFromHomesAndInvitations(); return }
        accountResolutionErrorMessage = nil
        state = .needsHome
    }

    @discardableResult
    func joinHomeFromOnboarding(_ invitation: HomeInvitationDisplay) async -> Bool {
        guard state == .pendingInvitations, homes.homes.isEmpty,
              let userID = authentication.currentUser?.id else { return false }
        accountResolutionErrorMessage = nil
        guard let result = await homes.acceptInvitation(invitation, currentUserID: userID) else {
            accountResolutionErrorMessage = homes.myInvitationsErrorMessage ?? "We couldn't join this Home. Please try again."
            return false
        }
        guard let joinedHome = homes.homes.first(where: { $0.id == result.homeID }) else {
            failAccountResolution("You joined the Home, but Homey couldn't load it yet. Try again to finish setup.")
            return false
        }
        return await switchHome(to: joinedHome)
    }

    func selectHome(_ home: HomeSummary) {
        commitActiveHome(home)
    }

    func homeWasCreated() {
        if let home = homes.selectedHome { selectHome(home) } else { routeFromHomes() }
    }

    func chooseAnotherHome() {
        guard !homes.homes.isEmpty else { state = .needsHome; return }
        homeSwitchErrorMessage = nil
        state = .selectingHome
    }

    func cancelHomeSelection() {
        guard !isSwitchingHome else { return }
        homeSwitchErrorMessage = nil
        state = activeHome == nil ? .selectingHome : .authenticated
    }

    func refreshHomeChoices() async {
        guard let userID = authentication.currentUser?.id, !isSwitchingHome else { return }
        let previousHomeID = activeHome?.id
        let refreshed = await homes.refreshHomes(for: userID, preservingHomeID: previousHomeID)
        guard refreshed else { return }
        if homes.homes.isEmpty { state = .needsHome }
    }

    @discardableResult
    func switchHome(to home: HomeSummary) async -> Bool {
        guard switchingHomeID == nil, let userID = authentication.currentUser?.id else { return false }
        homeSwitchErrorMessage = nil

        if home.id == activeHome?.id {
            state = .authenticated
            return true
        }

        switchingHomeID = home.id
        // Removing the feature root immediately clears stale navigation and cancels its
        // view-bound tasks before the destination Home is committed.
        state = .selectingHome
        defer { switchingHomeID = nil }

        do {
            let validatedHome = try await homes.validatedHome(homeID: home.id, userID: userID)
            commitActiveHome(validatedHome)
            return true
        } catch {
            homeSwitchErrorMessage = error.localizedDescription
            return false
        }
    }

    func refreshActiveHome() async {
        guard let userID = authentication.currentUser?.id else { return }
        let selectedID = activeHome?.id
        await homes.loadHomes(for: userID, preferredHomeID: selectedID)
    }

    func signOut() async {
        await authentication.signOut()
        homes.reset()
        UserDefaults.standard.removeObject(forKey: selectedHomeKey)
        switchingHomeID = nil
        homeSwitchErrorMessage = nil
        accountResolutionErrorMessage = nil
        state = .unauthenticated
    }

    private func commitActiveHome(_ home: HomeSummary) {
        let previousHomeID = activeHome?.id
        homes.select(home)
        UserDefaults.standard.set(home.id.uuidString, forKey: selectedHomeKey)
        homeSwitchErrorMessage = nil
        state = .authenticated
        if previousHomeID != home.id {
            NotificationCenter.default.post(name: .homeyActiveHomeDidChange, object: home.id)
        }
    }

    private func routeFromHomesAndInvitations() {
        accountResolutionErrorMessage = nil
        if homes.homes.isEmpty, !homes.myPendingInvitations.isEmpty { state = .pendingInvitations }
        else if homes.homes.isEmpty { state = .needsHome }
        else if homes.homes.count == 1, let home = homes.homes.first { selectHome(home) }
        else if homes.selectedHome != nil { state = .authenticated }
        else { state = .selectingHome }
    }

    private func routeFromHomes() { routeFromHomesAndInvitations() }

    private func failAccountResolution(_ message: String) {
        accountResolutionErrorMessage = message
        state = .accountResolutionFailed
    }
}

extension Notification.Name {
    static let homeyActiveHomeDidChange = Notification.Name("homeyActiveHomeDidChange")
}
