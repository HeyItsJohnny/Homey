import Combine
import Foundation
import Supabase

@MainActor
final class HomeService: ObservableObject {
    @Published private(set) var homes: [HomeSummary] = []
    @Published private(set) var isLoading = false
    @Published var selectedHome: HomeSummary?
    @Published var errorMessage: String?
    private let client = SupabaseManager.shared.client

    func loadHomes(for userID: UUID, preferredHomeID: UUID?) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let memberships: [HomeMembershipResponse] = try await client
                .from("home_members")
                .select("role, homes(id, name, timezone, week_starts_on, created_at)")
                .eq("user_id", value: userID.uuidString)
                .execute().value
            homes = memberships.compactMap { $0.summary() }
            if homes.count == 1 { selectedHome = homes[0] }
            else if let preferredHomeID { selectedHome = homes.first { $0.id == preferredHomeID } }
            else { selectedHome = nil }
        } catch {
            homes = []; selectedHome = nil
            errorMessage = "We couldn't load your Homes. Check your connection and try again."
            debugLog(error, context: "LOAD HOMES")
        }
    }

    func createHome(name: String, timezone: String, userID: UUID) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { errorMessage = "Enter a Home name."; return false }
        guard !timezone.isEmpty else { errorMessage = "Choose a timezone."; return false }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let homeID: UUID = try await client.rpc("create_home", params: CreateHomeParameters(homeName: cleanName, homeTimezone: timezone)).execute().value
            await loadHomes(for: userID, preferredHomeID: homeID)
            selectedHome = homes.first { $0.id == homeID }
            return selectedHome != nil
        } catch {
            errorMessage = "We couldn't create your Home. Please try again."
            debugLog(error, context: "CREATE HOME")
            return false
        }
    }

    func select(_ home: HomeSummary) { selectedHome = home }
    func reset() { homes = []; selectedHome = nil; errorMessage = nil }
    private func debugLog(_ error: Error, context: String) {
        #if DEBUG
        print("[Homey] \(context): \(String(reflecting: error))")
        #endif
    }
}

private struct CreateHomeParameters: Encodable {
    let homeName: String; let homeTimezone: String
    enum CodingKeys: String, CodingKey { case homeName = "home_name"; case homeTimezone = "home_timezone" }
}
