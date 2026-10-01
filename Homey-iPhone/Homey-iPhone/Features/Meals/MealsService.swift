import Foundation
import Functions
import PostgREST
import Supabase
import UIKit

@MainActor
final class MealsService {
    private let client = SupabaseManager.shared.client
    private let imageBucket = "meal-images"
    private static var communityCopyTasks: [String: Task<UUID, Error>] = [:]
    private static var pendingCommunityPhotoCopies: [UUID: String] = [:]

    func homeRecipes(homeId: UUID) async throws -> [HomeyMeal] {
        try await client.from("meals").select().eq("home_id", value: homeId.uuidString).eq("is_archived", value: false).order("updated_at", ascending: false).execute().value
    }

    func detail(for meal: HomeyMeal) async throws -> HomeyRecipeDetail {
        struct RecipeRow: Decodable { let id: UUID }
        let rows: [RecipeRow] = try await client.from("meal_recipes").select("id").eq("meal_id", value: meal.id.uuidString).limit(1).execute().value
        guard let recipeId = rows.first?.id else { return .init(meal: meal, ingredients: [], steps: []) }
        async let ingredients: [RecipeIngredient] = client.from("recipe_ingredients").select().eq("recipe_id", value: recipeId.uuidString).order("sort_order").execute().value
        async let steps: [RecipeStep] = client.from("recipe_steps").select().eq("recipe_id", value: recipeId.uuidString).order("step_number").execute().value
        return try await .init(meal: meal, ingredients: ingredients, steps: steps)
    }

    func favoriteIDs() async throws -> Set<UUID> {
        struct Row: Decodable { let mealId: UUID; enum CodingKeys: String, CodingKey { case mealId = "meal_id" } }
        let user = try await client.auth.session.user.id
        let rows: [Row] = try await client.from("meal_favorites").select("meal_id").eq("user_id", value: user.uuidString).execute().value
        return Set(rows.map(\.mealId))
    }

    func setFavorite(mealId: UUID, isFavorite: Bool) async throws {
        let user = try await client.auth.session.user.id
        if isFavorite { try await client.from("meal_favorites").insert(FavoritePayload(mealId: mealId, userId: user)).execute() }
        else { try await client.from("meal_favorites").delete().eq("meal_id", value: mealId.uuidString).eq("user_id", value: user.uuidString).execute() }
    }

    func save(_ draft: RecipeDraft, homeId: UUID, mealId: UUID? = nil, photoPath: String? = nil) async throws -> UUID {
        _ = try await client.auth.session
        let params = try SaveMealParams(homeId: homeId, mealId: mealId, draft: draft, photoPath: photoPath)
        return try await client.rpc("save_meal_recipe", params: params).execute().value
    }

    func share(_ draft: RecipeDraft, homePhotoPath: String?) async throws -> CommunityContributionResult {
        if let existingID = draft.imported?.globalRecipeId {
            return .alreadyExists(existingID)
        }
        let params = SaveCommunityParams(draft: draft, imageURL: homePhotoPath ?? draft.importImageURL)
        do {
            let createdID: UUID = try await client.rpc("save_global_recipe", params: params).execute().value
            return .created(createdID)
        } catch {
            if let error = error as? PostgrestError,
               CommunityRecipeDuplicateClassifier.isDuplicate(
                   code: error.code,
                   message: error.message,
                   details: error.detail
               ) {
                return .alreadyExists(nil)
            }
            #if DEBUG
            print("[CommunityRecipeSave] FAILED")
            if let error = error as? PostgrestError {
                print("code=\(error.code ?? "nil")")
                print("message=\(error.message)")
                print("details=\(error.detail ?? "nil")")
                print("hint=\(error.hint ?? "nil")")
            } else {
                print("error=\(String(reflecting: error))")
            }
            #endif
            throw error
        }
    }

