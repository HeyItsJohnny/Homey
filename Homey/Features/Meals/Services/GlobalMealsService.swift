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

    private func logGlobalMealError(_ error: Error, operation: String, homeId: UUID? = nil, globalMealId: UUID? = nil) {
        #if DEBUG
        print("========== GLOBAL MEALS ERROR ==========")
        print("operation: \(operation)")
        if let homeId { print("home_id: \(homeId.uuidString)") }
        if let globalMealId { print("global_recipe_id: \(globalMealId.uuidString)") }
        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        print(String(reflecting: error))
        print("========================================")
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
