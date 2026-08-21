import Foundation
import PostgREST
import Supabase

protocol GlobalMealsServicing: AnyObject {
    func fetchTrending(limit: Int) async throws -> [GlobalMeal]
    func fetchMeals(page: Int, pageSize: Int, filters: GlobalMealsFilters, selectedMealType: MealType?, searchText: String) async throws -> [GlobalMeal]
    func fetchGlobalMeal(globalMealId: UUID) async throws -> GlobalMeal
    func fetchDetail(globalMealId: UUID) async throws -> GlobalMealDetail
    func fetchExistingHomeMeal(homeId: UUID, globalMealId: UUID) async throws -> Meal?
    func fetchExistingHomeMeals(homeId: UUID) async throws -> [Meal]
    func addGlobalMealToHome(globalMeal: GlobalMeal, homeId: UUID) async throws -> GlobalMealAddResult
    func saveCommunityRecipe(draft: MealEditorDraft) async throws -> UUID
    func deleteCommunityRecipe(globalMealId: UUID) async throws
}

@MainActor
final class GlobalMealsService: GlobalMealsServicing {
    private let client: SupabaseClient
    private let mealService: MealServicing

    init(client: SupabaseClient? = nil, mealService: MealServicing? = nil) {
        self.client = client ?? SupabaseManager.shared.client
        self.mealService = mealService ?? MealService()
    }

