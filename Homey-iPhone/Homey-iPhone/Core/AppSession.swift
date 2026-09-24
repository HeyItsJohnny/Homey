import Combine
import Foundation

enum AppState: Equatable {
    case loading, unauthenticated, emailVerificationRequired, needsHome, selectingHome, authenticated
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var state: AppState = .loading
    @Published private(set) var switchingHomeID: UUID?
    @Published private(set) var homeSwitchErrorMessage: String?
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

    private func routeFromHomes() {
        if homes.homes.isEmpty { state = .needsHome }
        else if homes.homes.count == 1, let home = homes.homes.first { selectHome(home) }
        else if homes.selectedHome != nil { state = .authenticated }
        else { state = .selectingHome }
    }
}

extension Notification.Name {
    static let homeyActiveHomeDidChange = Notification.Name("homeyActiveHomeDidChange")
}
