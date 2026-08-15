import Combine
import Foundation
import PostgREST
import Supabase

protocol MealServicing: AnyObject {
    func fetchMeals(homeId: UUID) async throws -> [Meal]
    func fetchMeal(id: UUID) async throws -> Meal
    func createMeal(homeId: UUID, payload: CreateMealPayload) async throws -> Meal
    func updateMeal(id: UUID, payload: UpdateMealPayload) async throws -> Meal
    func archiveMeal(id: UUID) async throws
    func deleteMeal(id: UUID) async throws
    func searchMeals(homeId: UUID, query: String) async throws -> [Meal]
    func fetchMeals(homeId: UUID, mealType: MealType) async throws -> [Meal]
    func fetchFavoriteMeals(homeId: UUID) async throws -> [Meal]
    func fetchHouseholdFavorites(homeId: UUID, memberUserIds: Set<UUID>) async throws -> [HouseholdMealFavorite]
    func setFavorite(mealId: UUID, isFavorite: Bool) async throws
    func isFavorite(mealId: UUID) async throws -> Bool
    func fetchCollections(homeId: UUID) async throws -> [MealCollection]
    func createCollection(homeId: UUID, name: String, description: String?, iconName: String?) async throws -> MealCollection
    func updateCollection(id: UUID, name: String?, description: String?, iconName: String?) async throws -> MealCollection
    func deleteCollection(id: UUID) async throws
    func addMeal(mealId: UUID, toCollectionId collectionId: UUID) async throws
    func removeMeal(mealId: UUID, fromCollectionId collectionId: UUID) async throws
    func fetchMeals(collectionId: UUID) async throws -> [Meal]
    func fetchRecipe(mealId: UUID) async throws -> MealRecipeDetails
    func saveRecipe(mealId: UUID, recipe: MealRecipeDraft, ingredients: [RecipeIngredientDraft], steps: [RecipeStepDraft]) async throws -> MealRecipeDetails
    func saveMealRecipe(homeId: UUID, mealId: UUID?, draft: MealEditorDraft, isDraft: Bool) async throws -> UUID
    func fetchImportedMeal(homeId: UUID, globalRecipeId: UUID) async throws -> Meal?
    func saveImportedRecipe(homeId: UUID, draft: ImportedRecipeDraft) async throws -> ImportedRecipeSaveResult
    func applyImportedRecipeMetadata(homeId: UUID, mealId: UUID, metadata: ImportedMealMetadata) async throws
    func deleteRecipe(mealId: UUID) async throws
    func uploadMealPhoto(homeId: UUID, mealId: UUID, imageData: Data, fileExtension: String) async throws -> MealPhoto
    func deleteMealPhoto(photo: MealPhoto) async throws
    func createSignedMealPhotoURL(path: String) async throws -> URL
    func subscribeToMealChanges(homeId: UUID, onChange: @escaping @MainActor () -> Void) async throws -> MealRealtimeSubscription
}

@MainActor
final class MealService: ObservableObject, MealServicing {
    private let client = SupabaseManager.shared.client
    private let imageBucket = "meal-images"

    func fetchMeals(homeId: UUID) async throws -> [Meal] {
        do {
            try await requireAuthenticatedSession()
            let meals: [Meal] = try await client
                .from("meals")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("is_archived", value: false)
                .order("name", ascending: true)
                .execute()
                .value
            return meals.sortedForMeals()
        } catch {
            logMealError(error, operation: "fetchMeals", homeId: homeId)
            throw MealServiceError.loadMealsFailed
        }
    }

    func fetchMeal(id: UUID) async throws -> Meal {
        do {
            try await requireAuthenticatedSession()
            return try await client
                .from("meals")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
        } catch {
            logMealError(error, operation: "fetchMeal", mealId: id)
            throw MealServiceError.loadMealFailed
        }
    }