    func fetchTrending(limit: Int = 10) async throws -> [GlobalMeal] {
        do {
            try await requireAuthenticatedSession()
            let meals: [GlobalMeal] = try await client
                .from("global_recipes")
                .select()
                .eq("status", value: "active")
                .order("save_count", ascending: false)
                .order("updated_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            #if DEBUG
            print("Global Explore load: trending")
            print("query_table: global_recipes")
            print("limit: \(limit)")
            print("rows_returned: \(meals.count)")
            print("decoded_recipe_ids: \(meals.map { $0.id.uuidString }.joined(separator: ", "))")
            #endif

            return meals
        } catch {
            logGlobalMealError(error, operation: "fetchTrending")
            throw MealServiceError.loadMealsFailed
        }
    }

    func fetchMeals(
        page: Int,
        pageSize: Int,
        filters: GlobalMealsFilters,
        selectedMealType: MealType?,
        searchText: String
    ) async throws -> [GlobalMeal] {
        do {
            try await requireAuthenticatedSession()
            let lowerBound = max(0, page) * pageSize
            let upperBound = lowerBound + pageSize - 1
            let meals: [GlobalMeal] = try await client
                .from("global_recipes")
                .select()
                .eq("status", value: "active")
                .order(filters.sort.orderColumn, ascending: filters.sort.isAscending)
                .range(from: lowerBound, to: upperBound)
                .execute()
                .value

            let filteredMeals = meals.filter { meal in
                meal.matchesExploreFilters(filters)
                    && meal.matchesSelectedMealType(selectedMealType)
                    && meal.matchesExploreSearch(searchText.normalizedGlobalMealSearch)
            }

            #if DEBUG
            print("Global Explore load: browse")
            print("query_table: global_recipes")
            print("query: \(searchText)")
            print("sort: \(filters.sort.title)")
            print("page: \(page)")
            print("range: \(lowerBound)-\(upperBound)")
            print("rows_returned: \(filteredMeals.count)")
            print("active_rows: \(meals.count)")
            print("decoded_recipe_ids: \(filteredMeals.map { $0.id.uuidString }.joined(separator: ", "))")
            #endif

            return filteredMeals
        } catch {
            logGlobalMealError(error, operation: "fetchMeals")
            throw MealServiceError.loadMealsFailed
        }
    }

    func fetchGlobalMeal(globalMealId: UUID) async throws -> GlobalMeal {
        do {
            try await requireAuthenticatedSession()
            let meal: GlobalMeal = try await client
                .from("global_recipes")
                .select()
                .eq("id", value: globalMealId.uuidString)
                .eq("status", value: "active")
                .single()
                .execute()
                .value

            #if DEBUG
            print("Global recipe fetched")
            print("query_table: global_recipes")
            print("global_recipe_id: \(globalMealId.uuidString)")
            print("image_url_present: \((meal.imageURL?.isEmpty == false))")
            #endif

            return meal
        } catch {
            logGlobalMealError(error, operation: "fetchGlobalMeal", globalMealId: globalMealId)
            throw MealServiceError.loadRecipeFailed
        }
    }

    func fetchDetail(globalMealId: UUID) async throws -> GlobalMealDetail {
        do {
            try await requireAuthenticatedSession()
            let meal: GlobalMeal = try await client
                .from("global_recipes")
                .select()
                .eq("id", value: globalMealId.uuidString)
                .eq("status", value: "active")
                .single()
                .execute()
                .value

            #if DEBUG
            print("Global recipe detail")
            print("query_table: global_recipes")
            print("global_recipe_id: \(globalMealId.uuidString)")
            print("ingredient_count: \(meal.ingredients.count)")
            print("step_count: \(meal.steps.count)")
            print("has_nutrition: \(meal.nutrition != nil)")
            print("image_url_present: \((meal.imageURL?.isEmpty == false))")
            #endif

            return GlobalMealDetail(
                meal: meal,
                recipe: meal,
                ingredients: meal.ingredients.sorted { $0.sortOrder < $1.sortOrder },
                steps: meal.steps.sorted { $0.sortOrder < $1.sortOrder }
            )
        } catch {
            logGlobalMealError(error, operation: "fetchDetail", globalMealId: globalMealId)
            throw MealServiceError.loadRecipeFailed
        }
    }

    func fetchExistingHomeMeal(homeId: UUID, globalMealId: UUID) async throws -> Meal? {
        do {
            try await requireAuthenticatedSession()
            let meals: [Meal] = try await client
                .from("meals")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("origin_global_recipe_id", value: globalMealId.uuidString)
                .limit(1)
                .execute()
                .value
            return meals.first
        } catch {
            logGlobalMealError(error, operation: "fetchExistingHomeMeal", homeId: homeId, globalMealId: globalMealId)
            throw MealServiceError.loadMealFailed
        }
    }

    func fetchExistingHomeMeals(homeId: UUID) async throws -> [Meal] {
        do {
            try await requireAuthenticatedSession()
            return try await client
                .from("meals")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .execute()
                .value
        } catch {
            logGlobalMealError(error, operation: "fetchExistingHomeMeals", homeId: homeId)
            throw MealServiceError.loadMealsFailed
        }
    }

    func addGlobalMealToHome(globalMeal: GlobalMeal, homeId: UUID) async throws -> GlobalMealAddResult {
        do {
            try await requireAuthenticatedSession()

            if let existingMeal = try await fetchExistingHomeMeal(homeId: homeId, globalMealId: globalMeal.id) {
                #if DEBUG
                print("Add to Home duplicate detected")
                print("duplicate_found: true")
                print("global_recipe_id: \(globalMeal.id.uuidString)")
                print("selected_home_id: \(homeId.uuidString)")
                print("returned_home_meal_id: \(existingMeal.id.uuidString)")
                #endif
                return .alreadyExists(homeMealId: existingMeal.id)
            }

            #if DEBUG
            print("Add to Home started")
            print("duplicate_found: false")
            print("selected_home_id: \(homeId.uuidString)")
            print("global_recipe_id: \(globalMeal.id.uuidString)")
            #endif

            let homeMealId: UUID = try await client
                .rpc(
                    "add_global_meal_to_home",
                    params: AddGlobalMealToHomeRPCParameters(
                        requestedGlobalMealId: globalMeal.id,
                        requestedHomeId: homeId
                    )
                )
                .execute()
                .value

            #if DEBUG
            print("Add to Home completed")
            print("returned_home_meal_id: \(homeMealId.uuidString)")
            print("origin_global_recipe_id: \(globalMeal.id.uuidString)")
            print("save_count_increment_result: handled_by_rpc_or_database")
            #endif

            guard let imageURL = globalMeal.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return .added(homeMealId: homeMealId)
            }

            do {
                #if DEBUG
                print("Global photo copy started")
                print("global_recipe_id: \(globalMeal.id.uuidString)")
                print("home_meal_id: \(homeMealId.uuidString)")
                #endif

                let imageData = try await downloadGlobalMealImage(urlString: imageURL)
                let uploadedPhoto = try await mealService.uploadMealPhoto(homeId: homeId, mealId: homeMealId, imageData: imageData, fileExtension: "jpg")
                _ = try await mealService.updateMeal(id: homeMealId, payload: UpdateMealPayload(primaryPhotoPath: uploadedPhoto.path))

                #if DEBUG
                print("Global photo copy completed")
                print("photo_copy_result: copied")
                print("home_photo_path: \(uploadedPhoto.path)")
                #endif

                return .added(homeMealId: homeMealId)
            } catch {
                logGlobalMealError(error, operation: "copyGlobalPhoto", homeId: homeId, globalMealId: globalMeal.id)
                #if DEBUG
                print("photo_copy_result: failed")
                #endif
                return .addedPhotoCopyFailed(homeMealId: homeMealId)
            }
        } catch let error as MealServiceError {
            throw error
        } catch {
            logGlobalMealError(error, operation: "addGlobalMealToHome", homeId: homeId, globalMealId: globalMeal.id)
            throw MealServiceError.saveMealFailed
        }
    }

