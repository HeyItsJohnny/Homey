import Auth
import Combine
import Foundation
import PostgREST
import Supabase

enum SignUpOutcome { case signedIn, verificationRequired }

@MainActor
final class AuthenticationService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var currentUser: UserProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var isUploadingAvatar = false
    @Published var errorMessage: String?
    private let client = SupabaseManager.shared.client

    func restoreSession() async -> Bool {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let restored = try await client.auth.session
            session = restored
            currentUser = UserProfile(user: restored.user)
            await refreshCurrentUserProfile()
            return restored.user.emailConfirmedAt != nil || restored.user.confirmedAt != nil
        } catch {
            clearSession()
            debugLog(error, context: "RESTORE SESSION")
            return false
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        guard validate(email: email, password: password) else { return false }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let signedIn = try await client.auth.signIn(email: email.trimmed, password: password)
            session = signedIn; currentUser = UserProfile(user: signedIn.user)
            await refreshCurrentUserProfile()
            return true
        } catch {
            debugLog(error, context: "SIGN IN")
            errorMessage = friendlyMessage(for: error)
            clearSession()
            return false
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String, displayName: String) async -> SignUpOutcome? {
        guard validate(email: email, password: password) else { return nil }
        let values = [firstName.trimmed, lastName.trimmed, displayName.trimmed]
        guard !values[0].isEmpty else { errorMessage = "Enter your first name."; return nil }
        guard !values[1].isEmpty else { errorMessage = "Enter your last name."; return nil }
        guard !values[2].isEmpty else { errorMessage = "Enter a display name."; return nil }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.auth.signUp(email: email.trimmed, password: password)
            try await client.from("profiles").upsert(ProfilePayload(id: response.user.id, firstName: values[0], lastName: values[1], displayName: values[2])).execute()
            currentUser = UserProfile(id: response.user.id, email: response.user.email ?? email.trimmed, firstName: values[0], lastName: values[1], displayName: values[2])
            if let newSession = response.session { session = newSession; await refreshCurrentUserProfile(); return .signedIn }
            return .verificationRequired
        } catch {
            debugLog(error, context: "SIGN UP")
            errorMessage = friendlyMessage(for: error)
            return nil
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        guard !email.trimmed.isEmpty else { errorMessage = "Enter your email address."; return false }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { try await client.auth.resetPasswordForEmail(email.trimmed); return true }
        catch { debugLog(error, context: "PASSWORD RESET"); errorMessage = friendlyMessage(for: error); return false }
    }

    func signOut() async {
        isLoading = true; errorMessage = nil
        do { try await client.auth.signOut() } catch { debugLog(error, context: "SIGN OUT") }
        clearSession(); isLoading = false
    }

    func clearError() { errorMessage = nil }

    @discardableResult
    func refreshCurrentUserProfile() async -> Bool {
        guard let user = currentUser else {
            errorMessage = "Your session has expired. Please sign in again."
            return false
        }
        do {
            let rows: [ProfileResponse] = try await client.from("profiles").select("id, first_name, last_name, display_name, avatar_url").eq("id", value: user.id.uuidString).limit(1).execute().value
            if let row = rows.first { currentUser = UserProfile(id: row.id, email: user.email, firstName: row.firstName, lastName: row.lastName, displayName: row.displayName, avatarURL: row.avatarURL) }
            return true
        } catch {
            debugLog(error, context: "FETCH PROFILE")
            errorMessage = "We couldn't load your profile. Please try again."
            return false
        }
    }

    func updateCurrentUserProfile(firstName: String, lastName: String, displayName: String) async -> Bool {
        guard let user = currentUser else { errorMessage = "Your session has expired. Please sign in again."; return false }
        let values = [firstName.trimmed, lastName.trimmed, displayName.trimmed]
        guard !values[0].isEmpty else { errorMessage = "Enter your first name."; return false }
        guard !values[1].isEmpty else { errorMessage = "Enter your last name."; return false }
        guard !values[2].isEmpty else { errorMessage = "Enter a display name."; return false }
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.from("profiles").upsert(
                ProfilePayload(id: user.id, firstName: values[0], lastName: values[1], displayName: values[2])
            ).execute()
            return await refreshCurrentUserProfile()
        } catch {
            debugLog(error, context: "UPDATE PROFILE")
            errorMessage = "We couldn't update your profile. Please try again."
            return false
        }
    }

    func uploadCurrentUserAvatar(imageData: Data) async -> Bool {
        guard let user = currentUser else { errorMessage = "Your session has expired. Please sign in again."; return false }
        guard !isUploadingAvatar else { return false }
        guard !imageData.isEmpty else { errorMessage = "We couldn't prepare that photo. Please choose another image."; return false }

        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }
        let path = avatarObjectPath(for: user.id)
        do {
            try await client.storage.from("avatars").upload(
                path,
                data: imageData,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
            )
            let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
            do {
                try await updateAvatarURL(publicURL)
            } catch {
                try await updateAvatarURL(publicURL)
            }
            guard await refreshCurrentUserProfile() else { return false }
            currentUser = currentUser?.withAvatarURL(cacheBustedURL(publicURL))
            return true
        } catch {
            debugLog(error, context: "UPLOAD AVATAR")
            errorMessage = avatarMessage(for: error)
            return false
        }
    }

    func removeCurrentUserAvatar() async -> Bool {
        guard let user = currentUser else { errorMessage = "Your session has expired. Please sign in again."; return false }
        guard !isUploadingAvatar else { return false }
        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            _ = try? await client.storage.from("avatars").remove(paths: [avatarObjectPath(for: user.id)])
            try await updateAvatarURL(nil)
            return await refreshCurrentUserProfile()
        } catch {
            debugLog(error, context: "REMOVE AVATAR")
            errorMessage = avatarMessage(for: error)
            return false
        }
    }

    private func avatarObjectPath(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/profile.jpg"
    }

    private func updateAvatarURL(_ url: URL?) async throws {
        guard let user = currentUser else { return }
        try await client.from("profiles").update(AvatarURLPayload(avatarURL: url)).eq("id", value: user.id.uuidString).execute()
    }

    private func cacheBustedURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.removeAll { $0.name == "v" }
        items.append(URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970))))
        components?.queryItems = items
        return components?.url ?? url
    }

    private func avatarMessage(for error: Error) -> String {
        let message = friendlyMessage(for: error).lowercased()
        if message.contains("permission") || message.contains("policy") || message.contains("unauthorized") || message.contains("forbidden") {
            return "We couldn't upload your photo. Please check your connection and try again."
        }
        return "Unable to update your photo. Please try again."
    }

    private func validate(email: String, password: String) -> Bool {
        guard !email.trimmed.isEmpty else { errorMessage = "Enter your email address."; return false }
        guard !password.isEmpty else { errorMessage = "Enter your password."; return false }
        return true
    }

    private func clearSession() { session = nil; currentUser = nil }
    private func friendlyMessage(for error: Error) -> String {
        if let authError = error as? AuthError { return authError.message }
        if let postgrestError = error as? PostgrestError { return postgrestError.message }
        return "Something went wrong. Please try again."
    }
    private func debugLog(_ error: Error, context: String) {
        #if DEBUG
        print("[Homey] \(context): \(String(reflecting: error))")
        #endif
    }
}

private struct ProfileResponse: Decodable {
    let id: UUID; let firstName: String?; let lastName: String?; let displayName: String?; let avatarURL: URL?
    enum CodingKeys: String, CodingKey { case id; case firstName = "first_name"; case lastName = "last_name"; case displayName = "display_name"; case avatarURL = "avatar_url" }
}
private struct ProfilePayload: Encodable {
    let id: UUID; let firstName: String; let lastName: String; let displayName: String
    enum CodingKeys: String, CodingKey { case id; case firstName = "first_name"; case lastName = "last_name"; case displayName = "display_name" }
}
private struct AvatarURLPayload: Encodable {
    let avatarURL: URL?
    enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let avatarURL { try container.encode(avatarURL.absoluteString, forKey: .avatarURL) }
        else { try container.encodeNil(forKey: .avatarURL) }
    }
}
private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
