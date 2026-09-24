import Foundation
import Supabase

struct PhoneCalendarCategory: Codable, Identifiable, Hashable {
    let id: UUID
    let homeID: UUID
    let name: String
    let colorHex: String
    let iconName: String?
    let sortOrder: Int
    let systemKey: String?
    let isSystem: Bool

    var isProtectedSystemCategory: Bool { isSystem || systemKey != nil }
    var canRename: Bool { !isProtectedSystemCategory }
    var canDelete: Bool { !isProtectedSystemCategory }
    var canChangeIcon: Bool { !isProtectedSystemCategory }

    enum CodingKeys: String, CodingKey {
        case id, name
        case homeID = "home_id"
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case systemKey = "system_key"
        case isSystem = "is_system"
    }
}

enum HomeSettingsRepositoryError: LocalizedError {
    case permissionDenied
    case invalidCategory
    case loadCategoriesFailed
    case saveCategoryFailed
    case deleteCategoryFailed
    case reorderCategoriesFailed
    case clearMealsFailed
    case clearCalendarFailed
    case clearChoresFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "You don't have permission to make this change."
        case .invalidCategory: "Enter a category name and choose a valid color."
        case .loadCategoriesFailed: "Unable to load calendar categories. Please try again."
        case .saveCategoryFailed: "Unable to save this calendar category. Please try again."
        case .deleteCategoryFailed: "Unable to delete this calendar category. Please try again."
        case .reorderCategoriesFailed: "Unable to reorder calendar categories. Please try again."
        case .clearMealsFailed: "Unable to clear meals. No success was reported."
        case .clearCalendarFailed: "Unable to clear the calendar. No success was reported."
        case .clearChoresFailed: "Unable to clear chores. No success was reported."
        }
    }
}

final class HomeSettingsRepository {
    private let client = SupabaseManager.shared.client

    func fetchCategories(homeID: UUID) async throws -> [PhoneCalendarCategory] {
        do {
            let rows: [PhoneCalendarCategory] = try await client
                .from("calendar_categories")
                .select("id, home_id, name, color_hex, icon_name, sort_order, system_key, is_system")
                .eq("home_id", value: homeID.uuidString)
                .execute()
                .value
            return rows.sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.sortOrder < $1.sortOrder
            }
        } catch {
            throw HomeSettingsRepositoryError.loadCategoriesFailed
        }
    }

    func createCategory(homeID: UUID, name: String, colorHex: String, iconName: String?) async throws {
        let values = try normalizedCategory(name: name, colorHex: colorHex, iconName: iconName)
        do {
            let _: UUID = try await client.rpc(
                "create_calendar_category",
                params: CreateCategoryParameters(
                    targetHomeID: homeID,
                    categoryName: values.name,
                    categoryColorHex: values.color,
                    categoryIconName: values.icon
                )
            ).execute().value
        } catch {
            throw mappedCategoryError(error, fallback: .saveCategoryFailed)
        }
    }

    func updateCategory(_ category: PhoneCalendarCategory, name: String, colorHex: String, iconName: String?) async throws {
        let values = try normalizedCategory(name: name, colorHex: colorHex, iconName: iconName)
        if category.isProtectedSystemCategory,
           values.name != category.name || values.icon != normalizedIcon(category.iconName) {
            throw HomeSettingsRepositoryError.permissionDenied
        }
        do {
            try await client.rpc(
                "update_calendar_category",
                params: UpdateCategoryParameters(
                    targetCategoryID: category.id,
                    categoryName: values.name,
                    categoryColorHex: values.color,
                    categoryIconName: values.icon
                )
            ).execute()
        } catch {
            throw mappedCategoryError(error, fallback: .saveCategoryFailed)
        }
    }

    func deleteCategory(_ category: PhoneCalendarCategory) async throws {
        guard category.canDelete else { throw HomeSettingsRepositoryError.permissionDenied }
        do {
            try await client.rpc("delete_calendar_category", params: CategoryIDParameters(targetCategoryID: category.id)).execute()
        } catch {
            throw mappedCategoryError(error, fallback: .deleteCategoryFailed)
        }
    }

    func reorderCategories(homeID: UUID, categoryIDs: [UUID]) async throws {
        do {
            try await client.rpc(
                "reorder_calendar_categories",
                params: ReorderCategoryParameters(targetHomeID: homeID, orderedCategoryIDs: categoryIDs)
            ).execute()
        } catch {
            throw mappedCategoryError(error, fallback: .reorderCategoriesFailed)
        }
    }

    func clearMeals(homeID: UUID) async throws -> ClearMealsResult {
        do {
            let rows: [ClearMealsResult] = try await client.rpc("clear_home_meals", params: ClearHomeParameters(homeID: homeID)).execute().value
            guard let result = rows.first else { throw HomeSettingsRepositoryError.clearMealsFailed }
            return result
        } catch let error as HomeSettingsRepositoryError { throw error }
        catch { throw mappedClearError(error, fallback: .clearMealsFailed) }
    }

    func clearCalendar(homeID: UUID) async throws -> ClearCalendarResult {
        do {
            let rows: [ClearCalendarResult] = try await client.rpc("clear_home_calendar", params: ClearHomeParameters(homeID: homeID)).execute().value
            guard let result = rows.first else { throw HomeSettingsRepositoryError.clearCalendarFailed }
            return result
        } catch let error as HomeSettingsRepositoryError { throw error }
        catch { throw mappedClearError(error, fallback: .clearCalendarFailed) }
    }

    func clearChores(homeID: UUID) async throws -> ClearChoresResult {
        do {
            let rows: [ClearChoresResult] = try await client.rpc("clear_home_chores", params: ClearHomeParameters(homeID: homeID)).execute().value
            guard let result = rows.first else { throw HomeSettingsRepositoryError.clearChoresFailed }
            return result
        } catch let error as HomeSettingsRepositoryError { throw error }
        catch { throw mappedClearError(error, fallback: .clearChoresFailed) }
    }

    private func normalizedCategory(name: String, colorHex: String, iconName: String?) throws -> (name: String, color: String, icon: String?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard !name.isEmpty, color.count == 6, Int(color, radix: 16) != nil else {
            throw HomeSettingsRepositoryError.invalidCategory
        }
        return (name, color, normalizedIcon(iconName))
    }

    private func normalizedIcon(_ icon: String?) -> String? {
        let value = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func mappedCategoryError(_ error: Error, fallback: HomeSettingsRepositoryError) -> HomeSettingsRepositoryError {
        isPermissionError(error) ? .permissionDenied : fallback
    }

    private func mappedClearError(_ error: Error, fallback: HomeSettingsRepositoryError) -> HomeSettingsRepositoryError {
        isPermissionError(error) ? .permissionDenied : fallback
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let message = String(reflecting: error).lowercased()
        return message.contains("42501") || message.contains("permission") || message.contains("owner") || message.contains("admin")
    }
}

