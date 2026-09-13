import Foundation
import PostgREST
import Supabase

@MainActor
final class GroceryRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseManager.shared.client
    }

    var categories: [GroceryCategory] { GroceryCategory.allCases }

    func defaultList(homeID: UUID) async throws -> GroceryList {
        if let existing = try await fetchDefaultList(homeID: homeID) { return existing }
        let userID = try await client.auth.session.user.id
        do {
            return try await client.from("grocery_lists")
                .insert(CreateListPayload(homeID: homeID, createdBy: userID))
                .select().single().execute().value
        } catch {
            // A concurrent client may have created the Home's default list.
            if isUniqueViolation(error), let existing = try await fetchDefaultList(homeID: homeID) { return existing }
            throw error
        }
    }

    func fetchItems(listID: UUID) async throws -> [GroceryItem] {
        try await client.from("grocery_items").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .order("created_at").execute().value
    }

    func fetchSources(listID: UUID) async throws -> [GrocerySource] {
        try await client.from("grocery_sources").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .eq("is_active", value: true)
            .order("created_at").execute().value
    }

    func fetchItemSources(itemIDs: [UUID]) async throws -> [GroceryItemSource] {
        guard !itemIDs.isEmpty else { return [] }
        return try await client.from("grocery_item_sources").select()
            .in("grocery_item_id", values: itemIDs.map(\.uuidString))
            .execute().value
    }

    func loadItemsWithSources(listID: UUID) async throws -> [GroceryItemWithSources] {
        async let loadedItems = fetchItems(listID: listID)
        async let loadedSources = fetchSources(listID: listID)
        let (items, sources) = try await (loadedItems, loadedSources)
        let relationships = try await fetchItemSources(itemIDs: items.map(\.id))
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let sourceIDsByItem = Dictionary(grouping: relationships, by: \.groceryItemID)
        return items.map { item in
            let resolvedSources = (sourceIDsByItem[item.id] ?? [])
                .compactMap { sourceByID[$0.grocerySourceID] }
                .sorted { $0.createdAt < $1.createdAt }
            return GroceryItemWithSources(item: item, sources: resolvedSources)
        }
    }

    func addManualItem(
        listID: UUID,
        homeID: UUID,
        displayName: String,
        category: GroceryCategory? = nil
    ) async throws -> GroceryItem {
        try await findOrCreateItem(
            listID: listID,
            homeID: homeID,
            displayName: displayName,
            category: category ?? GroceryCategoryMatcher.category(for: displayName)
        )
    }

    func addManualItemWithResult(
        listID: UUID,
        homeID: UUID,
        displayName: String,
        category: GroceryCategory
    ) async throws -> AddManualGroceryItemResult {
        let resolution = try await resolveItem(
            listID: listID,
            homeID: homeID,
            displayName: displayName,
            category: category
        )
        return AddManualGroceryItemResult(item: resolution.item, wasCreated: resolution.created)
    }

    func findOrCreateItem(
        listID: UUID,
        homeID: UUID,
        displayName: String,
        category: GroceryCategory
    ) async throws -> GroceryItem {
        try await resolveItem(listID: listID, homeID: homeID, displayName: displayName, category: category).item
    }

    private func resolveItem(
        listID: UUID,
        homeID: UUID,
        displayName: String,
        category: GroceryCategory
    ) async throws -> (item: GroceryItem, created: Bool) {
        let normalizedName = GroceryNameNormalizer.normalize(displayName)
        let cleanDisplayName = GroceryNameNormalizer.displayName(displayName)
        guard !normalizedName.isEmpty else { throw GroceryRepositoryError.emptyItemName }
        if let existing = try await fetchItem(listID: listID, normalizedName: normalizedName) { return (existing, false) }

        let userID = try await client.auth.session.user.id
        let payload = CreateItemPayload(
            groceryListID: listID,
            homeID: homeID,
            ingredientName: cleanDisplayName,
            normalizedName: normalizedName,
            category: category,
            createdBy: userID
        )
        do {
            let item: GroceryItem = try await client.from("grocery_items").insert(payload)
                .select().single().execute().value
            return (item, true)
        } catch {
            // The database unique index is authoritative under concurrent inserts.
            if isUniqueViolation(error), let winner = try await fetchItem(listID: listID, normalizedName: normalizedName) {
                return (winner, false)
            }
            throw error
        }
    }

    func findOrCreateSource(
        listID: UUID,
        homeID: UUID,
        type: GrocerySourceType,
        referenceID: UUID,
        label: String,
        date: Date? = nil,
        calendar: Calendar? = nil
    ) async throws -> GrocerySource {
        if let existing = try await fetchSource(listID: listID, type: type, referenceID: referenceID) { return existing }
        if let inactive = try await fetchAnySource(listID: listID, type: type, referenceID: referenceID) {
            return try await client.from("grocery_sources")
                .update(UpdateSourceActivityPayload(isActive: true))
                .eq("id", value: inactive.id.uuidString)
                .select().single().execute().value
        }
        let userID = try await client.auth.session.user.id
        do {
            return try await client.from("grocery_sources")
                .insert(CreateSourcePayload(
                    groceryListID: listID,
                    homeID: homeID,
                    sourceType: type,
                    sourceRefID: referenceID,
                    sourceLabel: label,
                    sourceDate: date.map { Self.dateOnlyString($0, calendar: calendar ?? .autoupdatingCurrent) },
                    createdBy: userID
                ))
                .select().single().execute().value
        } catch {
            if isUniqueViolation(error), let winner = try await fetchSource(listID: listID, type: type, referenceID: referenceID) {
                return winner
            }
            throw error
        }
    }

    @discardableResult
    func attach(sourceID: UUID, to itemID: UUID) async throws -> Bool {
        do {
            try await client.from("grocery_item_sources")
                .insert(CreateItemSourcePayload(groceryItemID: itemID, grocerySourceID: sourceID))
                .execute()
            return true
        } catch where isUniqueViolation(error) {
            // Composite primary key makes repeated source processing idempotent.
            return false
        }
    }

    func removeAssociation(itemID: UUID, sourceID: UUID) async throws {
        try await client.from("grocery_item_sources").delete()
            .eq("grocery_item_id", value: itemID.uuidString)
            .eq("grocery_source_id", value: sourceID.uuidString)
            .execute()
    }

    func hasProcessedSource(listID: UUID, type: GrocerySourceType, referenceID: UUID) async throws -> Bool {
        try await fetchSource(listID: listID, type: type, referenceID: referenceID) != nil
    }

    func addIngredients(
        _ ingredientNames: [String],
        listID: UUID,
        homeID: UUID,
        source: GrocerySource
    ) async throws -> [GroceryItem] {
        var resolved: [GroceryItem] = []
        var seenNames: Set<String> = []
        for name in ingredientNames {
            let normalizedName = GroceryNameNormalizer.normalize(name)
            guard !normalizedName.isEmpty, seenNames.insert(normalizedName).inserted else { continue }
            let item = try await findOrCreateItem(
                listID: listID,
                homeID: homeID,
                displayName: GroceryNameNormalizer.recipeDisplayName(name),
                category: GroceryCategoryMatcher.category(for: name)
            )
            try await attach(sourceID: source.id, to: item.id)
            resolved.append(item)
        }
        return resolved
    }

    func addHomeRecipe(
        mealID: UUID,
        label: String,
        listID: UUID,
        homeID: UUID
    ) async throws -> [GroceryItem] {
        let names = try await ingredientNames(mealID: mealID)
        guard names.contains(where: { !GroceryNameNormalizer.normalize($0).isEmpty }) else { return [] }
        let source = try await findOrCreateSource(
            listID: listID,
            homeID: homeID,
            type: .homeRecipe,
            referenceID: mealID,
            label: label
        )
        return try await addIngredients(
            names,
            listID: listID,
            homeID: homeID,
            source: source
        )
    }

    func addHomeRecipeToDefaultList(
        mealID: UUID,
        recipeName: String,
        homeID: UUID
    ) async throws -> AddHomeRecipeToGroceriesResult {
        let rawNames = try await ingredientNames(mealID: mealID)
        var seen: Set<String> = []
        let names = rawNames.compactMap { rawName -> String? in
            let normalized = GroceryNameNormalizer.normalize(rawName)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return rawName
        }

        #if DEBUG
        print("[Groceries] Add Home Recipe")
        print("[Groceries] mealID=\(mealID.uuidString)")
        print("[Groceries] recipeName=\(recipeName)")
        print("[Groceries] ingredientCount=\(names.count)")
        #endif

        guard !names.isEmpty else {
            return AddHomeRecipeToGroceriesResult(ingredientCount: 0, successfulCount: 0, newAssociationCount: 0, failureCount: 0)
        }

        let list = try await defaultList(homeID: homeID)
        let source = try await findOrCreateSource(
            listID: list.id,
            homeID: homeID,
            type: .homeRecipe,
            referenceID: mealID,
            label: recipeName
        )
        var successfulCount = 0
        var newAssociationCount = 0
        var failureCount = 0

        for name in names {
            let normalized = GroceryNameNormalizer.normalize(name)
            do {
                let resolution = try await resolveItem(
                    listID: list.id,
                    homeID: homeID,
                    displayName: GroceryNameNormalizer.recipeDisplayName(name),
                    category: GroceryCategoryMatcher.category(for: name)
                )
                #if DEBUG
                print("[Groceries] ingredient=\(GroceryNameNormalizer.displayName(name)) normalized=\(normalized)")
                print("[Groceries] item=\(resolution.created ? "created category=\(resolution.item.category.rawValue)" : "reused")")
                #endif
                let attached = try await attach(sourceID: source.id, to: resolution.item.id)
                successfulCount += 1
                if attached { newAssociationCount += 1 }
                #if DEBUG
                print("[Groceries] sourceAssociation=\(attached ? "attached" : "existing")")
                #endif
            } catch {
                failureCount += 1
                #if DEBUG
                print("[Groceries] FAILED ingredient=\(GroceryNameNormalizer.displayName(name))")
                print("[Groceries] error=\(String(reflecting: error))")
                #endif
            }
        }

        return AddHomeRecipeToGroceriesResult(
            ingredientCount: names.count,
            successfulCount: successfulCount,
            newAssociationCount: newAssociationCount,
            failureCount: failureCount
        )
    }

    func addMealEvent(
        eventID: UUID,
        mealID: UUID,
        label: String,
        date: Date,
        isLeftover: Bool,
        listID: UUID,
        homeID: UUID
    ) async throws -> [GroceryItem] {
        guard !isLeftover else { return [] }
        let source = try await findOrCreateSource(
            listID: listID,
            homeID: homeID,
            type: .mealEvent,
            referenceID: eventID,
            label: label,
            date: date
        )
        return try await addIngredients(
            try await ingredientNames(mealID: mealID),
            listID: listID,
            homeID: homeID,
            source: source
        )
    }

    func addMealPlanDay(
        _ meals: [GroceryMealEventInput],
        selectedDate: Date,
        homeID: UUID,
        calendar: Calendar
    ) async throws -> AddMealPlanDayToGroceriesResult {
        #if DEBUG
        print("[Groceries] Add Meal Plan Day")
        print("[Groceries] selectedDate=\(Self.dateOnlyString(selectedDate, calendar: calendar))")
        print("[Groceries] scheduledMealCount=\(meals.count)")
        #endif

        let freshMeals = meals.filter { !$0.isLeftover }
        guard !freshMeals.isEmpty else {
            return AddMealPlanDayToGroceriesResult(meals: meals.map {
                GroceryMealEventResult(eventID: $0.eventID, label: $0.label, status: .leftoverSkipped)
            })
        }
        let ingredientsByMealID = try await ingredientNamesByMealID(Set(freshMeals.map(\.mealID)))
        let hasAnyIngredient = freshMeals.contains { meal in
            (ingredientsByMealID[meal.mealID] ?? []).contains {
                !GroceryNameNormalizer.normalize($0).isEmpty
            }
        }
        guard hasAnyIngredient else {
            return AddMealPlanDayToGroceriesResult(meals: meals.map {
                GroceryMealEventResult(
                    eventID: $0.eventID,
                    label: $0.label,
                    status: $0.isLeftover ? .leftoverSkipped : .noIngredients
                )
            })
        }
        let list = try await defaultList(homeID: homeID)
        var results: [GroceryMealEventResult] = []

        for meal in meals {
            #if DEBUG
            print("[Groceries] eventID=\(meal.eventID.uuidString)")
            print("[Groceries] mealID=\(meal.mealID.uuidString)")
            print("[Groceries] meal=\(meal.label)")
            print("[Groceries] isLeftover=\(meal.isLeftover)")
            #endif
            if meal.isLeftover {
                #if DEBUG
                print("[Groceries] meal=\(meal.label) skipped=leftover")
                #endif
                results.append(.init(eventID: meal.eventID, label: meal.label, status: .leftoverSkipped))
                continue
            }

            var seen: Set<String> = []
            let names = (ingredientsByMealID[meal.mealID] ?? []).compactMap { rawName -> String? in
                let normalized = GroceryNameNormalizer.normalize(rawName)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
                return rawName
            }
            #if DEBUG
            print("[Groceries] ingredientCount=\(names.count)")
            #endif
            guard !names.isEmpty else {
                results.append(.init(eventID: meal.eventID, label: meal.label, status: .noIngredients))
                continue
            }

            do {
                let source = try await findOrCreateSource(
                    listID: list.id,
                    homeID: homeID,
                    type: .mealEvent,
                    referenceID: meal.eventID,
                    label: meal.label,
                    date: selectedDate,
                    calendar: calendar
                )
                var newAssociations = 0
                var ingredientFailures = 0
                for name in names {
                    do {
                        let resolution = try await resolveItem(
                            listID: list.id,
                            homeID: homeID,
                            displayName: GroceryNameNormalizer.recipeDisplayName(name),
                            category: GroceryCategoryMatcher.category(for: name)
                        )
                        #if DEBUG
                        print("[Groceries] ingredient=\(GroceryNameNormalizer.displayName(name)) normalized=\(GroceryNameNormalizer.normalize(name))")
                        print("[Groceries] groceryItem=\(resolution.created ? "created" : "reused")")
                        #endif
                        let attached = try await attach(sourceID: source.id, to: resolution.item.id)
                        if attached { newAssociations += 1 }
                        #if DEBUG
                        print("[Groceries] sourceAssociation=\(attached ? "attached" : "existing")")
                        #endif
                    } catch {
                        ingredientFailures += 1
                        #if DEBUG
                        print("[Groceries] FAILED eventID=\(meal.eventID.uuidString) ingredient=\(GroceryNameNormalizer.displayName(name))")
                        print("[Groceries] error=\(String(reflecting: error))")
                        #endif
                    }
                }
                let status: GroceryMealEventResult.Status
                if ingredientFailures > 0 { status = .failed }
                else if newAssociations == 0 { status = .alreadyProcessed }
                else { status = .added }
                results.append(.init(eventID: meal.eventID, label: meal.label, status: status))
            } catch {
                #if DEBUG
                print("[Groceries] FAILED eventID=\(meal.eventID.uuidString) error=\(String(reflecting: error))")
                #endif
                results.append(.init(eventID: meal.eventID, label: meal.label, status: .failed))
            }
        }

        return AddMealPlanDayToGroceriesResult(meals: results)
    }

    func setChecked(_ checked: Bool, itemID: UUID) async throws -> GroceryItem {
        try await client.from("grocery_items").update(UpdateCheckedPayload(isChecked: checked))
            .eq("id", value: itemID.uuidString).select().single().execute().value
    }

    func changeCategory(_ category: GroceryCategory, itemID: UUID) async throws -> GroceryItem {
        try await client.from("grocery_items").update(UpdateCategoryPayload(category: category))
            .eq("id", value: itemID.uuidString).select().single().execute().value
    }

    func updateItem(
        _ item: GroceryItem,
        name: String,
        category: GroceryCategory
    ) async throws -> UpdateGroceryItemResult {
        let displayName = GroceryNameNormalizer.displayName(name)
        let normalizedName = GroceryNameNormalizer.normalize(name)
        guard !normalizedName.isEmpty else { throw GroceryRepositoryError.emptyItemName }

        if let target = try await fetchItem(listID: item.groceryListID, normalizedName: normalizedName), target.id != item.id {
            let relationships = try await fetchItemSources(itemIDs: [item.id])
            for relationship in relationships {
                _ = try await attach(sourceID: relationship.grocerySourceID, to: target.id)
            }
            try await deleteItem(itemID: item.id)
            return UpdateGroceryItemResult(item: target, removedItemID: item.id)
        }

        let saved: GroceryItem = try await client.from("grocery_items")
            .update(UpdateItemPayload(ingredientName: displayName, normalizedName: normalizedName, category: category))
            .eq("id", value: item.id.uuidString)
            .select().single().execute().value
        return UpdateGroceryItemResult(item: saved, removedItemID: nil)
    }

    func deleteItem(itemID: UUID) async throws {
        let relationships = try await fetchItemSources(itemIDs: [itemID])
        try await client.from("grocery_items").delete().eq("id", value: itemID.uuidString).execute()
        try await cleanupInactiveSources(sourceIDs: Set(relationships.map(\.grocerySourceID)))
    }

    func clearCheckedItems(listID: UUID) async throws {
        let items: [GroceryItem] = try await client.from("grocery_items").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .eq("is_checked", value: true)
            .execute().value
        try await deleteItems(items, listID: listID)
    }

    func clearAllItems(listID: UUID) async throws {
        let items: [GroceryItem] = try await client.from("grocery_items").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .execute().value
        try await deleteItems(items, listID: listID)
    }

    private func deleteItems(_ items: [GroceryItem], listID: UUID) async throws {
        guard !items.isEmpty else { return }
        let itemIDs = items.map(\.id)
        let relationships = try await fetchItemSources(itemIDs: itemIDs)
        try await client.from("grocery_items").delete()
            .eq("grocery_list_id", value: listID.uuidString)
            .in("id", values: itemIDs.map(\.uuidString))
            .execute()
        try await cleanupInactiveSources(sourceIDs: Set(relationships.map(\.grocerySourceID)))
    }

    private func cleanupInactiveSources(sourceIDs: Set<UUID>) async throws {
        guard !sourceIDs.isEmpty else { return }
        let remaining: [GroceryItemSource] = try await client.from("grocery_item_sources").select()
            .in("grocery_source_id", values: sourceIDs.map(\.uuidString))
            .execute().value
        let activeSourceIDs = Set(remaining.map(\.grocerySourceID))
        let orphanedIDs = sourceIDs.subtracting(activeSourceIDs)
        guard !orphanedIDs.isEmpty else { return }
        try await client.from("grocery_sources")
            .update(UpdateSourceActivityPayload(isActive: false))
            .in("id", values: orphanedIDs.map(\.uuidString))
            .execute()
    }

    private func fetchDefaultList(homeID: UUID) async throws -> GroceryList? {
        let rows: [GroceryList] = try await client.from("grocery_lists").select()
            .eq("home_id", value: homeID.uuidString)
            .eq("is_default", value: true)
            .limit(1).execute().value
        return rows.first
    }

    private func fetchItem(listID: UUID, normalizedName: String) async throws -> GroceryItem? {
        let rows: [GroceryItem] = try await client.from("grocery_items").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .eq("normalized_name", value: normalizedName)
            .limit(1).execute().value
        return rows.first
    }

    private func fetchSource(listID: UUID, type: GrocerySourceType, referenceID: UUID) async throws -> GrocerySource? {
        let rows: [GrocerySource] = try await client.from("grocery_sources").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .eq("source_type", value: type.rawValue)
            .eq("source_ref_id", value: referenceID.uuidString)
            .eq("is_active", value: true)
            .limit(1).execute().value
        return rows.first
    }

    private func fetchAnySource(listID: UUID, type: GrocerySourceType, referenceID: UUID) async throws -> GrocerySource? {
        let rows: [GrocerySource] = try await client.from("grocery_sources").select()
            .eq("grocery_list_id", value: listID.uuidString)
            .eq("source_type", value: type.rawValue)
            .eq("source_ref_id", value: referenceID.uuidString)
            .limit(1).execute().value
        return rows.first
    }

    private func ingredientNames(mealID: UUID) async throws -> [String] {
        let recipeRows: [MealRecipeRow] = try await client.from("meal_recipes").select("id")
            .eq("meal_id", value: mealID.uuidString).execute().value
        guard !recipeRows.isEmpty else { return [] }
        let ingredientRows: [IngredientNameRow] = try await client.from("recipe_ingredients")
            .select("ingredient_name, quantity, unit, preparation, sort_order")
            .in("recipe_id", values: recipeRows.map { $0.id.uuidString })
            .order("sort_order").execute().value
        logRecipeIngredients(ingredientRows)
        return ingredientRows.map(\.ingredientName)
    }

    private func ingredientNamesByMealID(_ mealIDs: Set<UUID>) async throws -> [UUID: [String]] {
        guard !mealIDs.isEmpty else { return [:] }
        let recipeRows: [MealRecipeRow] = try await client.from("meal_recipes")
            .select("id, meal_id")
            .in("meal_id", values: mealIDs.map(\.uuidString))
            .execute().value
        guard !recipeRows.isEmpty else { return [:] }
        let ingredientRows: [IngredientNameRow] = try await client.from("recipe_ingredients")
            .select("recipe_id, ingredient_name, quantity, unit, preparation, sort_order")
            .in("recipe_id", values: recipeRows.map { $0.id.uuidString })
            .order("sort_order").execute().value
        logRecipeIngredients(ingredientRows)
        let mealIDByRecipeID = Dictionary(uniqueKeysWithValues: recipeRows.compactMap { row in
            row.mealID.map { (row.id, $0) }
        })
        var result: [UUID: [String]] = [:]
        for ingredient in ingredientRows {
            guard let recipeID = ingredient.recipeID, let mealID = mealIDByRecipeID[recipeID] else { continue }
            result[mealID, default: []].append(ingredient.ingredientName)
        }
        return result
    }

    private func logRecipeIngredients(_ ingredients: [IngredientNameRow]) {
        #if DEBUG
        for ingredient in ingredients {
            let displayName = GroceryNameNormalizer.recipeDisplayName(ingredient.ingredientName)
            print("[Groceries] recipe ingredient:")
            print("ingredient_name=\(ingredient.ingredientName)")
            print("quantity=\(ingredient.quantity.map(String.init(describing:)) ?? "nil")")
            print("unit=\(ingredient.unit ?? "nil")")
            print("preparation=\(ingredient.preparation ?? "nil")")
            print("[Groceries] grocery displayName=\(displayName)")
            print("[Groceries] normalizedName=\(GroceryNameNormalizer.normalize(ingredient.ingredientName))")
        }
        #endif
    }

    private static func dateOnlyString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func isUniqueViolation(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }
}