    func saveCommunityRecipe(draft: MealEditorDraft) async throws -> UUID {
        let parameters: SaveGlobalRecipeParameters
        do {
            try await requireAuthenticatedSession()
            parameters = try saveGlobalRecipeParameters(from: draft)
        } catch {
            logGlobalMealError(
                error,
                operation: "saveCommunityRecipe_prepare",
                tableOrRPC: "rpc: save_global_recipe"
            )
            throw MealServiceError.saveMealFailed
        }

        logCommunityRecipeRPCStart(parameters)

        let response: PostgrestResponse<Void>
        do {
            response = try await client
                .rpc("save_global_recipe", params: parameters)
                .execute()

            #if DEBUG
            print("========== COMMUNITY RECIPE RPC EXECUTED ==========")
            print("rpc: save_global_recipe")
            print("http_status: \(response.status)")
            print("response_body: \(response.string() ?? "")")
            print("===================================================")
            #endif
        } catch {
            logCommunityRecipeRPCFailed(
                error,
                parameters: parameters
            )
            throw MealServiceError.saveMealFailed
        }

        do {
            let globalRecipeId = try decodeGlobalRecipeID(from: response.data)
            logCommunityRecipeRPCSucceeded(globalRecipeId: globalRecipeId)
            return globalRecipeId
        } catch {
            logCommunityRecipeRPCDecodeFailed(error, responseData: response.data)
            throw MealServiceError.saveMealFailed
        }
    }

