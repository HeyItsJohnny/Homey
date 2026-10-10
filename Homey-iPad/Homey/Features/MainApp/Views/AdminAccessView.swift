import SwiftUI
import Supabase
import Combine

struct HomeAdminSession: Equatable, Sendable {
    let token: String
    let adminUserID: UUID
    let role: HomeMemberRole
    let displayName: String
    let expiresAt: Date
}

enum HomeAdminAccessState: Equatable {
    case locked
    case verifying
    case unlocked(HomeAdminSession)
}

@MainActor
final class HomeAdminAccessController: ObservableObject {
    @Published private(set) var state: HomeAdminAccessState = .locked
    @Published private(set) var errorMessage: String?

    private let service = HomeAdminSessionService()
    private var scopedHomeID: UUID?
    private var expirationTask: Task<Void, Never>?
    private var unlockAttemptID: UUID?

    var isVerifying: Bool {
        state == .verifying
    }

    func scope(to homeID: UUID?) {
        guard homeID != scopedHomeID else { return }
        let revocation = revocationRequest()
        clearLocalSession()
        scopedHomeID = homeID
        revokeIfNeeded(revocation)
    }

    func beginPINEntry() {
        guard state == .locked else { return }
        errorMessage = nil
    }

    func unlock(homeID: UUID, pin: String) async {
        guard state == .locked,
              scopedHomeID == homeID,
              HomeAdminSessionService.isValidPIN(pin) else {
            return
        }

        state = .verifying
        errorMessage = nil
        let attemptID = UUID()
        unlockAttemptID = attemptID

        do {
            let session = try await service.unlock(homeID: homeID, pin: pin)
            guard unlockAttemptID == attemptID,
                  scopedHomeID == homeID else {
                await service.lock(homeID: homeID, sessionToken: session.token)
                return
            }
            unlockAttemptID = nil
            state = .unlocked(session)
            scheduleExpiration(for: session, homeID: homeID)
        } catch {
            guard unlockAttemptID == attemptID,
                  scopedHomeID == homeID else { return }
            unlockAttemptID = nil
            state = .locked
            errorMessage = error.localizedDescription
        }
    }

    func lock() {
        let revocation = revocationRequest()
        clearLocalSession()
        revokeIfNeeded(revocation)
    }

    func extendSessionAfterAdminActivity() {
        guard let scopedHomeID,
              case .unlocked(let session) = state else {
            return
        }

        let refreshedSession = HomeAdminSession(
            token: session.token,
            adminUserID: session.adminUserID,
            role: session.role,
            displayName: session.displayName,
            expiresAt: Date().addingTimeInterval(295)
        )
        state = .unlocked(refreshedSession)
        scheduleExpiration(for: refreshedSession, homeID: scopedHomeID)
    }

    private func clearLocalSession() {
        expirationTask?.cancel()
        expirationTask = nil
        unlockAttemptID = nil
        state = .locked
        errorMessage = nil
    }

    private func revocationRequest() -> (homeID: UUID, token: String)? {
        guard let scopedHomeID,
              case .unlocked(let session) = state else {
            return nil
        }
        return (scopedHomeID, session.token)
    }

    private func revokeIfNeeded(_ request: (homeID: UUID, token: String)?) {
        guard let request else { return }
        Task {
            await service.lock(homeID: request.homeID, sessionToken: request.token)
        }
    }

    private func scheduleExpiration(for session: HomeAdminSession, homeID: UUID) {
        expirationTask?.cancel()
        let delay = max(0, session.expiresAt.timeIntervalSinceNow)
        expirationTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled,
                  let self,
                  self.scopedHomeID == homeID,
                  case .unlocked(let activeSession) = self.state,
                  activeSession.token == session.token else {
                return
            }
            self.lock()
        }
    }
}

private struct HomeAdminSessionService {
    private let client = SupabaseManager.shared.client

    func unlock(homeID: UUID, pin: String) async throws -> HomeAdminSession {
        guard Self.isValidPIN(pin) else {
            throw HomeAdminSessionError.incorrectPIN
        }

        do {
            let rows: [HomeAdminUnlockResponse] = try await client.rpc(
                "unlock_home_admin",
                params: HomeAdminUnlockParameters(homeID: homeID, pin: pin)
            ).execute().value

            guard let response = rows.first,
                  let expiration = HomeAdminExpirationParser.date(from: response.expiresAt) else {
                throw HomeAdminSessionError.invalidResponse
            }

            return HomeAdminSession(
                token: response.sessionToken,
                adminUserID: response.adminUserID,
                role: response.adminRole,
                displayName: response.adminDisplayName,
                expiresAt: expiration
            )
        } catch let error as HomeAdminSessionError {
            throw error
        } catch {
            throw mapUnlockError(error)
        }
    }

    func lock(homeID: UUID, sessionToken: String) async {
        do {
            try await client.rpc(
                "lock_home_admin_session",
                params: HomeAdminLockParameters(homeID: homeID, sessionToken: sessionToken)
            ).execute()
        } catch {
            // Local locking is authoritative for the shared device. Revocation is best effort.
        }
    }