    func validateSave(_ draft: RecipeDraft, homeId: UUID) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MealsError.message("Enter a recipe name.")
        }
        for ingredient in draft.ingredients where ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !ingredient.quantity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ingredient.unit.isEmpty {
                throw MealsError.message("Enter a name for each ingredient that has a quantity.")
            }
        }
        _ = try SaveMealParams(homeId: homeId, mealId: nil, draft: draft)
    }

    func requireSaveSession() async throws {
        do { _ = try await client.auth.session }
        catch {
            RecipeSaveDiagnostics.failure(error, stage: "authentication")
            throw MealsError.message("Your session has expired. Please sign in again before saving.")
        }
    }

    func importPhoto(_ imageURL: String, homeId: UUID, mealId: UUID) async throws -> String {
        guard let url = URL(string: imageURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw MealsError.message("The imported recipe image URL is invalid.")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              data.count <= 12 * 1024 * 1024, let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw MealsError.message("Homey couldn’t download the recipe photo. Please try again.")
        }
        return try await uploadPhoto(jpeg, homeId: homeId, mealId: mealId)
    }

    func addToHome(_ recipe: CommunityRecipe, homeId: UUID) async throws -> UUID {
        let key = "\(homeId.uuidString)/\(recipe.id.uuidString)"
        if let task = Self.communityCopyTasks[key] { return try await task.value }
        let task = Task { try await copyCommunityRecipeToHome(recipe, homeId: homeId) }
        Self.communityCopyTasks[key] = task
        defer { Self.communityCopyTasks[key] = nil }
        return try await task.value
    }

    private func copyCommunityRecipeToHome(_ recipe: CommunityRecipe, homeId: UUID) async throws -> UUID {
        let homeMealID: UUID = try await client.rpc("add_global_meal_to_home", params: AddGlobalParams(globalId: recipe.id, homeId: homeId)).execute().value
        try await normalizeCommunityIngredientsAfterCopy(recipe.ingredients, homeMealID: homeMealID)
        guard recipe.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return homeMealID }
        do {
            struct ImageRow: Decodable { let primary_photo_path: String? }
            let homeImage: ImageRow = try await client.from("meals").select("primary_photo_path")
                .eq("id", value: homeMealID.uuidString).eq("home_id", value: homeId.uuidString)
                .single().execute().value
            // The RPC deduplicates by origin_global_recipe_id. Keep an already
            // copied or edited Home image when Add to Home is retried.
            if RecipeImageReference(homeImage.primary_photo_path) != nil {
                return homeMealID
            }
            let path: String
            if let uploaded = Self.pendingCommunityPhotoCopies[homeMealID] {
                path = uploaded
            } else {
                guard let sourceURL = await signedImageURL(path: recipe.imageURL) else {
                    throw MealsError.message("The Community photo isn't accessible.")
                }
                path = try await importPhoto(sourceURL.absoluteString, homeId: homeId, mealId: homeMealID)
                Self.pendingCommunityPhotoCopies[homeMealID] = path
            }
            struct AttachPhoto: Encodable { let primary_photo_path: String; let updated_by: UUID }
            struct UpdatedMeal: Decodable { let id: UUID }
            let userID = try await client.auth.session.user.id
            let _: UpdatedMeal = try await client.from("meals").update(AttachPhoto(primary_photo_path: path, updated_by: userID))
                .eq("id", value: homeMealID.uuidString).eq("home_id", value: homeId.uuidString)
                .select("id").single().execute().value
            Self.pendingCommunityPhotoCopies[homeMealID] = nil
            return homeMealID
        } catch {
            RecipeSaveDiagnostics.failure(error, stage: "communityPhotoCopy")
            throw MealsError.message("The recipe was added to your Home, but its photo couldn't be copied. Tap Add to My Home again to retry.")
        }
    }

    private func normalizeCommunityIngredientsAfterCopy(
        _ communityIngredients: [CommunityIngredient],
        homeMealID: UUID
    ) async throws {
        struct RecipeRow: Decodable { let id: UUID }
        struct IngredientRow: Decodable {
            let id: UUID
            let sortOrder: Int
            enum CodingKeys: String, CodingKey { case id, sortOrder = "sort_order" }
        }
        struct StructuredUpdate: Encodable {
            let ingredientName: String
            let quantity: Decimal?
            let unit: String?
            enum CodingKeys: String, CodingKey {
                case ingredientName = "ingredient_name", quantity, unit
            }
        }

        let recipes: [RecipeRow] = try await client.from("meal_recipes").select("id")
            .eq("meal_id", value: homeMealID.uuidString).limit(1).execute().value
        guard let recipeID = recipes.first?.id else { return }
        let homeIngredients: [IngredientRow] = try await client.from("recipe_ingredients")
            .select("id,sort_order").eq("recipe_id", value: recipeID.uuidString)
            .order("sort_order").execute().value
        let communityByOrder = Dictionary(uniqueKeysWithValues: communityIngredients.map { ($0.sortOrder, $0) })

        for homeIngredient in homeIngredients {
            guard let community = communityByOrder[homeIngredient.sortOrder],
                  let quantity = community.quantity?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !quantity.isEmpty
            else { continue }
            let parsed = WebsiteIngredientParser.parse("\(quantity) \(community.ingredientName)")
            guard parsed.safety == .safe else {
                continue
            }
            try await client.from("recipe_ingredients")
                .update(StructuredUpdate(
                    ingredientName: parsed.ingredientName,
                    quantity: parsed.quantity,
                    unit: parsed.unit
                ))
                .eq("id", value: homeIngredient.id.uuidString).execute()
        }
    }

    // Use the existing iPad archive contract to preserve planner/history/image references.
    func removeHomeRecipe(_ meal: HomeyMeal, home: HomeSummary) async throws {
        guard meal.homeId == home.id else { throw MealsError.message("This recipe does not belong to the active Home.") }
        let userID = try await client.auth.session.user.id
        struct Membership: Decodable { let role: String }
        let membership: Membership = try await client.from("home_members").select("role")
            .eq("home_id", value: home.id.uuidString).eq("user_id", value: userID.uuidString)
            .single().execute().value
        guard ["owner", "admin"].contains(membership.role) else {
            throw MealsError.message("Only Home owners and admins can remove recipes.")
        }
        struct Archive: Encodable {
            let is_archived = true
            let updated_by: UUID
        }
        struct ArchivedMeal: Decodable { let id: UUID }
        let _: ArchivedMeal = try await client.from("meals")
            .update(Archive(updated_by: userID))
            .eq("id", value: meal.id.uuidString).eq("home_id", value: home.id.uuidString)
            .select("id").single().execute().value
    }

    func deleteHomeRecipe(_ id: UUID) async throws { try await client.from("meals").delete().eq("id", value: id.uuidString).execute() }
    func deleteCommunityRecipe(_ id: UUID) async throws {
        struct DeletedRecipe: Decodable { let id: UUID }
        let deleted: [DeletedRecipe] = try await client.from("global_recipes").delete()
            .eq("id", value: id.uuidString).select("id").execute().value
        guard deleted.contains(where: { $0.id == id }) else {
            throw MealsError.message("You don't have permission to delete this community recipe.")
        }
    }

    func importURL(_ url: String, homeId: UUID) async throws -> RecipeImportResponse {
        guard let cleanURL = RecipeImportInput.validURL(url) else { throw MealsError.message("Enter a valid recipe URL.") }
        do {
            let response: RecipeImportResponse = try await client.functions.invoke("import-recipe-url", options: FunctionInvokeOptions(body: RecipeImportRequest(homeId: homeId, url: cleanURL))) { data, _ in
                return try RecipeImportResponseDecoder.decode(data)
            }
            return response
        } catch {
            var code = error is URLError ? "NETWORK_ERROR" : "IMPORT_REQUEST_ERROR"
            if let responseError = error as? RecipeImportResponseError { code = responseError.code }
            if let decodingError = error as? DecodingError {
                code = "RESPONSE_DECODING_ERROR"
                RecipeSaveDiagnostics.failure(decodingError, stage: "recipeImportDecoding")
            }
            if let functionError = error as? FunctionsError, case .httpError(let status, let data) = functionError {
                code = RecipeImportInput.errorCode(data: data) ?? "HTTP_\(status)"
            }
            #if DEBUG
            print("[RecipeImport] FAILED")
            print("[RecipeImport] code=\(code)")
            print("[RecipeImport] errorType=\(String(reflecting: type(of: error)))")
            print("[RecipeImport] message=\(RecipeImportInput.message(for: code))")
            #endif
            throw MealsError.message(RecipeImportInput.message(for: code))
        }
    }

    func signedImageURL(path: String?) async -> URL? {
        guard let reference = RecipeImageReference(path) else { return nil }
        switch reference {
        case .remote(let url): return url
        case .storage(let path):
            return try? await client.storage.from(imageBucket).createSignedURL(path: path, expiresIn: 3600)
        }
    }

    func uploadPhoto(_ data: Data, homeId: UUID, mealId: UUID) async throws -> String {
        guard !data.isEmpty else { throw MealsError.message("The recipe photo is empty. Please choose another image.") }
        let path = RecipeImageStoragePath.make(homeId: homeId, mealId: mealId)
        try await client.storage.from(imageBucket).upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
        return path
    }

    func mealPlanEntries(homeID: UUID, startDate: String, endDate: String) async throws -> [MealPlanEntry] {
        let entries: [MealPlanEntry] = try await client.rpc(
            "get_meal_plan_entries",
            params: MealPlanRangeParameters(homeID: homeID, startDate: startDate, endDate: endDate)
        ).execute().value
        return entries.sorted {
            if $0.plannedDate != $1.plannedDate { return $0.plannedDate < $1.plannedDate }
            if $0.mealType != $1.mealType { return $0.mealType.rawValue < $1.mealType.rawValue }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func saveMealPlanEntry(
        homeID: UUID,
        entryID: UUID?,
        mealID: UUID,
        plannedDate: String,
        mealType: MealType,
        plannedServings: Double?,
        mealNotes: String?,
        sortOrder: Int
    ) async throws {
        try await client.rpc(
            "save_meal_plan_entry",
            params: SaveMealPlanEntryParameters(
                homeID: homeID,
                entryID: entryID,
                mealID: mealID,
                plannedDate: plannedDate,
                mealType: mealType,
                plannedServings: plannedServings,
                mealNotes: mealNotes,
                sortOrder: sortOrder
            )
        ).execute()
    }

    func deleteMealPlanEntry(homeID: UUID, entryID: UUID) async throws {
        try await client.rpc(
            "delete_meal_plan_entry",
            params: DeleteMealPlanEntryParameters(homeID: homeID, entryID: entryID)
        ).execute()
    }

    func applyMealAutoPlan(
        homeID: UUID,
        entries: [MealAutoPlanEntry],
        idempotencyKey: UUID
    ) async throws -> ApplyMealAutoPlanResponse {
        try await client.rpc(
            "apply_meal_auto_plan",
            params: ApplyMealAutoPlanParameters(
                homeID: homeID,
                entries: entries,
                idempotencyKey: idempotencyKey
            )
        ).execute().value
    }

    func assignMealPlanLeftovers(
        homeID: UUID,
        sourceEntryIDs: [UUID],
        destinationDate: String,
        conflictMode: LeftoverConflictMode,
        idempotencyKey: UUID
    ) async throws -> AssignMealPlanLeftoversResponse {
        let parameters = AssignMealPlanLeftoversParameters(
            homeID: homeID,
            sourceEntryIDs: sourceEntryIDs,
            destinationDate: destinationDate,
            conflictMode: conflictMode,
            idempotencyKey: idempotencyKey
        )

        do {
            let response: AssignMealPlanLeftoversResponse = try await client
                .rpc("assign_meal_plan_leftovers", params: parameters)
                .execute().value
            return response
        } catch {
            #if DEBUG
            print("[Homey] ASSIGN LEFTOVERS FAILED: \(String(reflecting: error))")
            #endif
            throw error
        }
    }

}

enum LeftoverConflictMode: String, Codable, Equatable {
    case add, replace

    var title: String { self == .add ? "Add Anyway" : "Replace" }
}

struct AssignMealPlanLeftoversResponse: Decodable {
    let homeID: UUID
    let sourceDate: String
    let destinationDate: String
    let conflictMode: LeftoverConflictMode
    let createdEntryIDs: [UUID]
    let deletedEntryIDs: [UUID]
    let createdCount: Int
    let deletedCount: Int
    let idempotencyKey: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "home_id"
        case sourceDate = "source_date"
        case destinationDate = "destination_date"
        case conflictMode = "conflict_mode"
        case createdEntryIDs = "created_entry_ids"
        case deletedEntryIDs = "deleted_entry_ids"
        case createdCount = "created_count"
        case deletedCount = "deleted_count"
        case idempotencyKey = "idempotency_key"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        homeID = try values.decode(UUID.self, forKey: .homeID)
        sourceDate = try values.decode(String.self, forKey: .sourceDate)
        destinationDate = try values.decode(String.self, forKey: .destinationDate)
        conflictMode = try values.decode(LeftoverConflictMode.self, forKey: .conflictMode)
        createdEntryIDs = try values.decode([UUID].self, forKey: .createdEntryIDs)
        deletedEntryIDs = try values.decodeIfPresent([UUID].self, forKey: .deletedEntryIDs) ?? []
        createdCount = try values.decode(Int.self, forKey: .createdCount)
        deletedCount = try values.decodeIfPresent(Int.self, forKey: .deletedCount) ?? 0
        idempotencyKey = try values.decode(UUID.self, forKey: .idempotencyKey)
    }
}

