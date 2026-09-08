import Auth
import Combine
import Foundation
import PostgREST
import Supabase

@MainActor
final class AuthenticationService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var session: Session?
    @Published private(set) var currentUser: UserProfile?
    @Published private(set) var authenticationState: AuthenticationState = .loading
    @Published private(set) var isLoading = false
    @Published private(set) var isUploadingAvatar = false
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
            await refreshCurrentUserProfile()
        } catch {
            logCompleteError(error, context: "RESTORE SESSION FAILED")
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
            logCompleteError(error, context: "REFRESH SESSION FAILED")
            errorMessage = authErrorMessage(for: error)
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
            await refreshCurrentUserProfile()
        } catch {
            logCompleteError(error, context: "SIGN IN FAILED")
            clearSession(state: .unauthenticated)
            errorMessage = authErrorMessage(for: error)
        }

        isLoading = false
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, displayName: String) async {
        guard validate(email: email, password: password) else {
            return
        }

        let normalizedProfile = NormalizedProfileInput(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName
        )

        guard normalizedProfile.firstName != nil else {
            errorMessage = "Enter your first name."
            return
        }

        guard normalizedProfile.lastName != nil else {
            errorMessage = "Enter your last name."
            return
        }

        guard normalizedProfile.displayName != nil else {
            errorMessage = "Enter a display name."
            return
        }

        isLoading = true
        clearError()

        if client.auth.currentSession != nil {
            do {
                try await client.auth.signOut()
                clearSession(state: .unauthenticated)
            } catch {
                logCompleteError(error, context: "CLEAR CACHED SESSION BEFORE SIGNUP FAILED")
            }
        }

        do {
            #if DEBUG
            print("========== SIGNUP STARTED ==========")
            print("email: \(email.trimmingCharacters(in: .whitespacesAndNewlines))")
            print("===================================")
            #endif

            let response = try await client.auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            do {
                try await upsertProfile(
                    userID: response.user.id,
                    email: response.user.email ?? email.trimmingCharacters(in: .whitespacesAndNewlines),
                    profile: normalizedProfile
                )
            } catch {
                logCompleteError(error, context: "SIGNUP PROFILE SAVE FAILED")
                errorMessage = "Your account was created, but your profile information could not be saved. Please try again."
                isLoading = false
                return
            }

            if let signUpSession = response.session {
                applySession(signUpSession)
                await refreshCurrentUserProfile()
            } else {
                session = nil
                currentUser = UserProfile(
                    id: response.user.id,
                    email: response.user.email ?? email.trimmingCharacters(in: .whitespacesAndNewlines),
                    firstName: normalizedProfile.firstName,
                    lastName: normalizedProfile.lastName,
                    displayName: normalizedProfile.displayName,
                    avatarURL: nil
                )
                authenticationState = .emailVerificationRequired
            }
        } catch {
            logCompleteError(error, context: "SIGNUP FAILED")
            clearSession(state: .unauthenticated)
            errorMessage = authErrorMessage(for: error)
        }

        isLoading = false
    }

    func signOut() async {
        isLoading = true
        clearError()

        do {
            try await client.auth.signOut()
        } catch {
            logCompleteError(error, context: "SIGN OUT FAILED")
            errorMessage = authErrorMessage(for: error)
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
            logCompleteError(error, context: "PASSWORD RESET FAILED")
            errorMessage = authErrorMessage(for: error)
            isLoading = false
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshCurrentUserProfile() async {
        guard let currentUser else {
            return
        }

        do {
            self.currentUser = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
        } catch {
            logCompleteError(error, context: "FETCH PROFILE FAILED")
        }
    }

    func updateCurrentUserProfile(firstName: String, lastName: String, displayName: String) async -> Bool {
        guard let currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }

        let normalizedProfile = NormalizedProfileInput(
            firstName: firstName,
            lastName: lastName,
            displayName: displayName
        )

        guard normalizedProfile.firstName != nil else {
            errorMessage = "Enter your first name."
            return false
        }

        guard normalizedProfile.lastName != nil else {
            errorMessage = "Enter your last name."
            return false
        }

        guard normalizedProfile.displayName != nil else {
            errorMessage = "Enter a display name."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        clearError()
        defer { isLoading = false }

        do {
            try await upsertProfile(userID: currentUser.id, email: currentUser.email, profile: normalizedProfile)
            self.currentUser = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            return true
        } catch {
            logCompleteError(error, context: "UPDATE PROFILE FAILED")
            errorMessage = "We could not update your account. Please try again."
            return false
        }
    }

    func uploadCurrentUserAvatar(imageData: Data) async -> Bool {
        guard let currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }

        guard !isUploadingAvatar else {
            return false
        }

        guard !imageData.isEmpty else {
            errorMessage = "We could not prepare that photo. Please choose another image."
            return false
        }

        isUploadingAvatar = true
        clearError()
        defer { isUploadingAvatar = false }

        let avatarPath = avatarObjectPath(for: currentUser.id)

        do {
            #if DEBUG
            print("Uploading avatar")
            print("bucket: avatars")
            print("objectPath: \(avatarPath)")
            #endif

            try await client.storage
                .from("avatars")
                .upload(
                    avatarPath,
                    data: imageData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: "image/jpeg",
                        upsert: true
                    )
                )

            let publicURL = try client.storage
                .from("avatars")
                .getPublicURL(path: avatarPath)

            do {
                try await updateAvatarURL(publicURL)
            } catch {
                #if DEBUG
                print("Avatar profile update failed after upload; retrying once")
                #endif

                do {
                    try await updateAvatarURL(publicURL)
                } catch {
                    logCompleteError(error, context: "UPDATE AVATAR URL FAILED")
                    errorMessage = "Your photo uploaded, but we could not connect it to your profile. Please try again."
                    return false
                }
            }

            let refreshedProfile = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            self.currentUser = refreshedProfile.withAvatarURL(cacheBustedURL(publicURL))
            return true
        } catch {
            logCompleteError(error, context: "UPLOAD AVATAR FAILED")
            errorMessage = avatarErrorMessage(for: error)
            return false
        }
    }

    func removeCurrentUserAvatar() async -> Bool {
        guard let currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }

        guard !isUploadingAvatar else {
            return false
        }

        isUploadingAvatar = true
        clearError()
        defer { isUploadingAvatar = false }

        let avatarPath = avatarObjectPath(for: currentUser.id)

        do {
            #if DEBUG
            print("Removing avatar")
            print("bucket: avatars")
            print("objectPath: \(avatarPath)")
            #endif

            _ = try? await client.storage
                .from("avatars")
                .remove(paths: [avatarPath])

            try await updateAvatarURL(nil)
            self.currentUser = try await fetchProfile(userID: currentUser.id, email: currentUser.email)
            return true
        } catch {
            logCompleteError(error, context: "REMOVE AVATAR FAILED")
            errorMessage = avatarErrorMessage(for: error)
            return false
        }
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
                Task {
                    await refreshCurrentUserProfile()
                }
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

    private func fetchProfile(userID: UUID, email: String) async throws -> UserProfile {
        let profiles: [ProfileResponse] = try await client
            .from("profiles")
            .select("id, first_name, last_name, display_name, avatar_url")
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        guard let profile = profiles.first else {
            return UserProfile(id: userID, email: email)
        }

        return UserProfile(
            id: profile.id,
            email: email,
            firstName: profile.firstName,
            lastName: profile.lastName,
            displayName: profile.displayName,
            avatarURL: profile.avatarURL
        )
    }

    private func upsertProfile(userID: UUID, email: String, profile: NormalizedProfileInput) async throws {
        try await client
            .from("profiles")
            .upsert(
                UpdateProfilePayload(
                    id: userID,
                    firstName: profile.firstName,
                    lastName: profile.lastName,
                    displayName: profile.displayName
                )
            )
            .execute()
    }

    private func avatarObjectPath(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/profile.jpg"
    }

    private func cacheBustedURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "v" }
        queryItems.append(URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970))))
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    private func updateAvatarURL(_ avatarURL: URL?) async throws {
        guard let currentUser else {
            return
        }

        try await client
            .from("profiles")
            .update(UpdateAvatarURLPayload(avatarURL: avatarURL))
            .eq("id", value: currentUser.id.uuidString)
            .execute()
    }

    private func authErrorMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.message
        }

        if let postgrestError = error as? PostgrestError {
            return postgrestError.message
        }

        if let httpError = error as? HTTPError {
            return httpError.errorDescription ?? "HTTP request failed."
        }

        return error.localizedDescription
    }

    private func avatarErrorMessage(for error: Error) -> String {
        let message = authErrorMessage(for: error).lowercased()

        if message.contains("permission") || message.contains("policy") || message.contains("rls") || message.contains("unauthorized") || message.contains("forbidden") {
            return "We could not upload your photo. Please check your connection and try again."
        }

        return "Unable to update your photo. Please try again."
    }

    private func logCompleteError(_ error: Error, context: String) {
        #if DEBUG
        print("========== \(context) ==========")
        print(String(reflecting: error))
        print(error.localizedDescription)

        if let authError = error as? AuthError {
            print("AuthError.code: \(authError.errorCode)")
            print("AuthError.message: \(authError.message)")
            print("AuthError.details: <not exposed by Supabase AuthError>")
            print("AuthError.hint: <not exposed by Supabase AuthError>")

            switch authError {
            case .api(let message, let errorCode, let underlyingData, let underlyingResponse):
                print("AuthError.api.message: \(message)")
                print("AuthError.api.code: \(errorCode)")
                print("AuthError.api.statusCode: \(underlyingResponse.statusCode)")
                print("AuthError.api.responseBody: \(String(data: underlyingData, encoding: .utf8) ?? "<non-UTF8 response body>")")
            case .weakPassword(let message, let reasons):
                print("AuthError.weakPassword.message: \(message)")
                print("AuthError.weakPassword.reasons: \(reasons)")
            case .pkceGrantCodeExchange(let message, let error, let code):
                print("AuthError.pkceGrantCodeExchange.message: \(message)")
                print("AuthError.pkceGrantCodeExchange.error: \(error ?? "")")
                print("AuthError.pkceGrantCodeExchange.code: \(code ?? "")")
            case .implicitGrantRedirect(let message):
                print("AuthError.implicitGrantRedirect.message: \(message)")
            case .jwtVerificationFailed(let message):
                print("AuthError.jwtVerificationFailed.message: \(message)")
            case .sessionMissing:
                print("AuthError.sessionMissing")
            default:
                print("AuthError: \(authError)")
            }
        }

        if let postgrestError = error as? PostgrestError {
            print("PostgrestError.code: \(postgrestError.code ?? "")")
            print("PostgrestError.message: \(postgrestError.message)")
            print("PostgrestError.details: \(postgrestError.detail ?? "")")
            print("PostgrestError.hint: \(postgrestError.hint ?? "")")
            print("PostgrestError.statusCode: <not exposed by PostgrestError>")
            print("PostgrestError.responseBody: <not exposed by PostgrestError>")
        }

        if let httpError = error as? HTTPError {
            print("HTTPError.statusCode: \(httpError.response.statusCode)")
            print("HTTPError.responseBody: \(String(data: httpError.data, encoding: .utf8) ?? "<non-UTF8 response body>")")
        }

        print("===================================")
        #endif
    }
}

private struct NormalizedProfileInput {
    let firstName: String?
    let lastName: String?
    let displayName: String?

    init(firstName: String, lastName: String, displayName: String) {
        self.firstName = Self.normalized(firstName)
        self.lastName = Self.normalized(lastName)
        self.displayName = Self.normalized(displayName)
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ProfileResponse: Decodable {
    let id: UUID
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}

private struct UpdateProfilePayload: Encodable {
    let id: UUID
    let firstName: String?
    let lastName: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case displayName = "display_name"
    }
}

private struct UpdateAvatarURLPayload: Encodable {
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case avatarURL = "avatar_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let avatarURL {
            try container.encode(avatarURL.absoluteString, forKey: .avatarURL)
        } else {
            try container.encodeNil(forKey: .avatarURL)
        }
    }
}