enum GroceryRepositoryError: LocalizedError {
    case emptyItemName
    var errorDescription: String? { "Enter a grocery item name." }
}

private struct CreateListPayload: Encodable {
    let homeID: UUID
    let name = "Groceries"
    let isDefault = true
    let createdBy: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "home_id", name, isDefault = "is_default", createdBy = "created_by"
    }
}

private struct CreateItemPayload: Encodable {
    let groceryListID, homeID: UUID
    let ingredientName, normalizedName: String
    let category: GroceryCategory
    let isChecked = false
    let createdBy: UUID
    enum CodingKeys: String, CodingKey {
        case groceryListID = "grocery_list_id", homeID = "home_id"
        case ingredientName = "ingredient_name", normalizedName = "normalized_name"
        case category, isChecked = "is_checked", createdBy = "created_by"
    }
}

private struct CreateSourcePayload: Encodable {
    let groceryListID, homeID: UUID
    let sourceType: GrocerySourceType
    let sourceRefID: UUID
    let sourceLabel: String
    let sourceDate: String?
    let isActive = true
    let createdBy: UUID
    enum CodingKeys: String, CodingKey {
        case groceryListID = "grocery_list_id", homeID = "home_id"
        case sourceType = "source_type", sourceRefID = "source_ref_id"
        case sourceLabel = "source_label", sourceDate = "source_date"
        case isActive = "is_active", createdBy = "created_by"
    }
}