struct ClearMealsResult: Decodable {
    let mealsDeleted: Int
    let calendarEventsDeleted: Int
    enum CodingKeys: String, CodingKey { case mealsDeleted = "meals_deleted"; case calendarEventsDeleted = "calendar_events_deleted" }
}

struct ClearCalendarResult: Decodable {
    let calendarEventsDeleted: Int
    enum CodingKeys: String, CodingKey { case calendarEventsDeleted = "calendar_events_deleted" }
}

struct ClearChoresResult: Decodable {
    let choreDefinitionsDeleted: Int
    let occurrencesDeleted: Int
    let calendarEventsDeleted: Int
    let rewardsDeleted: Int
    enum CodingKeys: String, CodingKey {
        case choreDefinitionsDeleted = "chore_definitions_deleted"
        case occurrencesDeleted = "occurrences_deleted"
        case calendarEventsDeleted = "calendar_events_deleted"
        case rewardsDeleted = "rewards_deleted"
    }
}

private struct CreateCategoryParameters: Encodable {
    let targetHomeID: UUID
    let categoryName: String
    let categoryColorHex: String
    let categoryIconName: String?
    enum CodingKeys: String, CodingKey {
        case targetHomeID = "target_home_id"
        case categoryName = "category_name"
        case categoryColorHex = "category_color_hex"
        case categoryIconName = "category_icon_name"
    }
}

private struct UpdateCategoryParameters: Encodable {
    let targetCategoryID: UUID
    let categoryName: String
    let categoryColorHex: String
    let categoryIconName: String?
    enum CodingKeys: String, CodingKey {
        case targetCategoryID = "target_category_id"
        case categoryName = "category_name"
        case categoryColorHex = "category_color_hex"
        case categoryIconName = "category_icon_name"
    }
}

private struct CategoryIDParameters: Encodable {
    let targetCategoryID: UUID
    enum CodingKeys: String, CodingKey { case targetCategoryID = "target_category_id" }
}

private struct ReorderCategoryParameters: Encodable {
    let targetHomeID: UUID
    let orderedCategoryIDs: [UUID]
    enum CodingKeys: String, CodingKey {
        case targetHomeID = "target_home_id"
        case orderedCategoryIDs = "ordered_category_ids"
    }
}

private struct ClearHomeParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "requested_home_id" }
}