    func createMeal(homeId: UUID, payload: CreateMealPayload) async throws -> Meal {
        do {
            let userId = try await authenticatedUserId()
            let normalizedPayload = try normalizedCreateMealPayload(payload, homeId: homeId, userId: userId)
            return try await client
                .from("meals")
                .insert(normalizedPayload)
                .select()
                .single()
                .execute()
                .value
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "createMeal", homeId: homeId)
            throw MealServiceError.saveMealFailed
        }
    }

    func updateMeal(id: UUID, payload: UpdateMealPayload) async throws -> Meal {
        do {
            let userId = try await authenticatedUserId()
            let normalizedPayload = try normalizedUpdateMealPayload(payload, userId: userId)
            return try await client
                .from("meals")
                .update(normalizedPayload)
                .eq("id", value: id.uuidString)
                .select()
                .single()
                .execute()
                .value
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "updateMeal", mealId: id)
            throw MealServiceError.saveMealFailed
        }
    }

    func archiveMeal(id: UUID) async throws {
        do {
            let userId = try await authenticatedUserId()
            try await client
                .from("meals")
                .update(UpdateMealPayload(isArchived: true, updatedBy: userId))
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            logMealError(error, operation: "archiveMeal", mealId: id)
            throw MealServiceError.archiveMealFailed
        }
    }

    func deleteMeal(id: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("meals")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            logMealError(error, operation: "deleteMeal", mealId: id)
            throw MealServiceError.deleteMealFailed
        }
    }

    func searchMeals(homeId: UUID, query: String) async throws -> [Meal] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await fetchMeals(homeId: homeId)
        }

        let meals = try await fetchMeals(homeId: homeId)
        return meals.filter { $0.matchesSearch(trimmedQuery) }
    }

    func fetchMeals(homeId: UUID, mealType: MealType) async throws -> [Meal] {
        let meals = try await fetchMeals(homeId: homeId)
        return meals.filter { $0.mealTypes.contains(mealType) }
    }

    func fetchFavoriteMeals(homeId: UUID) async throws -> [Meal] {
        do {
            let userId = try await authenticatedUserId()
            let favorites: [MealFavorite] = try await client
                .from("meal_favorites")
                .select("meal_id, user_id, created_at")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            let favoriteIds = Set(favorites.map(\.mealId))
            guard !favoriteIds.isEmpty else {
                return []
            }
            return try await fetchMeals(homeId: homeId).filter { favoriteIds.contains($0.id) }
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "fetchFavoriteMeals", homeId: homeId)
            throw MealServiceError.loadFavoritesFailed
        }
    }

    func fetchHouseholdFavorites(homeId: UUID, memberUserIds: Set<UUID>) async throws -> [HouseholdMealFavorite] {
        do {
            try await requireAuthenticatedSession()
            guard !memberUserIds.isEmpty else { return [] }

            let meals = try await fetchMeals(homeId: homeId)
            let homeMealIds = Set(meals.map(\.id))
            guard !homeMealIds.isEmpty else { return [] }

            let favorites: [HouseholdMealFavorite] = try await client
                .from("meal_favorites")
                .select("meal_id, user_id, created_at")
                .execute()
                .value

            let scopedFavorites = favorites.filter { favorite in
                homeMealIds.contains(favorite.mealId) && memberUserIds.contains(favorite.userId)
            }

            #if DEBUG
            print("Auto Plan household favorites loaded")
            print("selected_home_id: \(homeId.uuidString)")
            print("member_count: \(memberUserIds.count)")
            print("household_favorite_row_count: \(scopedFavorites.count)")
            #endif

            return scopedFavorites
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "fetchHouseholdFavorites", homeId: homeId)
            throw MealServiceError.loadFavoritesFailed
        }
    }

    func setFavorite(mealId: UUID, isFavorite: Bool) async throws {
        do {
            let userId = try await authenticatedUserId()

            if isFavorite {
                try await client
                    .from("meal_favorites")
                    .upsert(CreateMealFavoritePayload(mealId: mealId, userId: userId))
                    .execute()
            } else {
                try await client
                    .from("meal_favorites")
                    .delete()
                    .eq("meal_id", value: mealId.uuidString)
                    .eq("user_id", value: userId.uuidString)
                    .execute()
            }
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "setFavorite", mealId: mealId)
            throw MealServiceError.updateFavoriteFailed
        }
    }

    func isFavorite(mealId: UUID) async throws -> Bool {
        do {
            let userId = try await authenticatedUserId()
            let favorites: [MealFavorite] = try await client
                .from("meal_favorites")
                .select()
                .eq("meal_id", value: mealId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            return !favorites.isEmpty
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "isFavorite", mealId: mealId)
            throw MealServiceError.loadFavoritesFailed
        }
    }

    func fetchCollections(homeId: UUID) async throws -> [MealCollection] {
        do {
            try await requireAuthenticatedSession()
            let collections: [MealCollection] = try await client
                .from("meal_collections")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            return collections.sortedForMeals()
        } catch {
            logMealError(error, operation: "fetchCollections", homeId: homeId)
            throw MealServiceError.loadCollectionsFailed
        }
    }

    func createCollection(homeId: UUID, name: String, description: String?, iconName: String?) async throws -> MealCollection {
        do {
            let userId = try await authenticatedUserId()
            let payload = try normalizedCreateCollectionPayload(
                homeId: homeId,
                name: name,
                description: description,
                iconName: iconName,
                userId: userId
            )
            return try await client
                .from("meal_collections")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "createCollection", homeId: homeId)
            throw MealServiceError.saveCollectionFailed
        }
    }

    func updateCollection(id: UUID, name: String?, description: String?, iconName: String?) async throws -> MealCollection {
        do {
            let userId = try await authenticatedUserId()
            let payload = try normalizedUpdateCollectionPayload(name: name, description: description, iconName: iconName, userId: userId)
            return try await client
                .from("meal_collections")
                .update(payload)
                .eq("id", value: id.uuidString)
                .select()
                .single()
                .execute()
                .value
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "updateCollection", collectionId: id)
            throw MealServiceError.saveCollectionFailed
        }
    }

    func deleteCollection(id: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("meal_collections")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            logMealError(error, operation: "deleteCollection", collectionId: id)
            throw MealServiceError.deleteCollectionFailed
        }
    }

    func addMeal(mealId: UUID, toCollectionId collectionId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("meal_collection_items")
                .upsert(CreateMealCollectionItemPayload(collectionId: collectionId, mealId: mealId))
                .execute()
        } catch {
            logMealError(error, operation: "addMealToCollection", mealId: mealId, collectionId: collectionId)
            throw MealServiceError.updateCollectionItemsFailed
        }
    }

    func removeMeal(mealId: UUID, fromCollectionId collectionId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("meal_collection_items")
                .delete()
                .eq("collection_id", value: collectionId.uuidString)
                .eq("meal_id", value: mealId.uuidString)
                .execute()
        } catch {
            logMealError(error, operation: "removeMealFromCollection", mealId: mealId, collectionId: collectionId)
            throw MealServiceError.updateCollectionItemsFailed
        }
    }

    func fetchMeals(collectionId: UUID) async throws -> [Meal] {
        do {
            try await requireAuthenticatedSession()
            let items: [MealCollectionItem] = try await client
                .from("meal_collection_items")
                .select()
                .eq("collection_id", value: collectionId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value

            var meals: [Meal] = []
            for item in items {
                let meal = try await fetchMeal(id: item.mealId)
                if !meal.isArchived {
                    meals.append(meal)
                }
            }
            return meals.sortedForMeals()
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "fetchMealsForCollection", collectionId: collectionId)
            throw MealServiceError.loadMealsFailed
        }
    }

    func fetchRecipe(mealId: UUID) async throws -> MealRecipeDetails {
        do {
            try await requireAuthenticatedSession()
            logMealLoadStage("fetch meal_recipes row", mealId: mealId)
            let recipes: [MealRecipe] = try await client
                .from("meal_recipes")
                .select()
                .eq("meal_id", value: mealId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value

            guard let recipe = recipes.first else {
                logMealLoadStage("meal_recipes row missing; continuing with empty recipe", mealId: mealId)
                return MealRecipeDetails(recipe: nil, ingredients: [], steps: [])
            }

            if recipes.count > 1 {
                logMealLoadStage("duplicate meal_recipes rows detected: \(recipes.count)", mealId: mealId, recipeId: recipe.id)
            }

            let loadedIngredients: [RecipeIngredient]
            do {
                logMealLoadStage("fetch recipe ingredients", mealId: mealId, recipeId: recipe.id)
                loadedIngredients = try await client
                    .from("recipe_ingredients")
                    .select()
                    .eq("recipe_id", value: recipe.id.uuidString)
                    .order("sort_order", ascending: true)
                    .execute()
                    .value
            } catch {
                logMealError(error, operation: "fetchRecipeIngredients", mealId: mealId, recipeId: recipe.id)
                throw MealServiceError.ingredientLoadFailed
            }

            let loadedSteps: [RecipeStep]
            do {
                logMealLoadStage("fetch recipe steps", mealId: mealId, recipeId: recipe.id)
                loadedSteps = try await client
                    .from("recipe_steps")
                    .select()
                    .eq("recipe_id", value: recipe.id.uuidString)
                    .order("step_number", ascending: true)
                    .execute()
                    .value
            } catch {
                logMealError(error, operation: "fetchRecipeSteps", mealId: mealId, recipeId: recipe.id)
                throw MealServiceError.stepLoadFailed
            }

            let details = MealRecipeDetails(
                recipe: recipe,
                ingredients: loadedIngredients.sortedForRecipeIngredients(),
                steps: loadedSteps.sortedForRecipeSteps()
            )
            logMealLoadStage("map database models into MealEditorDraft", mealId: mealId, recipeId: recipe.id)
            return details
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "fetchRecipe", mealId: mealId)
            throw MealServiceError.loadRecipeFailed
        }
    }

    func saveRecipe(mealId: UUID, recipe: MealRecipeDraft, ingredients: [RecipeIngredientDraft], steps: [RecipeStepDraft]) async throws -> MealRecipeDetails {
        do {
            try await requireAuthenticatedSession()
            try validateRecipeDraft(recipe, ingredients: ingredients, steps: steps)
            try await deleteRecipe(mealId: mealId)

            let recipePayload = CreateMealRecipePayload(
                mealId: mealId,
                instructionsNotes: normalizedOptionalString(recipe.notes),
                yieldText: recipe.servings.map(String.init(describing:))
            )
            let savedRecipe: MealRecipe = try await client
                .from("meal_recipes")
                .insert(recipePayload)
                .select()
                .single()
                .execute()
                .value

            let ingredientPayloads = ingredients.map {
                CreateRecipeIngredientPayload(
                    recipeId: savedRecipe.id,
                    sectionName: nil,
                    ingredientName: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: $0.quantity,
                    unit: normalizedOptionalString($0.unit),
                    preparation: nil,
                    notes: normalizedOptionalString($0.notes),
                    sortOrder: $0.sortOrder,
                    isOptional: $0.isOptional
                )
            }
            let stepPayloads = steps.map {
                CreateRecipeStepPayload(
                    recipeId: savedRecipe.id,
                    instruction: $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                    stepNumber: $0.sortOrder,
                    timerMinutes: $0.durationMinutes,
                    photoPath: nil
                )
            }

            let savedIngredients: [RecipeIngredient]
            if ingredientPayloads.isEmpty {
                savedIngredients = []
            } else {
                savedIngredients = try await client
                    .from("recipe_ingredients")
                    .insert(ingredientPayloads)
                    .select()
                    .execute()
                    .value
            }

            let savedSteps: [RecipeStep]
            if stepPayloads.isEmpty {
                savedSteps = []
            } else {
                savedSteps = try await client
                    .from("recipe_steps")
                    .insert(stepPayloads)
                    .select()
                    .execute()
                    .value
            }

            return MealRecipeDetails(
                recipe: savedRecipe,
                ingredients: savedIngredients.sortedForRecipeIngredients(),
                steps: savedSteps.sortedForRecipeSteps()
            )
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "saveRecipe", mealId: mealId)
            throw MealServiceError.saveRecipeFailed
        }
    }

    func saveMealRecipe(homeId: UUID, mealId: UUID?, draft: MealEditorDraft, isDraft: Bool) async throws -> UUID {
        var parameters: SaveMealRecipeParameters?
        do {
            try await requireAuthenticatedSession()
            parameters = try saveMealRecipeParameters(homeId: homeId, mealId: mealId, draft: draft, isDraft: isDraft)

            #if DEBUG
            print("Calling RPC save_meal_recipe")
            print("requested_home_id: \(homeId.uuidString)")
            if let mealId {
                print("requested_meal_id: \(mealId.uuidString)")
            } else {
                print("requested_meal_id: null")
            }
            print("requested_is_draft: \(isDraft)")
            if let parameters {
                print("request_payload: \(debugPayloadDescription(parameters))")
            }
            #endif

            guard let parameters else {
                throw MealServiceError.saveMealFailed
            }

            return try await client
                .rpc("save_meal_recipe", params: parameters)
                .execute()
                .value
        } catch let error as MealServiceError {
            logMealError(
                error,
                operation: "save_meal_recipe_preflight",
                rpcName: "save_meal_recipe",
                homeId: homeId,
                mealId: mealId,
                isDraft: isDraft
            )
            throw error
        } catch {
            logMealError(
                error,
                operation: "save_meal_recipe",
                rpcName: "save_meal_recipe",
                homeId: homeId,
                mealId: mealId,
                isDraft: isDraft,
                payloadDescription: parameters.map { debugPayloadDescription($0) }
            )
            throw MealServiceError.saveMealFailed
        }
    }

    func fetchImportedMeal(homeId: UUID, globalRecipeId: UUID) async throws -> Meal? {
        do {
            try await requireAuthenticatedSession()
            let meals: [Meal] = try await client
                .from("meals")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("global_recipe_id", value: globalRecipeId.uuidString)
                .eq("is_archived", value: false)
                .limit(1)
                .execute()
                .value
            return meals.first
        } catch {
            logMealError(error, operation: "fetchImportedMeal", homeId: homeId)
            throw MealServiceError.loadMealFailed
        }
    }

    func saveImportedRecipe(homeId: UUID, draft: ImportedRecipeDraft) async throws -> ImportedRecipeSaveResult {
        do {
            if let existingMeal = try await fetchImportedMeal(homeId: homeId, globalRecipeId: draft.globalRecipeId) {
                return .alreadyExists(existingMeal)
            }

            let mealDraft = try draft.makeMealEditorDraft()
            let mealId = try await saveMealRecipe(homeId: homeId, mealId: nil, draft: mealDraft, isDraft: false)
            let userId = try await authenticatedUserId()
            let metadataPayload = UpdateMealPayload(
                sourceName: draft.sourceDisplayName,
                sourceURL: draft.originalUrl,
                sourceType: "url",
                globalRecipeId: draft.globalRecipeId,
                importedAt: Date(),
                updatedBy: userId
            )

            do {
                try await client
                    .from("meals")
                    .update(metadataPayload)
                    .eq("id", value: mealId.uuidString)
                    .execute()
            } catch {
                if let existingMeal = try? await fetchImportedMeal(homeId: homeId, globalRecipeId: draft.globalRecipeId) {
                    return .alreadyExists(existingMeal)
                }
                throw error
            }

            try await markRecipeImportSaved(importId: draft.importId, globalRecipeId: draft.globalRecipeId)
            return .saved(mealId)
        } catch let error as MealServiceError {
            logMealError(error, operation: "saveImportedRecipe", homeId: homeId)
            throw error
        } catch {
            logMealError(error, operation: "saveImportedRecipe", homeId: homeId)
            throw MealServiceError.saveMealFailed
        }
    }

    func applyImportedRecipeMetadata(homeId: UUID, mealId: UUID, metadata: ImportedMealMetadata) async throws {
        do {
            if let existingMeal = try await fetchImportedMeal(homeId: homeId, globalRecipeId: metadata.globalRecipeId),
               existingMeal.id != mealId {
                throw MealServiceError.duplicateImportedRecipe
            }

            let userId = try await authenticatedUserId()
            let metadataPayload = UpdateMealPayload(
                sourceName: metadata.sourceDisplayName,
                sourceURL: metadata.originalURL,
                sourceType: "url",
                globalRecipeId: metadata.globalRecipeId,
                importedAt: Date(),
                updatedBy: userId
            )

            try await client
                .from("meals")
                .update(metadataPayload)
                .eq("id", value: mealId.uuidString)
                .execute()

            try await markRecipeImportSaved(importId: metadata.importId, globalRecipeId: metadata.globalRecipeId)
        } catch let error as MealServiceError {
            logMealError(error, operation: "applyImportedRecipeMetadata", homeId: homeId, mealId: mealId)
            throw error
        } catch {
            logMealError(error, operation: "applyImportedRecipeMetadata", homeId: homeId, mealId: mealId)
            throw MealServiceError.saveMealFailed
        }
    }

    func deleteRecipe(mealId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            let recipes: [MealRecipe] = try await client
                .from("meal_recipes")
                .select()
                .eq("meal_id", value: mealId.uuidString)
                .execute()
                .value

            for recipe in recipes {
                try await client
                    .from("recipe_ingredients")
                    .delete()
                    .eq("recipe_id", value: recipe.id.uuidString)
                    .execute()
                try await client
                    .from("recipe_steps")
                    .delete()
                    .eq("recipe_id", value: recipe.id.uuidString)
                    .execute()
            }

            try await client
                .from("meal_recipes")
                .delete()
                .eq("meal_id", value: mealId.uuidString)
                .execute()
        } catch {
            logMealError(error, operation: "deleteRecipe", mealId: mealId)
            throw MealServiceError.deleteRecipeFailed
        }
    }

    func uploadMealPhoto(homeId: UUID, mealId: UUID, imageData: Data, fileExtension: String) async throws -> MealPhoto {
        var objectPath: String?
        let contentType = "image/jpeg"
        let normalizedExtension = normalizedFileExtension(fileExtension)
        do {
            let userId = try await authenticatedUserId()
            guard !imageData.isEmpty else {
                throw MealServiceError.invalidPhotoData
            }
            let photoId = UUID()
            objectPath = mealPhotoPath(
                homeId: homeId,
                mealId: mealId,
                photoId: photoId,
                fileExtension: normalizedExtension
            )

            #if DEBUG
            print("Meal photo upload started")
            print("bucket: \(imageBucket)")
            print("home_id: \(homeId.uuidString)")
            print("persisted_meal_id: \(mealId.uuidString)")
            print("path: \(objectPath ?? "")")
            print("file_extension: \(normalizedExtension)")
            print("mime_type: \(contentType)")
            print("compressed_bytes: \(imageData.count)")
            #endif

            try await client.storage
                .from(imageBucket)
                .upload(
                    objectPath ?? "",
                    data: imageData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: contentType,
                        upsert: true
                    )
                )

            #if DEBUG
            print("upload_succeeded")
            #endif

            let uploadedPath = objectPath ?? ""
            let photoPayload = CreateMealPhotoPayload(
                mealId: mealId,
                homeId: homeId,
                path: uploadedPath,
                fileExtension: normalizedExtension,
                contentType: contentType,
                uploadedBy: userId
            )
            do {
                return try await client
                    .from("meal_photos")
                    .insert(photoPayload)
                    .select()
                    .single()
                    .execute()
                    .value
            } catch {
                logMealError(
                    error,
                    operation: "meal_photo_metadata_insert_nonfatal",
                    homeId: homeId,
                    mealId: mealId,
                    payloadDescription: "bucket=\(imageBucket), objectPath=\(uploadedPath), fileExtension=\(normalizedExtension), contentType=\(contentType), imageDataBytes=\(imageData.count)"
                )
                #if DEBUG
                print("meal_photo_metadata_insert_failed_nonfatal")
                #endif
                return MealPhoto(
                    id: photoId,
                    mealId: mealId,
                    homeId: homeId,
                    path: uploadedPath,
                    fileExtension: normalizedExtension,
                    contentType: contentType,
                    caption: nil,
                    sortOrder: 0,
                    uploadedBy: userId,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        } catch let error as MealServiceError {
            logMealError(
                error,
                operation: "uploadMealPhoto_preflight",
                homeId: homeId,
                mealId: mealId,
                payloadDescription: "bucket=\(imageBucket), objectPath=\(objectPath ?? "nil"), fileExtension=\(normalizedExtension), contentType=\(contentType), imageDataBytes=\(imageData.count)"
            )
            throw error
        } catch {
            logMealError(
                error,
                operation: "uploadMealPhoto",
                homeId: homeId,
                mealId: mealId,
                payloadDescription: "bucket=\(imageBucket), objectPath=\(objectPath ?? "nil"), fileExtension=\(normalizedExtension), contentType=\(contentType), imageDataBytes=\(imageData.count)"
            )
            throw MealServiceError.uploadPhotoFailed
        }
    }

    func deleteMealPhoto(photo: MealPhoto) async throws {
        do {
            try await requireAuthenticatedSession()
            _ = try? await client.storage
                .from(imageBucket)
                .remove(paths: [photo.path])
            try await client
                .from("meal_photos")
                .delete()
                .eq("id", value: photo.id.uuidString)
                .execute()
        } catch {
            logMealError(error, operation: "deleteMealPhoto", homeId: photo.homeId, mealId: photo.mealId)
            throw MealServiceError.deletePhotoFailed
        }
    }

    func createSignedMealPhotoURL(path: String) async throws -> URL {
        do {
            try await requireAuthenticatedSession()
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPath.isEmpty else {
                throw MealServiceError.invalidPhotoPath
            }
            return try await client.storage
                .from(imageBucket)
                .createSignedURL(path: normalizedPath, expiresIn: 60 * 60)
        } catch let error as MealServiceError {
            throw error
        } catch {
            logMealError(error, operation: "createSignedMealPhotoURL")
            throw MealServiceError.loadPhotoFailed
        }
    }

    func subscribeToMealChanges(
        homeId: UUID,
        onChange: @escaping @MainActor () -> Void
    ) async throws -> MealRealtimeSubscription {
        do {
            try await requireAuthenticatedSession()
            let homeIdString = homeId.uuidString.lowercased()
            let channel = client.channel("meals-home-\(homeIdString)")
            let meals = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "meals",
                filter: .eq("home_id", value: homeIdString)
            )
            let favorites = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "meal_favorites"
            )
            let collections = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "meal_collections",
                filter: .eq("home_id", value: homeIdString)
            )
            let collectionItems = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "meal_collection_items"
            )

            let listenerTasks = [meals, favorites, collections, collectionItems].map { stream in
                Task { @MainActor in
                    for await _ in stream {
                        guard !Task.isCancelled else {
                            return
                        }
                        onChange()
                    }
                }
            }

            try await channel.subscribeWithError()
            return MealRealtimeSubscription(channel: channel, listenerTasks: listenerTasks)
        } catch {
            logMealError(error, operation: "meals_realtime_subscribe", homeId: homeId)
            throw MealServiceError.realtimeSubscriptionFailed
        }
    }

    private func markRecipeImportSaved(importId: UUID, globalRecipeId: UUID) async throws {
        try await client
            .from("recipe_imports")
            .update(UpdateRecipeImportTrackingPayload.saved(globalRecipeId: globalRecipeId))
            .eq("id", value: importId.uuidString)
            .execute()
    }

    private func requireAuthenticatedSession() async throws {
        _ = try await client.auth.session
    }

    private func authenticatedUserId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw MealServiceError.unauthenticated
        }
    }

    private func normalizedCreateMealPayload(_ payload: CreateMealPayload, homeId: UUID, userId: UUID) throws -> CreateMealPayload {
        let normalizedName = try normalizedRequiredName(payload.name, error: .emptyMealName)
        return CreateMealPayload(
            homeId: homeId,
            name: normalizedName,
            description: normalizedOptionalString(payload.description),
            mealTypes: payload.mealTypes,
            cuisine: normalizedOptionalString(payload.cuisine),
            difficulty: payload.difficulty,
            prepTimeMinutes: payload.prepTimeMinutes,
            cookTimeMinutes: payload.cookTimeMinutes,
            servings: payload.servings,
            primaryPhotoPath: normalizedOptionalString(payload.primaryPhotoPath),
            sourceName: normalizedOptionalString(payload.sourceName),
            sourceURL: normalizedOptionalString(payload.sourceURL),
            notes: normalizedOptionalString(payload.notes),
            tags: normalizedTags(payload.tags),
            isArchived: payload.isArchived,
            createdBy: userId,
            updatedBy: userId
        )
    }

    private func normalizedUpdateMealPayload(_ payload: UpdateMealPayload, userId: UUID) throws -> UpdateMealPayload {
        if let name = payload.name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MealServiceError.emptyMealName
        }
        return UpdateMealPayload(
            name: payload.name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            description: normalizedOptionalString(payload.description),
            mealTypes: payload.mealTypes,
            cuisine: normalizedOptionalString(payload.cuisine),
            difficulty: payload.difficulty,
            prepTimeMinutes: payload.prepTimeMinutes,
            cookTimeMinutes: payload.cookTimeMinutes,
            servings: payload.servings,
            primaryPhotoPath: normalizedOptionalString(payload.primaryPhotoPath),
            sourceName: normalizedOptionalString(payload.sourceName),
            sourceURL: normalizedOptionalString(payload.sourceURL),
            sourceType: normalizedOptionalString(payload.sourceType),
            globalRecipeId: payload.globalRecipeId,
            importedAt: payload.importedAt,
            notes: normalizedOptionalString(payload.notes),
            tags: payload.tags.map(normalizedTags),
            isArchived: payload.isArchived,
            updatedBy: userId
        )
    }

    private func normalizedCreateCollectionPayload(homeId: UUID, name: String, description: String?, iconName: String?, userId: UUID) throws -> CreateMealCollectionPayload {
        CreateMealCollectionPayload(
            homeId: homeId,
            name: try normalizedRequiredName(name, error: .emptyCollectionName),
            description: normalizedOptionalString(description),
            iconName: normalizedOptionalString(iconName),
            createdBy: userId,
            updatedBy: userId
        )
    }

    private func normalizedUpdateCollectionPayload(name: String?, description: String?, iconName: String?, userId: UUID) throws -> UpdateMealCollectionPayload {
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MealServiceError.emptyCollectionName
        }
        return UpdateMealCollectionPayload(
            name: name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            description: normalizedOptionalString(description),
            iconName: normalizedOptionalString(iconName),
            updatedBy: userId
        )
    }

    private func saveMealRecipeParameters(homeId: UUID, mealId: UUID?, draft: MealEditorDraft, isDraft: Bool) throws -> SaveMealRecipeParameters {
        let normalizedName = try normalizedRequiredName(draft.name, error: .emptyMealName)
        return SaveMealRecipeParameters(
            requestedHomeId: homeId,
            requestedMealId: mealId,
            requestedName: normalizedName,
            requestedDescription: normalizedOptionalString(draft.description),
            requestedMealTypes: draft.mealTypes.map(\.rawValue),
            requestedCuisine: normalizedOptionalString(draft.cuisine),
            requestedDifficulty: draft.difficulty?.rawValue,
            requestedPrepTimeMinutes: draft.prepTimeMinutes,
            requestedCookTimeMinutes: draft.cookTimeMinutes,
            requestedServings: draft.servings,
            requestedPrimaryPhotoPath: normalizedOptionalString(draft.primaryPhotoPath),
            requestedSourceName: normalizedOptionalString(draft.sourceName),
            requestedSourceURL: normalizedOptionalString(draft.sourceURL),
            requestedNotes: normalizedOptionalString(draft.notes),
            requestedTags: normalizedTags(draft.tags),
            requestedIsDraft: isDraft,
            requestedIngredients: try buildSaveIngredients(from: draft.ingredients),
            requestedSteps: try buildSaveSteps(from: draft.steps)
        )
    }

    private func buildSaveIngredients(from ingredients: [MealEditorIngredient]) throws -> [SaveMealRecipeIngredient] {
        try ingredients.enumerated().compactMap { index, ingredient in
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasContent = !name.isEmpty
                || !ingredient.quantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !ingredient.preparation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !ingredient.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasContent else { return nil }
            guard !name.isEmpty else { throw MealServiceError.emptyIngredientName }

            return SaveMealRecipeIngredient(
                sectionName: normalizedOptionalString(ingredient.sectionName),
                ingredientName: name,
                quantity: try Self.decimalFromQuantityText(ingredient.quantityText),
                unit: normalizedOptionalString(ingredient.unit),
                preparation: normalizedOptionalString(ingredient.preparation),
                notes: normalizedOptionalString(ingredient.notes),
                sortOrder: index + 1,
                isOptional: ingredient.isOptional
            )
        }
    }

    private func buildSaveSteps(from steps: [MealEditorStep]) throws -> [SaveMealRecipeStep] {
        try steps.enumerated().compactMap { index, step in
            let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let timerText = step.timerMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty || !timerText.isEmpty else { return nil }
            guard !instruction.isEmpty else { throw MealServiceError.emptyRecipeStep }
            let timerMinutes = try optionalPositiveInt(from: timerText, error: .invalidMealTime)
            return SaveMealRecipeStep(
                stepNumber: index + 1,
                instruction: instruction,
                timerMinutes: timerMinutes,
                photoPath: normalizedOptionalString(step.photoPath)
            )
        }
    }

    private func validateRecipeDraft(_ recipe: MealRecipeDraft, ingredients: [RecipeIngredientDraft], steps: [RecipeStepDraft]) throws {
        for ingredient in ingredients where ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MealServiceError.emptyIngredientName
        }
        for step in steps where step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MealServiceError.emptyRecipeStep
        }
        if let prep = recipe.prepTimeMinutes, prep < 0 {
            throw MealServiceError.invalidMealTime
        }
        if let cook = recipe.cookTimeMinutes, cook < 0 {
            throw MealServiceError.invalidMealTime
        }
    }

    private func normalizedRequiredName(_ value: String, error: MealServiceError) throws -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw error
        }
        return trimmedValue
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func optionalPositiveInt(from value: String, error: MealServiceError) throws -> Int? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        guard let intValue = Int(trimmedValue), intValue >= 0 else {
            throw error
        }
        return intValue
    }

    static func decimalFromQuantityText(_ value: String) throws -> Decimal? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        if let decimal = Decimal(string: trimmedValue, locale: Locale(identifier: "en_US_POSIX")) {
            return decimal
        }

        let parts = trimmedValue.split(separator: " ").map(String.init)
        if parts.count == 2,
           let whole = Decimal(string: parts[0], locale: Locale(identifier: "en_US_POSIX")),
           let fraction = decimalFromFraction(parts[1]) {
            return whole + fraction
        }

        if let fraction = decimalFromFraction(trimmedValue) {
            return fraction
        }

        throw MealServiceError.invalidQuantity
    }

    private static func decimalFromFraction(_ value: String) -> Decimal? {
        let parts = value.split(separator: "/")
        guard parts.count == 2,
              let numerator = Decimal(string: String(parts[0]), locale: Locale(identifier: "en_US_POSIX")),
              let denominator = Decimal(string: String(parts[1]), locale: Locale(identifier: "en_US_POSIX")),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }

    private func mealPhotoPath(homeId: UUID, mealId: UUID, photoId: UUID, fileExtension: String) -> String {
        let normalizedExtension = normalizedFileExtension(fileExtension)
        return [
            homeId.uuidString.lowercased(),
            mealId.uuidString.lowercased(),
            "\(photoId.uuidString.lowercased()).\(normalizedExtension)"
        ].joined(separator: "/")
    }

    private func normalizedFileExtension(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        switch cleaned {
        case "jpeg", "jpg":
            return "jpg"
        default:
            return "jpg"
        }
    }

    private func logMealError(
        _ error: Error,
        operation: String,
        rpcName: String? = nil,
        homeId: UUID? = nil,
        mealId: UUID? = nil,
        recipeId: UUID? = nil,
        collectionId: UUID? = nil,
        isDraft: Bool? = nil,
        payloadDescription: String? = nil
    ) {
        #if DEBUG
        print("========== MEAL OPERATION FAILED ==========")
        print("operation: \(operation)")
        if let rpcName { print("rpc_name: \(rpcName)") }
        if let homeId { print("home_id: \(homeId.uuidString)") }
        if let mealId { print("meal_id: \(mealId.uuidString)") }
        if let recipeId { print("recipe_id: \(recipeId.uuidString)") }
        if let collectionId { print("collection_id: \(collectionId.uuidString)") }
        if let isDraft { print("is_draft: \(isDraft)") }
        if let payloadDescription { print("request_payload: \(payloadDescription)") }
        print("localizedDescription: \(error.localizedDescription)")
        print(String(reflecting: error))
        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        logDecodingErrorDetails(error)
        print("===========================================")
        #endif
    }

    private func logMealLoadStage(_ stage: String, mealId: UUID, recipeId: UUID? = nil) {
        #if DEBUG
        print("========== MEAL EDIT LOAD STAGE ==========")
        print("stage: \(stage)")
        print("meal_id: \(mealId.uuidString)")
        if let recipeId {
            print("recipe_id: \(recipeId.uuidString)")
        }
        print("==========================================")
        #endif
    }

    private func logDecodingErrorDetails(_ error: Error) {
        #if DEBUG
        guard let decodingError = error as? DecodingError else { return }
        switch decodingError {
        case .typeMismatch(let type, let context):
            print("DecodingError: typeMismatch \(type)")
            print("codingPath: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            print("debugDescription: \(context.debugDescription)")
            if let underlyingError = context.underlyingError {
                print("underlyingError: \(String(reflecting: underlyingError))")
            }
        case .valueNotFound(let type, let context):
            print("DecodingError: valueNotFound \(type)")
            print("codingPath: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            print("debugDescription: \(context.debugDescription)")
        case .keyNotFound(let key, let context):
            print("DecodingError: keyNotFound \(key.stringValue)")
            print("codingPath: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            print("debugDescription: \(context.debugDescription)")
        case .dataCorrupted(let context):
            print("DecodingError: dataCorrupted")
            print("codingPath: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            print("debugDescription: \(context.debugDescription)")
            if let underlyingError = context.underlyingError {
                print("underlyingError: \(String(reflecting: underlyingError))")
            }
        @unknown default:
            print("DecodingError: \(String(reflecting: decodingError))")
        }
        #endif
    }

    private func debugPayloadDescription<T: Encodable>(_ payload: T) -> String {
        #if DEBUG
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "<payload encoding produced non-UTF8 data>"
        } catch {
            return "<unable to encode payload for debug logging: \(String(reflecting: error))>"
        }
        #else
        return ""
        #endif
    }
}

enum MealServiceError: LocalizedError, Equatable {
    case unauthenticated
    case emptyMealName
    case emptyCollectionName
    case emptyIngredientName
    case emptyRecipeStep
    case invalidMealTime
    case invalidPhotoData
    case invalidPhotoPath
    case invalidQuantity
    case loadMealsFailed
    case loadMealFailed
    case saveMealFailed
    case archiveMealFailed
    case deleteMealFailed
    case loadFavoritesFailed
    case updateFavoriteFailed
    case loadCollectionsFailed
    case saveCollectionFailed
    case deleteCollectionFailed
    case updateCollectionItemsFailed
    case loadRecipeFailed
    case ingredientLoadFailed
    case stepLoadFailed
    case saveRecipeFailed
    case deleteRecipeFailed
    case uploadPhotoFailed
    case deletePhotoFailed
    case loadPhotoFailed
    case realtimeSubscriptionFailed
    case permissionDenied
    case duplicateImportedRecipe

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .emptyMealName:
            return "Enter a meal name."
        case .emptyCollectionName:
            return "Enter a collection name."
        case .emptyIngredientName:
            return "Enter an ingredient name."
        case .emptyRecipeStep:
            return "Enter each recipe step."
        case .invalidMealTime:
            return "Meal times cannot be negative."
        case .invalidPhotoData:
            return "We could not prepare that meal photo. Please choose another image."
        case .invalidPhotoPath:
            return "We could not load that meal photo."
        case .invalidQuantity:
            return "Check the ingredient quantity."
        case .loadMealsFailed:
            return "We could not load meals."
        case .loadMealFailed:
            return "We could not load this meal."
        case .saveMealFailed:
            return "We could not save this meal."
        case .archiveMealFailed:
            return "We could not archive this meal."
        case .deleteMealFailed:
            return "We could not delete this meal."
        case .loadFavoritesFailed:
            return "We could not load favorite meals."
        case .updateFavoriteFailed:
            return "We could not update favorites."
        case .loadCollectionsFailed:
            return "We could not load meal collections."
        case .saveCollectionFailed:
            return "We could not save this collection."
        case .deleteCollectionFailed:
            return "We could not delete this collection."
        case .updateCollectionItemsFailed:
            return "We could not update this collection."
        case .loadRecipeFailed:
            return "We could not load this recipe."
        case .ingredientLoadFailed:
            return "We could not load recipe ingredients."
        case .stepLoadFailed:
            return "We could not load recipe directions."
        case .saveRecipeFailed:
            return "We could not save this recipe."
        case .deleteRecipeFailed:
            return "We could not delete this recipe."
        case .uploadPhotoFailed:
            return "We could not upload this meal photo."
        case .deletePhotoFailed:
            return "We could not delete this meal photo."
        case .loadPhotoFailed:
            return "We could not load this meal photo."
        case .realtimeSubscriptionFailed:
            return "Meal updates are temporarily unavailable."
        case .permissionDenied:
            return "You do not have permission to perform this action."
        case .duplicateImportedRecipe:
            return "This recipe is already in your Home."
        }
    }
}

private extension Meal {
    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.lowercased()
        return [name, description, cuisine, notes, sourceName]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedQuery) }
            || tags.contains { $0.lowercased().contains(normalizedQuery) }
            || mealTypes.contains { $0.displayName.lowercased().contains(normalizedQuery) }
    }
}

extension Array where Element == Meal {
    func sortedForMeals() -> [Meal] {
        sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension Array where Element == MealCollection {
    func sortedForMeals() -> [MealCollection] {
        sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension Array where Element == RecipeIngredient {
    func sortedForRecipeIngredients() -> [RecipeIngredient] {
        sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension Array where Element == RecipeStep {
    func sortedForRecipeSteps() -> [RecipeStep] {
        sorted { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder
        }
    }
}