enum MealsError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let value) = self { value } else { nil } } }
private struct FavoritePayload: Encodable { let mealId, userId: UUID; enum CodingKeys: String, CodingKey { case mealId = "meal_id", userId = "user_id" } }
private struct AddGlobalParams: Encodable { let globalId, homeId: UUID; enum CodingKeys: String, CodingKey { case globalId = "requested_global_meal_id", homeId = "requested_home_id" } }
private struct ImportErrorEnvelope: Decodable { struct Body: Decodable { let message: String }; let error: Body }
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
        if let entryID { try values.encode(entryID, forKey: .entryID) }
        else { try values.encodeNil(forKey: .entryID) }
        try values.encode(mealID, forKey: .mealID)
        try values.encode(plannedDate, forKey: .plannedDate)
        try values.encode(mealType, forKey: .mealType)
        if let plannedServings { try values.encode(plannedServings, forKey: .plannedServings) }
        else { try values.encodeNil(forKey: .plannedServings) }
        if let mealNotes { try values.encode(mealNotes, forKey: .mealNotes) }
        else { try values.encodeNil(forKey: .mealNotes) }
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
private struct ApplyMealAutoPlanParameters: Encodable {
    let homeID: UUID
    let entries: [MealAutoPlanEntry]
    let idempotencyKey: UUID
    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case entries = "requested_entries"
        case idempotencyKey = "requested_idempotency_key"
    }
}
private struct AssignMealPlanLeftoversParameters: Encodable {
    let homeID: UUID
    let sourceEntryIDs: [UUID]
    let destinationDate: String
    let conflictMode: LeftoverConflictMode
    let idempotencyKey: UUID

