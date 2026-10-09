import Foundation
import Supabase

struct MealPlanEntryService {
    private let client = SupabaseManager.shared.client

    func fetchEntries(homeID: UUID, date: String) async throws -> [MealPlanEntry] {
        do {
            let entries: [MealPlanEntry] = try await client.rpc(
                "get_meal_plan_entries",
                params: MealPlanRangeParameters(homeID: homeID, startDate: date, endDate: date)
            ).execute().value

            return entries.sorted(by: Self.precedes)
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            throw MealPlanEntryServiceError.loadFailed
        }
    }

    func saveEntry(
        homeID: UUID,
        mealID: UUID,
        date: String,
        mealType: MealType,
        sortOrder: Int
    ) async throws {
        do {
            try await client.rpc(
                "save_meal_plan_entry",
                params: SaveMealPlanEntryParameters(
                    homeID: homeID,
                    entryID: nil,
                    mealID: mealID,
                    plannedDate: date,
                    mealType: mealType,
                    plannedServings: nil,
                    mealNotes: nil,
                    sortOrder: sortOrder
                )
            ).execute()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            throw MealPlanEntryServiceError.saveFailed
        }
    }

    func deleteEntry(homeID: UUID, entryID: UUID) async throws {
        do {
            try await client.rpc(
                "delete_meal_plan_entry",
                params: DeleteMealPlanEntryParameters(homeID: homeID, entryID: entryID)
            ).execute()
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            throw MealPlanEntryServiceError.deleteFailed
        }
    }

    private static func precedes(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool {
        if lhs.mealType != rhs.mealType { return lhs.mealType.rawValue < rhs.mealType.rawValue }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let value = error as NSError
        if value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }
}

enum MealPlanEntryServiceError: LocalizedError {
    case loadFailed
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return "We couldn't load the meal plan for this date."
        case .saveFailed:
            return "That meal couldn't be added to the plan."
        case .deleteFailed:
            return "That meal couldn't be removed from the plan."
        }
    }
}

private struct MealPlanRangeParameters: Encodable {
    let homeID: UUID
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case startDate = "requested_start_date"
        case endDate = "requested_end_date"
    }
}

private struct SaveMealPlanEntryParameters: Encodable {
    let homeID: UUID
    let entryID: UUID?
    let mealID: UUID
    let plannedDate: String
    let mealType: MealType
    let plannedServings: Double?
    let mealNotes: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case entryID = "requested_entry_id"
        case mealID = "requested_meal_id"
        case plannedDate = "requested_planned_date"
        case mealType = "requested_meal_type"
        case plannedServings = "requested_planned_servings"
        case mealNotes = "requested_meal_notes"
        case sortOrder = "requested_sort_order"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(homeID, forKey: .homeID)
        try values.encodeIfPresent(entryID, forKey: .entryID)
        if entryID == nil { try values.encodeNil(forKey: .entryID) }
        try values.encode(mealID, forKey: .mealID)
        try values.encode(plannedDate, forKey: .plannedDate)
        try values.encode(mealType, forKey: .mealType)
        try values.encodeIfPresent(plannedServings, forKey: .plannedServings)
        if plannedServings == nil { try values.encodeNil(forKey: .plannedServings) }
        try values.encodeIfPresent(mealNotes, forKey: .mealNotes)
        if mealNotes == nil { try values.encodeNil(forKey: .mealNotes) }
        try values.encode(sortOrder, forKey: .sortOrder)
    }
}

private struct DeleteMealPlanEntryParameters: Encodable {
    let homeID: UUID
    let entryID: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case entryID = "requested_entry_id"
    }
}
