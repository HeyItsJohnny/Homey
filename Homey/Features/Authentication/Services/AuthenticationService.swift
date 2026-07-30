import Combine
import Foundation
import Supabase

@MainActor
final class AuthenticationService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var session: Session?
    @Published private(set) var currentUser: UserProfile?
    @Published private(set) var authenticationState: AuthenticationState = .loading
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let client = SupabaseManager.shared.client
    private var authStateChangesTask: Task<Void, Never>?

    // MARK: - Lifecycle

    init() {
        subscribeToAuthStateChanges()
    }

    deinit {
        authStateChangesTask?.cancel()
    }

    // MARK: - Session

    func restoreSession() async {
        authenticationState = .loading
        isLoading = true
        clearError()

        do {
            let restoredSession = try await client.auth.session
            applySession(restoredSession)
        } catch {
            clearSession(state: .unauthenticated)
        }

        isLoading = false
    }

    func refreshSession() async {
        isLoading = true
        clearError()

        do {
            let refreshedSession = try await client.auth.refreshSession()
            applySession(refreshedSession)
        } catch {
            errorMessage = "Please verify your email."
            authenticationState = .emailVerificationRequired
        }

        isLoading = false
    }

    // MARK: - Authentication

    func signIn(email: String, password: String) async {
        guard validate(email: email, password: password) else {
            return
        }

        isLoading = true
        clearError()

        do {
            let signedInSession = try await client.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            applySession(signedInSession)
        } catch {
            clearSession(state: .unauthenticated)
            errorMessage = friendlyMessage(for: error, fallback: "Invalid email or password.")
        }

        isLoading = false
    }

    func signUp(email: String, password: String) async {
        guard validate(email: email, password: password) else {
            return
        }

        isLoading = true
        clearError()

        do {
            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            if let signUpSession = response.session {
                applySession(signUpSession)
            } else {
                session = nil
                currentUser = UserProfile(user: response.user)
                authenticationState = .emailVerificationRequired
            }
        } catch {
            clearSession(state: .unauthenticated)
            errorMessage = friendlyMessage(for: error, fallback: "Unable to create your account.")
        }

        isLoading = false
    }

    func signOut() async {
        isLoading = true
        clearError()

        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = friendlyMessage(for: error, fallback: "Unable to sign out.")
        }

        clearSession(state: .unauthenticated)
        isLoading = false
    }

    func sendPasswordReset(email: String) async -> Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email address."
            return false
        }

        isLoading = true
        clearError()

        do {
            try await client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            isLoading = false
            return true
        } catch {
            errorMessage = friendlyMessage(for: error, fallback: "Unable to send password reset email.")
            isLoading = false
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Auth State Changes

    private func subscribeToAuthStateChanges() {
        authStateChangesTask = Task { [weak self] in
            guard let self else { return }

            for await change in client.auth.authStateChanges {
                handleAuthStateChange(event: change.event, session: change.session)
            }
        }
    }

    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            if let session {
                applySession(session)
            } else {
                clearSession(state: .unauthenticated)
            }
        case .signedOut, .userDeleted:
            clearSession(state: .unauthenticated)
        case .passwordRecovery:
            if let session {
                applySession(session)
            }
        }
    }

    // MARK: - State Helpers

    private func applySession(_ session: Session) {
        self.session = session
        currentUser = UserProfile(user: session.user)
        authenticationState = isVerified(user: session.user) ? .authenticated : .emailVerificationRequired
    }

    private func clearSession(state: AuthenticationState) {
        session = nil
        currentUser = nil
        authenticationState = state
    }

    private func isVerified(user: User) -> Bool {
        user.emailConfirmedAt != nil || user.confirmedAt != nil
    }

    private func validate(email: String, password: String) -> Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email address."
            return false
        }

        guard !password.isEmpty else {
            errorMessage = "Enter your password."
            return false
        }

        return true
    }

    private func friendlyMessage(for error: Error, fallback: String) -> String {
        let description = error.localizedDescription.lowercased()

        if description.contains("invalid login") || description.contains("invalid_credentials") {
            return "Invalid email or password."
        }

        if description.contains("email not confirmed") || description.contains("email_not_confirmed") {
            return "Please verify your email."
        }

        if description.contains("network") || description.contains("timed out") || description.contains("offline") {
            return "Unable to connect."
        }

        return fallback
    }
}