private struct CreateItemSourcePayload: Encodable {
    let groceryItemID, grocerySourceID: UUID
    enum CodingKeys: String, CodingKey {
        case groceryItemID = "grocery_item_id", grocerySourceID = "grocery_source_id"
    }
}

private struct UpdateCheckedPayload: Encodable {
    let isChecked: Bool
    enum CodingKeys: String, CodingKey { case isChecked = "is_checked" }
}

private struct UpdateCategoryPayload: Encodable { let category: GroceryCategory }
private struct UpdateItemPayload: Encodable {
    let ingredientName: String
    let normalizedName: String
    let category: GroceryCategory
    enum CodingKeys: String, CodingKey {
        case ingredientName = "ingredient_name", normalizedName = "normalized_name", category
    }
}
private struct UpdateSourceActivityPayload: Encodable {
    let isActive: Bool
    enum CodingKeys: String, CodingKey { case isActive = "is_active" }
}
private struct MealRecipeRow: Decodable {
    let id: UUID
    let mealID: UUID?
    enum CodingKeys: String, CodingKey { case id, mealID = "meal_id" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mealID = try container.decodeIfPresent(UUID.self, forKey: .mealID)
    }
}
private struct IngredientNameRow: Decodable {
    let recipeID: UUID?
    let ingredientName: String
    let quantity: Double?
    let unit: String?
    let preparation: String?
    let sortOrder: Int
    enum CodingKeys: String, CodingKey {
        case recipeID = "recipe_id", ingredientName = "ingredient_name"
        case quantity, unit, preparation
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recipeID = try container.decodeIfPresent(UUID.self, forKey: .recipeID)
        ingredientName = try container.decode(String.self, forKey: .ingredientName)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        preparation = try container.decodeIfPresent(String.self, forKey: .preparation)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }
}