    static func isValidPIN(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy { "0123456789".contains($0) }
    }

    private func mapUnlockError(_ error: Error) -> HomeAdminSessionError {
        let message = ((error as? PostgrestError)?.message ?? error.localizedDescription).lowercased()
        if message.contains("too many") ||
            message.contains("temporar") && message.contains("lock") ||
            message.contains("rate limit") ||
            message.contains("429") {
            return .tooManyAttempts
        }
        if message.contains("incorrect pin") || message.contains("invalid pin") {
            return .incorrectPIN
        }
        return .unlockFailed
    }
}

private enum HomeAdminSessionError: LocalizedError {
    case incorrectPIN
    case tooManyAttempts
    case invalidResponse
    case unlockFailed

    var errorDescription: String? {
        switch self {
        case .incorrectPIN:
            return "Incorrect PIN"
        case .tooManyAttempts:
            return "Too many attempts. Try again later."
        case .invalidResponse, .unlockFailed:
            return "Admin access could not be unlocked. Please try again."
        }
    }
}

private struct HomeAdminUnlockResponse: Decodable {
    let sessionToken: String
    let adminUserID: UUID
    let adminRole: HomeMemberRole
    let adminDisplayName: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
        case adminUserID = "admin_user_id"
        case adminRole = "admin_role"
        case adminDisplayName = "admin_display_name"
        case expiresAt = "expires_at"
    }
}

private struct HomeAdminUnlockParameters: Encodable {
    let homeID: UUID
    let pin: String

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case pin = "requested_pin"
    }
}

private struct HomeAdminLockParameters: Encodable {
    let homeID: UUID
    let sessionToken: String

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case sessionToken = "requested_session_token"
    }
}

private enum HomeAdminExpirationParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }
}

struct AdminAccessView: View {
    @EnvironmentObject private var homeService: HomeService
    @ObservedObject var controller: HomeAdminAccessController
    @State private var enteredPIN = ""

    var body: some View {
        Group {
            switch controller.state {
            case .locked, .verifying:
                lockedView
            case .unlocked(let session):
                unlockedView(session)
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 38)
        .frame(maxWidth: 1180, maxHeight: .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
        .onChange(of: controller.state) { _, state in
            if state != .locked {
                enteredPIN = ""
            }
        }
        .onDisappear {
            enteredPIN = ""
            controller.lock()
        }
    }

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Admin Access")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter an Owner or Admin PIN to continue.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .padding(.trailing, 78)

            HStack(spacing: 48) {
                VStack(spacing: 22) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 96, height: 96)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

                    HStack(spacing: 18) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < enteredPIN.count ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.softBorder)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .accessibilityLabel("\(enteredPIN.count) of 4 PIN digits entered")

                    if controller.isVerifying {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(HomeyDashboardTheme.warmBrown)
                            Text("Verifying…")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    } else if let errorMessage = controller.errorMessage {
                        Text(errorMessage)
                            .font(.headline)
                            .foregroundStyle(HomeyDashboardTheme.softRed)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Use the keypad to enter your 4-digit PIN.")
                            .font(.subheadline)
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)

                numericKeypad
                    .frame(width: 360)
            }
            .padding(.horizontal, 54)
            .padding(.vertical, 38)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dashboardCard(cornerRadius: 34)
        }
    }

    private var numericKeypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
            ForEach(1...9, id: \.self) { digit in
                keypadButton(title: String(digit)) {
                    enterDigit(String(digit))
                }
            }

            Color.clear
                .frame(height: 72)
                .accessibilityHidden(true)

            keypadButton(title: "0") {
                enterDigit("0")
            }

            Button {
                guard !controller.isVerifying, !enteredPIN.isEmpty else { return }
                controller.beginPINEntry()
                enteredPIN.removeLast()
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(controller.isVerifying)
            .accessibilityLabel("Backspace")
        }
    }

    private func keypadButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(controller.isVerifying)
        .accessibilityLabel(title)
    }

    private func enterDigit(_ digit: String) {
        guard !controller.isVerifying,
              enteredPIN.count < 4,
              let homeID = homeService.selectedHomeID else {
            return
        }

        controller.beginPINEntry()
        enteredPIN.append(digit)

        guard enteredPIN.count == 4 else { return }
        let submittedPIN = enteredPIN
        enteredPIN = ""
        Task {
            await controller.unlock(homeID: homeID, pin: submittedPIN)
        }
    }

    private func unlockedView(_ session: HomeAdminSession) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Admin")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Signed in as \(session.displayName)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)

                    Text(session.role.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                }

                Spacer()

                Button {
                    controller.lock()
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 52)
                        .background(HomeyDashboardTheme.warmBrown, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 78)

            if let homeID = homeService.selectedHomeID {
                AdminApprovalsView(
                    homeID: homeID,
                    session: session,
                    controller: controller
                )
            }
        }
    }
}
