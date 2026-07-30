import Foundation
import PostgREST
import Supabase

@MainActor
final class HomeService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var homes: [HomeSummary] = []
    @Published private(set) var isLoading = false
    @Published var selectedHomeID: UUID?
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let client = SupabaseManager.shared.client

    // MARK: - Loading

    func loadHomes(for userID: UUID) async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            homes = try await fetchHomes(for: userID)
            restoreOrSelectHome()
        } catch {
            homes = []
            selectedHomeID = nil
            errorMessage = "Unable to load your Homes."

            #if DEBUG
            print("Failed to load Homes: \(error)")
            #endif
        }

        isLoading = false
    }

    func createHome(name: String, timezone: String, userID: UUID) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a Home name."
            return false
        }

        guard !trimmedTimezone.isEmpty else {
            errorMessage = "Enter a timezone."
            return false
        }

        guard !isLoading else {
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            try await client
                .rpc(
                    "create_home",
                    params: CreateHomeParams(
                        homeName: trimmedName,
                        timezone: trimmedTimezone
                    )
                )
                .execute()

            homes = try await fetchHomes(for: userID)
            restoreOrSelectHome(preferredHomeName: trimmedName)
            isLoading = false
            return true
        } catch {
            errorMessage = "Unable to create Home."

            #if DEBUG
            print("Failed to create Home: \(error)")
            #endif

            isLoading = false
            return false
        }
    }

    func selectHome(id: UUID?) {
        selectedHomeID = id
    }

    func restoreSelectedHome(from storedValue: String?) {
        selectedHomeID = storedValue.flatMap(UUID.init(uuidString:))
        restoreOrSelectHome()
    }

    func selectedHome() -> HomeSummary? {
        guard let selectedHomeID else {
            return nil
        }

        return homes.first { $0.id == selectedHomeID }
    }

    // MARK: - Private Helpers

    private func fetchHomes(for userID: UUID) async throws -> [HomeSummary] {
        let memberships: [HomeMembershipResponse] = try await client
            .from("home_members")
            .select("role, homes(id, name, timezone, created_at)")
            .eq("user_id", value: userID.uuidString)
            .eq("status", value: "active")
            .execute()
            .value

        var summaries: [HomeSummary] = []

        for membership in memberships {
            guard let home = membership.home else {
                continue
            }

            let memberCount = try await loadMemberCount(homeID: home.id)
            summaries.append(
                HomeSummary(
                    id: home.id,
                    name: home.name,
                    timezone: home.timezone,
                    role: membership.role,
                    createdAt: home.createdAt,
                    memberCount: memberCount
                )
            )
        }

        return summaries
    }

    private func loadMemberCount(homeID: UUID) async throws -> Int {
        let members: [HomeMemberResponse] = try await client
            .from("home_members")
            .select("id")
            .eq("home_id", value: homeID.uuidString)
            .eq("status", value: "active")
            .execute()
            .value

        return members.count
    }

    private func restoreOrSelectHome(preferredHomeName: String? = nil) {
        guard !homes.isEmpty else {
            selectedHomeID = nil
            return
        }

        if let selectedHomeID, homes.contains(where: { $0.id == selectedHomeID }) {
            return
        }

        if let preferredHomeName,
           let preferredHome = homes.first(where: { $0.name == preferredHomeName }) {
            selectedHomeID = preferredHome.id
        } else {
            selectedHomeID = homes[0].id
        }
    }
}

private struct CreateHomeParams: Encodable {
    let homeName: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case homeName = "home_name"
        case timezone
    }
}

private struct HomeMembershipResponse: Decodable {
    let role: String?
    let home: HomeResponse?

    enum CodingKeys: String, CodingKey {
        case role
        case home = "homes"
    }
}

private struct HomeResponse: Decodable {
    let id: UUID
    let name: String
    let timezone: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case timezone
        case createdAt = "created_at"
    }
}

private struct HomeMemberResponse: Decodable {
    let id: UUID
}