    enum CodingKeys: String, CodingKey {
        case homeID = "requested_home_id"
        case sourceEntryIDs = "requested_source_entry_ids"
        case destinationDate = "requested_destination_date"
        case conflictMode = "requested_conflict_mode"
        case idempotencyKey = "requested_idempotency_key"
    }
}
struct SaveMealParams: Encodable {
    let photoPath: String?
    let homeId: UUID, mealId: UUID?, name: String, description: String?, mealTypes: [String], cuisine: String?, difficulty: String?, prep, cook: Int?, servings: Double?, sourceName, sourceURL, notes: String?, tags: [String], ingredients: [Ingredient], steps: [Step]
    init(homeId: UUID, mealId: UUID?, draft: RecipeDraft, photoPath: String? = nil) throws { self.photoPath = photoPath; self.homeId = homeId; self.mealId = mealId; name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines); description = draft.description.nilIfBlank; mealTypes = draft.mealTypes.map(\.rawValue); cuisine = draft.cuisine.nilIfBlank; difficulty = draft.difficulty?.rawValue; prep = draft.prepMinutes; cook = draft.cookMinutes; servings = draft.servings; sourceName = draft.sourceName.nilIfBlank; sourceURL = draft.sourceURL.nilIfBlank; notes = draft.notes.nilIfBlank; tags = draft.tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }; ingredients = try draft.ingredients.enumerated().filter { !$0.element.name.nilIfBlank.isNil }.map { try Ingredient($0.element, order: $0.offset + 1) }; steps = draft.steps.enumerated().filter { !$0.element.text.nilIfBlank.isNil }.map { Step($0.element, order: $0.offset + 1) } }
    enum CodingKeys: String, CodingKey { case homeId = "requested_home_id", mealId = "requested_meal_id", name = "requested_name", description = "requested_description", mealTypes = "requested_meal_types", cuisine = "requested_cuisine", difficulty = "requested_difficulty", prep = "requested_prep_time_minutes", cook = "requested_cook_time_minutes", servings = "requested_servings", sourceName = "requested_source_name", sourceURL = "requested_source_url", notes = "requested_notes", tags = "requested_tags", ingredients = "requested_ingredients", steps = "requested_steps" }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(homeId, forKey: .homeId); try c.encode(mealId, forKey: .mealId); try c.encode(name, forKey: .name); try c.encode(description, forKey: .description); try c.encode(mealTypes, forKey: .mealTypes); try c.encode(cuisine, forKey: .cuisine); try c.encode(difficulty, forKey: .difficulty); try c.encode(prep, forKey: .prep); try c.encode(cook, forKey: .cook); try c.encode(servings, forKey: .servings); try c.encode(sourceName, forKey: .sourceName); try c.encode(sourceURL, forKey: .sourceURL); try c.encode(notes, forKey: .notes); try c.encode(tags, forKey: .tags); try c.encode(ingredients, forKey: .ingredients); try c.encode(steps, forKey: .steps); var d = encoder.container(keyedBy: DynamicKey.self); try d.encode(false, forKey: .init("requested_is_draft")); try d.encode(photoPath, forKey: .init("requested_primary_photo_path")) }
    struct DynamicKey: CodingKey { let stringValue: String; let intValue: Int? = nil; init(_ value: String) { stringValue = value }; init?(stringValue: String) { self.init(stringValue) }; init?(intValue: Int) { return nil } }
    struct Ingredient: Encodable {
        let sectionName, unit, preparation, notes: String?
        let ingredientName: String
        let quantity: Decimal?
        let sortOrder: Int
        let isOptional: Bool

        init(_ draft: IngredientDraft, order: Int) throws {
            preparation = draft.preparation
            notes = draft.notes
            sectionName = draft.section.nilIfBlank
            ingredientName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            quantity = try RecipeQuantity.decimal(draft.quantity)
            unit = draft.unit.nilIfBlank
            sortOrder = order
            isOptional = draft.optional
        }

        enum CodingKeys: String, CodingKey {
            case quantity, unit, preparation, notes
            case sectionName = "section_name", ingredientName = "ingredient_name"
            case sortOrder = "sort_order", isOptional = "is_optional"
        }
    }
    struct Step: Encodable { let stepNumber: Int; let instruction: String; let timerMinutes: Int?; init(_ d: StepDraft, order: Int) { stepNumber=order; instruction=d.text; timerMinutes=d.timerMinutes }; enum CodingKeys: String, CodingKey { case instruction; case stepNumber="step_number", timerMinutes="timer_minutes" } }
}
struct SaveCommunityParams: Encodable {
    let title: String; let imageURL: String?; let sourceType: String; let description, cuisine, servings, sourceName, sourceURL: String?; let prep, cook, total: Int?; let mealTypes, keywords: [String]; let ingredients: [CommunityIngredient]; let steps: [CommunityStep]
    init(draft: RecipeDraft, imageURL: String? = nil) {
        self.imageURL = imageURL ?? draft.importImageURL
        sourceType = CommunityRecipeSourceType.forDraft(draft).rawValue
        title = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        description = draft.description.nilIfBlank
        cuisine = draft.cuisine.nilIfBlank
        servings = draft.servings.map { String($0) }
        sourceName = draft.sourceName.nilIfBlank
        sourceURL = draft.sourceURL.nilIfBlank
        prep = draft.prepMinutes
        cook = draft.cookMinutes
        total = draft.imported?.recipe.totalTimeMinutes ?? (((draft.prepMinutes ?? 0) + (draft.cookMinutes ?? 0)) > 0 ? (draft.prepMinutes ?? 0) + (draft.cookMinutes ?? 0) : nil)
        mealTypes = draft.mealTypes.map(\.rawValue)
        keywords = draft.tagsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        ingredients = draft.ingredients.enumerated().filter { !$0.element.name.isEmpty }.map { index, ingredient in
            CommunityIngredient(
                quantity: Self.communityQuantity(for: ingredient),
                sortOrder: index,
                isOptional: ingredient.optional,
                sectionName: ingredient.section.nilIfBlank,
                ingredientName: ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        steps = draft.steps.enumerated().filter { !$0.element.text.isEmpty }.map {
            CommunityStep(stepText: $0.element.text, sortOrder: $0.offset, sectionName: nil)
        }
    }

    private static func communityQuantity(for ingredient: IngredientDraft) -> String? {
        let quantity: Decimal?
        if let text = ingredient.quantity.nilIfBlank {
            quantity = (try? RecipeQuantity.decimal(text)) ?? nil
        } else {
            quantity = nil
        }
        return CommunityIngredientQuantityFormatter.string(quantity: quantity, unit: ingredient.unit.nilIfBlank)
    }
    enum CodingKeys: String, CodingKey { case title="requested_title", description="requested_description", prep="requested_prep_time_minutes", cook="requested_cook_time_minutes", total="requested_total_time_minutes", servings="requested_servings", cuisine="requested_cuisine", mealTypes="requested_meal_types", keywords="requested_keywords", ingredients="requested_ingredients", steps="requested_steps", sourceName="requested_source_name", sourceURL="requested_source_url" }
    func encode(to encoder: Encoder) throws { var c=encoder.container(keyedBy:CodingKeys.self); try c.encode(title,forKey:.title); try c.encode(description,forKey:.description); try c.encode(prep,forKey:.prep); try c.encode(cook,forKey:.cook); try c.encode(total,forKey:.total); try c.encode(servings,forKey:.servings); try c.encode(cuisine,forKey:.cuisine); try c.encode(mealTypes,forKey:.mealTypes); try c.encode(keywords,forKey:.keywords); try c.encode(ingredients,forKey:.ingredients); try c.encode(steps,forKey:.steps); try c.encode(sourceName,forKey:.sourceName); try c.encode(sourceURL,forKey:.sourceURL); var d=encoder.container(keyedBy:DynamicKey.self); try d.encode(imageURL,forKey:.init("requested_image_url")); try d.encode(sourceType,forKey:.init("requested_source_type")) }
    struct DynamicKey: CodingKey { let stringValue:String; let intValue:Int?=nil; init(_ v:String){stringValue=v}; init?(stringValue:String){self.init(stringValue)}; init?(intValue:Int){return nil} }
}
private extension String { var nilIfBlank: String? { let value=trimmingCharacters(in:.whitespacesAndNewlines); return value.isEmpty ? nil : value } }
private extension Optional { var isNil: Bool { self == nil } }

// Matches iPad MealService.mealPhotoPath. IDs are persisted Home/meal IDs,
// not the separate meal_recipes row ID; there is no user folder or literal prefix.
enum RecipeImageStoragePath {
    static func make(homeId: UUID, mealId: UUID, photoId: UUID = UUID()) -> String {
        [homeId.uuidString.lowercased(), mealId.uuidString.lowercased(),
         "\(photoId.uuidString.lowercased()).jpg"].joined(separator: "/")
    }
}

// Supported by the deployed global_recipes_source_type_check.
// This editor creates community contributions or imports URLs; it does not
// create Instagram imports or variations.
enum CommunityRecipeSourceType: String {
    case community, url

    static func forDraft(_ draft: RecipeDraft) -> Self {
        draft.imported == nil ? .community : .url
    }
}

enum CommunityContributionResult: Equatable {
    case created(UUID)
    case alreadyExists(UUID?)
}

enum CommunityRecipeDuplicateClassifier {
    static func isDuplicate(code: String?, message: String, details: String?) -> Bool {
        if code == "23505" { return true }
        guard code == "P0001" else { return false }
        let text = [message, details].compactMap { $0 }.joined(separator: " ").lowercased()
        return text.contains("already exists") || text.contains("duplicate")
    }
}

enum CommunityIngredientQuantityFormatter {
    static func string(quantity: Decimal?, unit: String?) -> String? {
        let amount = quantity.map { NSDecimalNumber(decimal: $0).stringValue }
        return [amount, unit?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank]
            .compactMap { $0 }.joined(separator: " ").nilIfBlank
    }
}
