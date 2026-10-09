import Foundation
import Supabase

struct HomeAdminPinStatus: Decodable, Equatable, Sendable {
    let hasPIN: Bool
    let canManagePIN: Bool

    enum CodingKeys: String, CodingKey {
        case hasPIN = "has_pin"
        case canManagePIN = "can_manage_pin"
    }
}

struct AdminPinService {
    private let client = SupabaseManager.shared.client

    func status(homeID: UUID) async throws -> HomeAdminPinStatus {
        do {
            let rows: [HomeAdminPinStatus] = try await client.rpc(
                "get_my_home_admin_pin_status",
                params: AdminPinHomeParameters(homeID: homeID)
            ).execute().value
            guard let status = rows.first else {
                throw AdminPinServiceError.statusUnavailable
            }
            return status
        } catch let error as AdminPinServiceError {
            throw error
        } catch {
            throw mappedError(error, fallback: .statusUnavailable)
        }
    }

    func setPIN(_ pin: String, homeID: UUID) async throws {
        guard Self.isValid(pin) else { throw AdminPinServiceError.invalidPIN }
        do {
            try await client.rpc(
                "set_my_home_admin_pin",
                params: SetAdminPinParameters(homeID: homeID, pin: pin)
            ).execute()
        } catch {
            throw mappedError(error, fallback: .saveFailed)
        }
    }

    func removePIN(homeID: UUID) async throws {
        do {
            try await client.rpc(
                "remove_my_home_admin_pin",
                params: AdminPinHomeParameters(homeID: homeID)
            ).execute()
        } catch {
            throw mappedError(error, fallback: .removeFailed)
        }
    }

    static func normalized(_ value: String) -> String {
        String(value.filter { "0123456789".contains($0) }.prefix(4))
    }

    static func isValid(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy { "0123456789".contains($0) }
    }

    private func mappedError(_ error: Error, fallback: AdminPinServiceError) -> AdminPinServiceError {
        let message = ((error as? PostgrestError)?.message ?? error.localizedDescription).lowercased()
        if message.contains("exactly 4") || message.contains("four") && message.contains("digit") {
            return .invalidPIN
        }
        if message.contains("already in use") {
            return .alreadyInUse
        }
        if message.contains("owner") || message.contains("admin") || message.contains("permission") || message.contains("42501") {
            return .permissionDenied
        }
        return fallback
    }
}

enum AdminPinServiceError: LocalizedError {
    case invalidPIN
    case permissionDenied
    case alreadyInUse
    case statusUnavailable
    case saveFailed
    case removeFailed

    var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "PIN must contain exactly 4 digits."
        case .permissionDenied:
            return "Only Home owners and admins can manage an iPad Admin PIN."
        case .alreadyInUse:
            return "That PIN is already in use for this Home. Choose a different PIN."
        case .statusUnavailable:
            return "We couldn't load the iPad Admin PIN status."
        case .saveFailed:
            return "We couldn't save the iPad Admin PIN. Please try again."
        case .removeFailed:
            return "We couldn't remove the iPad Admin PIN. Please try again."
        }
    }
}

private struct AdminPinHomeParameters: Encodable {
    let homeID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
    }
}

private struct SetAdminPinParameters: Encodable {
    let homeID: UUID
    let pin: String

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case pin = "requested_pin"
    }
}