    func deleteCommunityRecipe(globalMealId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()

            #if DEBUG
            print("========== COMMUNITY RECIPE DELETE START ==========")
            print("table: global_recipes")
            print("global_recipe_id: \(globalMealId.uuidString)")
            print("home_recipe_delete: false")
            print("===================================================")
            #endif

            let deletedRows: [DeletedGlobalRecipeRow] = try await client
                .from("global_recipes")
                .delete()
                .eq("id", value: globalMealId.uuidString)
                .select("id")
                .execute()
                .value

            guard deletedRows.contains(where: { $0.id == globalMealId }) else {
                #if DEBUG
                print("========== COMMUNITY RECIPE DELETE DENIED ==========")
                print("table: global_recipes")
                print("global_recipe_id: \(globalMealId.uuidString)")
                print("deleted_row_count: \(deletedRows.count)")
                print("reason: RLS or ownership check deleted no rows")
                print("====================================================")
                #endif
                throw MealServiceError.permissionDenied
            }

            #if DEBUG
            print("========== COMMUNITY RECIPE DELETE SUCCEEDED ==========")
            print("table: global_recipes")
            print("global_recipe_id: \(globalMealId.uuidString)")
            print("deleted_row_count: \(deletedRows.count)")
            print("home_recipe_deleted: false")
            print("=======================================================")
            #endif
        } catch let error as MealServiceError {
            throw error
        } catch {
            logGlobalMealError(error, operation: "deleteCommunityRecipe", globalMealId: globalMealId, tableOrRPC: "table: global_recipes")
            throw MealServiceError.deleteMealFailed
        }
    }

    private func downloadGlobalMealImage(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw MealServiceError.invalidPhotoData
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              !data.isEmpty,
              data.count <= 12 * 1024 * 1024 else {
            throw MealServiceError.invalidPhotoData
        }
        return data
    }

    private func requireAuthenticatedSession() async throws {
        _ = try await client.auth.session
    }

    private func saveGlobalRecipeParameters(from draft: MealEditorDraft) throws -> SaveGlobalRecipeParameters {
        let title = try normalizedRequiredString(draft.name, error: .emptyMealName)
        let ingredients = try globalRecipeIngredients(from: draft.ingredients)
        let steps = try globalRecipeSteps(from: draft.steps)

        return SaveGlobalRecipeParameters(
            requestedTitle: title,
            requestedDescription: normalizedOptionalString(draft.description),
            requestedImageURL: draft.importedImageURL?.absoluteString,
            requestedPrepTimeMinutes: draft.prepTimeMinutes,
            requestedCookTimeMinutes: draft.cookTimeMinutes,
            requestedTotalTimeMinutes: totalTime(prep: draft.prepTimeMinutes, cook: draft.cookTimeMinutes),
            requestedServings: normalizedServings(draft.servings),
            requestedCuisine: normalizedOptionalString(draft.cuisine),
            requestedMealTypes: draft.mealTypes.map(\.rawValue),
            requestedKeywords: normalizedTags(draft.tags),
            requestedIngredients: ingredients,
            requestedSteps: steps,
            requestedSourceType: draft.importedMetadata == nil ? "manual" : "url",
            requestedSourceName: normalizedOptionalString(draft.sourceName),
            requestedSourceURL: normalizedOptionalString(draft.sourceURL)
        )
    }

    private func globalRecipeIngredients(from ingredients: [MealEditorIngredient]) throws -> [SaveGlobalRecipeIngredient] {
        try ingredients.enumerated().compactMap { index, ingredient in
            let name = trimmed(ingredient.name)
            let quantity = trimmed(ingredient.quantityText)
            let hasContent = !name.isEmpty
                || !quantity.isEmpty
                || !trimmed(ingredient.unit).isEmpty
                || !trimmed(ingredient.preparation).isEmpty
                || !trimmed(ingredient.notes).isEmpty
            guard hasContent else { return nil }
            guard !name.isEmpty else { throw MealServiceError.emptyIngredientName }

            let combinedQuantity = [quantity, trimmed(ingredient.unit)].filter { !$0.isEmpty }.joined(separator: " ")
            let preparation = trimmed(ingredient.preparation)
            let notes = trimmed(ingredient.notes)
            let combinedNotes = [preparation, notes].filter { !$0.isEmpty }.joined(separator: "; ")

            return SaveGlobalRecipeIngredient(
                quantity: nilIfTrimmedEmpty(combinedQuantity),
                sortOrder: index,
                isOptional: ingredient.isOptional,
                sectionName: nilIfTrimmedEmpty(ingredient.sectionName),
                ingredientName: combinedNotes.isEmpty ? name : "\(name), \(combinedNotes)"
            )
        }
    }

    private func globalRecipeSteps(from steps: [MealEditorStep]) throws -> [SaveGlobalRecipeStep] {
        try steps.enumerated().compactMap { index, step in
            let instruction = trimmed(step.instruction)
            guard !instruction.isEmpty || !trimmed(step.timerMinutesText).isEmpty else { return nil }
            guard !instruction.isEmpty else { throw MealServiceError.emptyRecipeStep }
            return SaveGlobalRecipeStep(
                stepText: instruction,
                sortOrder: index,
                sectionName: nil
            )
        }
    }

    private func normalizedRequiredString(_ value: String, error: MealServiceError) throws -> String {
        let trimmedValue = trimmed(value)
        guard !trimmedValue.isEmpty else { throw error }
        return trimmedValue
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        nilIfTrimmedEmpty(value)
    }

    private func normalizedServings(_ servings: Decimal?) -> String? {
        servings.map { NSDecimalNumber(decimal: $0).stringValue }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { trimmed($0) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func totalTime(prep: Int?, cook: Int?) -> Int? {
        let total = (prep ?? 0) + (cook ?? 0)
        return total > 0 ? total : nil
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nilIfTrimmedEmpty(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func decodeGlobalRecipeID(from data: Data) throws -> UUID {
        if let uuid = try? JSONDecoder().decode(UUID.self, from: data) {
            return uuid
        }

        let responseText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
            ?? ""
        guard let uuid = UUID(uuidString: responseText) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Expected save_global_recipe to return a UUID scalar."
                )
            )
        }
        return uuid
    }

    private func logGlobalMealError(
        _ error: Error,
        operation: String,
        homeId: UUID? = nil,
        globalMealId: UUID? = nil,
        tableOrRPC: String? = nil,
        saveGlobalRecipeParameters: SaveGlobalRecipeParameters? = nil
    ) {
        #if DEBUG
        if operation == "saveCommunityRecipe" {
            print("========== COMMUNITY RECIPE SAVE FAILED ==========")
        } else {
            print("========== GLOBAL MEALS ERROR ==========")
        }
        print("operation: \(operation)")
        if let tableOrRPC { print("table/rpc: \(tableOrRPC)") }
        if let homeId { print("home_id: \(homeId.uuidString)") }
        if let globalMealId { print("global_recipe_id: \(globalMealId.uuidString)") }
        if let saveGlobalRecipeParameters {
            logSaveGlobalRecipeParameters(saveGlobalRecipeParameters)
        }
        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        print("underlying_error_type: \(String(reflecting: type(of: error)))")
        print(String(reflecting: error))
        print("========================================")
        #endif
    }

    private func logSaveGlobalRecipeParameters(_ parameters: SaveGlobalRecipeParameters) {
        #if DEBUG
        print("requested_title: \(parameters.requestedTitle)")
        print("requested_description_present: \((parameters.requestedDescription?.isEmpty == false))")
        print("requested_image_url_present: \((parameters.requestedImageURL?.isEmpty == false))")
        print("requested_prep_time_minutes: \(parameters.requestedPrepTimeMinutes.map(String.init) ?? "nil")")
        print("requested_cook_time_minutes: \(parameters.requestedCookTimeMinutes.map(String.init) ?? "nil")")
        print("requested_total_time_minutes: \(parameters.requestedTotalTimeMinutes.map(String.init) ?? "nil")")
        print("requested_servings: \(parameters.requestedServings ?? "nil")")
        print("requested_cuisine: \(parameters.requestedCuisine ?? "nil")")
        print("requested_meal_types: \(parameters.requestedMealTypes)")
        print("requested_keywords: \(parameters.requestedKeywords)")
        print("requested_ingredient_count: \(parameters.requestedIngredients.count)")
        print("requested_step_count: \(parameters.requestedSteps.count)")
        print("requested_source_type: \(parameters.requestedSourceType)")
        print("requested_source_name_present: \((parameters.requestedSourceName?.isEmpty == false))")
        print("requested_source_url_present: \((parameters.requestedSourceURL?.isEmpty == false))")
        #endif
    }

    private func logCommunityRecipeRPCStart(_ parameters: SaveGlobalRecipeParameters) {
        #if DEBUG
        print("========== COMMUNITY RECIPE RPC START ==========")
        print("rpc: save_global_recipe")
        print("title: \(parameters.requestedTitle)")
        print("source_type: \(parameters.requestedSourceType)")
        print("source_url_present: \((parameters.requestedSourceURL?.isEmpty == false))")
        print("meal_types: \(parameters.requestedMealTypes)")
        print("ingredients_count: \(parameters.requestedIngredients.count)")
        print("steps_count: \(parameters.requestedSteps.count)")
        print("keywords_count: \(parameters.requestedKeywords.count)")
        print("===============================================")
        #endif
    }

    private func logCommunityRecipeRPCFailed(_ error: Error, parameters: SaveGlobalRecipeParameters) {
        #if DEBUG
        print("========== COMMUNITY RECIPE RPC FAILED ==========")
        print("rpc: save_global_recipe")
        print("error_type: \(String(reflecting: type(of: error)))")
        logSaveGlobalRecipeParameters(parameters)
        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        print("underlying error: \(String(reflecting: error))")
        print("================================================")
        #endif
    }

    private func logCommunityRecipeRPCDecodeFailed(_ error: Error, responseData: Data) {
        #if DEBUG
        print("========== COMMUNITY RECIPE RPC DECODE FAILED ==========")
        print("rpc: save_global_recipe")
        print("expected_type: UUID")
        print("error_type: \(String(reflecting: type(of: error)))")
        print("error: \(String(reflecting: error))")
        print("response_body: \(String(data: responseData, encoding: .utf8) ?? "<non-UTF8 response body>")")
        print("========================================================")
        #endif
    }

    private func logCommunityRecipeRPCSucceeded(globalRecipeId: UUID) {
        #if DEBUG
        print("========== COMMUNITY RECIPE RPC SUCCEEDED ==========")
        print("rpc: save_global_recipe")
        print("global_recipe_id: \(globalRecipeId.uuidString)")
        print("home_recipe_created: false")
        print("====================================================")
        #endif
    }
}

private struct AddGlobalMealToHomeRPCParameters: Encodable {
    let requestedGlobalMealId: UUID
    let requestedHomeId: UUID

    enum CodingKeys: String, CodingKey {
        case requestedGlobalMealId = "requested_global_meal_id"
        case requestedHomeId = "requested_home_id"
    }
}

private struct DeletedGlobalRecipeRow: Decodable {
    let id: UUID
}

private extension String {
    var normalizedGlobalMealSearch: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Meal {
    var globalOriginIdForExplore: UUID? {
        originGlobalRecipeId
    }
}
