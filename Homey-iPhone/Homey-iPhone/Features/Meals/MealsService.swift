import Foundation
import Functions
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

    func share(_ draft: RecipeDraft, homeRecipeID: UUID, homePhotoPath: String?) async throws -> UUID {
        _ = try await client.auth.session
        let params = SaveCommunityParams(draft: draft)
        #if DEBUG
        print("[RecipeImageFlow] homeRecipeID=\(homeRecipeID.uuidString)")
        print("[RecipeImageFlow] uploadedPath=\(homePhotoPath ?? "nil")")
        print("[RecipeImageFlow] homeImageField=\(homePhotoPath ?? "nil")")
        print("[RecipeImageFlow] globalImagePayload=\(RecipeImageReference.safeLog(params.imageURL))")
        print("[CommunityRecipe] sourceType=\(params.sourceType)")
        print("[CommunityRecipe] source=\(params.sourceName ?? "nil")")
        print("[CommunityRecipe] sourceURL=\(params.sourceURL ?? "nil")")
        print("[CommunityRecipe] imported=\(draft.imported != nil)")
        #endif
        return try await client.rpc("save_global_recipe", params: params).execute().value
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
        #if DEBUG
        print("[RecipeImageFlow] source=community")
        print("[RecipeImageFlow] globalRecipeID=\(recipe.id.uuidString)")
        print("[RecipeImageFlow] globalImageReference=\(RecipeImageReference.safeLog(recipe.imageURL))")
        print("[RecipeImageFlow] homeRecipeID=\(homeMealID.uuidString)")
        #endif
        guard let sourceImage = recipe.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceImage.isEmpty else { return homeMealID }
        do {
            struct ImageRow: Decodable { let primary_photo_path: String? }
            let homeImage: ImageRow = try await client.from("meals").select("primary_photo_path")
                .eq("id", value: homeMealID.uuidString).eq("home_id", value: homeId.uuidString)
                .single().execute().value
            // The RPC deduplicates by origin_global_recipe_id. Keep an already
            // copied or edited Home image when Add to Home is retried.
            if let existing = RecipeImageReference(homeImage.primary_photo_path) {
                #if DEBUG
                print("[RecipeImageFlow] homeImageReference=\(RecipeImageReference.safeLog(existing.value))")
                #endif
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
            #if DEBUG
            print("[RecipeImageFlow] uploadedPath=\(path)")
            print("[RecipeImageFlow] homeImageReference=\(path)")
            #endif
            return homeMealID
        } catch {
            RecipeSaveDiagnostics.failure(error, stage: "communityPhotoCopy")
            throw MealsError.message("The recipe was added to your Home, but its photo couldn't be copied. Tap Add to My Home again to retry.")
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
        #if DEBUG
        print("[RecipeImport] Starting url=\(RecipeImportInput.safeLogURL(cleanURL))")
        print("[RecipeImport] Calling importer")
        #endif
        do {
            let response: RecipeImportResponse = try await client.functions.invoke("import-recipe-url", options: FunctionInvokeOptions(body: RecipeImportRequest(homeId: homeId, url: cleanURL))) { data, response in
                RecipeImportDiagnostics.response(data: data, status: response.statusCode, contentType: response.value(forHTTPHeaderField: "Content-Type"))
                return try RecipeImportResponseDecoder.decode(data)
            }
            RecipeImportDiagnostics.decoded(response)
            #if DEBUG
            print("[RecipeImport] Success")
            print("[RecipeImport] title=\(response.recipe.title)")
            print("[RecipeImport] imagePresent=\(response.recipe.imageUrl?.isEmpty == false)")
            print("[RecipeImport] ingredients=\(response.recipe.ingredients.count)")
            print("[RecipeImport] directions=\(response.recipe.steps.count)")
            #endif
            return response
        } catch {
            var code = error is URLError ? "NETWORK_ERROR" : "IMPORT_REQUEST_ERROR"
            if let responseError = error as? RecipeImportResponseError { code = responseError.code }
            if let decodingError = error as? DecodingError {
                code = "RESPONSE_DECODING_ERROR"
                RecipeImportDiagnostics.decoding(decodingError)
            }
            if let functionError = error as? FunctionsError, case .httpError(let status, let data) = functionError {
                RecipeImportDiagnostics.response(data: data, status: status, contentType: nil)
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
        let userID = try await client.auth.session.user.id
        guard !data.isEmpty else { throw MealsError.message("The recipe photo is empty. Please choose another image.") }
        let path = RecipeImageStoragePath.make(homeId: homeId, mealId: mealId)
        #if DEBUG
        print("[RecipeImage] bucket=\(imageBucket)")
        print("[RecipeImage] path=\(path)")
        print("[RecipeImage] userID=\(userID.uuidString)")
        print("[RecipeImage] homeID=\(homeId.uuidString)")
        print("[RecipeImage] recipeID=\(mealId.uuidString)")
        #endif
        try await client.storage.from(imageBucket).upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
        return path
    }

    func plannedMeals(home: HomeSummary, week: DateInterval) async throws -> [PlannedMeal] {
        let events: [CalendarMealEvent] = try await client.rpc("get_calendar_events", params: CalendarRange(homeId: home.id, start: week.start, end: week.end)).execute().value
        guard !events.isEmpty else { return [] }
        let details: [MealEventDetailRow] = try await client.from("meal_event_details").select("calendar_event_id, meal_id, meal_type").execute().value
        let eventIDs = Set(events.map(\.eventId)); let matching = details.filter { eventIDs.contains($0.calendarEventId) }
        let meals = try await homeRecipes(homeId: home.id); let mealByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) }); let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.eventId, $0) })
        return matching.compactMap { d in guard let e = eventByID[d.calendarEventId], let m = mealByID[d.mealId] else { return nil }; return PlannedMeal(eventId: e.eventId, occurrenceId: e.occurrenceId, startsAt: e.occurrenceStartsAt, mealType: d.mealType, meal: m) }.sorted { $0.startsAt < $1.startsAt }
    }

    func schedule(_ meal: HomeyMeal, type: MealType, day: Date, home: HomeSummary) async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = home.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let start = calendar.date(bySettingHour: type.hour, minute: 0, second: 0, of: day) ?? day
        let category: [CategoryRow] = try await client.from("calendar_categories").select("id").eq("home_id", value: home.id.uuidString).eq("system_category_key", value: "meal").limit(1).execute().value
        let eventId: UUID = try await client.rpc("create_calendar_event", params: CreateEvent(home: home, meal: meal, start: start, categoryId: category.first?.id)).execute().value
        do {
            let user = try await client.auth.session.user.id
            try await client.from("meal_event_details").insert(CreateMealDetail(eventId: eventId, mealId: meal.id, mealType: type, userId: user)).execute()
        } catch { try? await removePlanned(eventId); throw error }
    }

    func removePlanned(_ eventId: UUID) async throws { try await client.rpc("delete_calendar_event", params: DeleteEvent(eventId: eventId)).execute() }
}

enum MealsError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let value) = self { value } else { nil } } }
private struct FavoritePayload: Encodable { let mealId, userId: UUID; enum CodingKeys: String, CodingKey { case mealId = "meal_id", userId = "user_id" } }
private struct AddGlobalParams: Encodable { let globalId, homeId: UUID; enum CodingKeys: String, CodingKey { case globalId = "requested_global_meal_id", homeId = "requested_home_id" } }
private struct ImportErrorEnvelope: Decodable { struct Body: Decodable { let message: String }; let error: Body }
private struct CalendarRange: Encodable { let homeId: UUID; let start, end: Date; enum CodingKeys: String, CodingKey { case homeId = "target_home_id", start = "range_start", end = "range_end" } }
private struct CategoryRow: Decodable { let id: UUID }
private struct DeleteEvent: Encodable { let eventId: UUID; enum CodingKeys: String, CodingKey { case eventId = "target_event_id" } }
private struct CreateMealDetail: Encodable { let eventId, mealId: UUID; let mealType: MealType; let shoppingGenerated = false; let userId: UUID; enum CodingKeys: String, CodingKey { case eventId = "calendar_event_id", mealId = "meal_id", mealType = "meal_type", shoppingGenerated = "shopping_generated", userId = "created_by" } }
private struct CreateEvent: Encodable {
    let homeId: UUID, title: String, start, end, timezone: String, categoryId: UUID?
    init(home: HomeSummary, meal: HomeyMeal, start: Date, categoryId: UUID?) { homeId = home.id; title = meal.name; self.start = ISO8601DateFormatter().string(from: start); end = ISO8601DateFormatter().string(from: start.addingTimeInterval(3600)); timezone = home.timezone ?? TimeZone.current.identifier; self.categoryId = categoryId }
    enum CodingKeys: String, CodingKey { case homeId = "target_home_id", title = "event_title", start = "event_starts_at", end = "event_ends_at", timezone = "event_timezone", categoryId = "event_category_id" }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(homeId, forKey: .homeId); try c.encode(title, forKey: .title); try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(timezone, forKey: .timezone); try c.encodeIfPresent(categoryId, forKey: .categoryId); var dynamic = encoder.container(keyedBy: DynamicKey.self); try dynamic.encode(false, forKey: .init("event_is_all_day")); try dynamic.encode([UUID](), forKey: .init("assigned_user_ids")); try dynamic.encode(1, forKey: .init("event_recurrence_interval")) }
    struct DynamicKey: CodingKey { let stringValue: String; let intValue: Int? = nil; init(_ value: String) { stringValue = value }; init?(stringValue: String) { self.init(stringValue) }; init?(intValue: Int) { return nil } }
}

struct SaveMealParams: Encodable {
    let photoPath: String?
    let homeId: UUID, mealId: UUID?, name: String, description: String?, mealTypes: [String], cuisine: String?, difficulty: String?, prep, cook: Int?, servings: Double?, sourceName, sourceURL, notes: String?, tags: [String], ingredients: [Ingredient], steps: [Step]
    init(homeId: UUID, mealId: UUID?, draft: RecipeDraft, photoPath: String? = nil) throws { self.photoPath = photoPath; self.homeId = homeId; self.mealId = mealId; name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines); description = draft.description.nilIfBlank; mealTypes = draft.mealTypes.map(\.rawValue); cuisine = draft.cuisine.nilIfBlank; difficulty = draft.difficulty?.rawValue; prep = draft.prepMinutes; cook = draft.cookMinutes; servings = draft.servings; sourceName = draft.sourceName.nilIfBlank; sourceURL = draft.sourceURL.nilIfBlank; notes = draft.notes.nilIfBlank; tags = draft.tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }; ingredients = try draft.ingredients.enumerated().filter { !$0.element.name.nilIfBlank.isNil }.map { try Ingredient($0.element, order: $0.offset + 1) }; steps = draft.steps.enumerated().filter { !$0.element.text.nilIfBlank.isNil }.map { Step($0.element, order: $0.offset + 1) } }
    enum CodingKeys: String, CodingKey { case homeId = "requested_home_id", mealId = "requested_meal_id", name = "requested_name", description = "requested_description", mealTypes = "requested_meal_types", cuisine = "requested_cuisine", difficulty = "requested_difficulty", prep = "requested_prep_time_minutes", cook = "requested_cook_time_minutes", servings = "requested_servings", sourceName = "requested_source_name", sourceURL = "requested_source_url", notes = "requested_notes", tags = "requested_tags", ingredients = "requested_ingredients", steps = "requested_steps" }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(homeId, forKey: .homeId); try c.encode(mealId, forKey: .mealId); try c.encode(name, forKey: .name); try c.encode(description, forKey: .description); try c.encode(mealTypes, forKey: .mealTypes); try c.encode(cuisine, forKey: .cuisine); try c.encode(difficulty, forKey: .difficulty); try c.encode(prep, forKey: .prep); try c.encode(cook, forKey: .cook); try c.encode(servings, forKey: .servings); try c.encode(sourceName, forKey: .sourceName); try c.encode(sourceURL, forKey: .sourceURL); try c.encode(notes, forKey: .notes); try c.encode(tags, forKey: .tags); try c.encode(ingredients, forKey: .ingredients); try c.encode(steps, forKey: .steps); var d = encoder.container(keyedBy: DynamicKey.self); try d.encode(false, forKey: .init("requested_is_draft")); try d.encode(photoPath, forKey: .init("requested_primary_photo_path")) }
    struct DynamicKey: CodingKey { let stringValue: String; let intValue: Int? = nil; init(_ value: String) { stringValue = value }; init?(stringValue: String) { self.init(stringValue) }; init?(intValue: Int) { return nil } }
    struct Ingredient: Encodable { let sectionName, ingredientName, unit, preparation, notes: String?; let quantity: Decimal?; let sortOrder: Int; let isOptional: Bool; init(_ d: IngredientDraft, order: Int) throws { preparation=d.preparation; notes=d.notes; sectionName=d.section.nilIfBlank; ingredientName=d.name; quantity=try RecipeQuantity.decimal(d.quantity); unit=d.unit.nilIfBlank; sortOrder=order; isOptional=d.optional }; enum CodingKeys: String, CodingKey { case quantity, unit, preparation, notes; case sectionName="section_name", ingredientName="ingredient_name", sortOrder="sort_order", isOptional="is_optional" } }
    struct Step: Encodable { let stepNumber: Int; let instruction: String; let timerMinutes: Int?; init(_ d: StepDraft, order: Int) { stepNumber=order; instruction=d.text; timerMinutes=d.timerMinutes }; enum CodingKeys: String, CodingKey { case instruction; case stepNumber="step_number", timerMinutes="timer_minutes" } }
}
struct SaveCommunityParams: Encodable {
    let title: String; let imageURL: String?; let sourceType: String; let description, cuisine, servings, sourceName, sourceURL: String?; let prep, cook, total: Int?; let mealTypes, keywords: [String]; let ingredients: [CommunityIngredient]; let steps: [CommunityStep]
    init(draft: RecipeDraft) { imageURL=draft.importImageURL; sourceType=CommunityRecipeSourceType.forDraft(draft).rawValue; title=draft.name.trimmingCharacters(in: .whitespacesAndNewlines); description=draft.description.nilIfBlank; cuisine=draft.cuisine.nilIfBlank; servings=draft.servings.map { String($0) }; sourceName=draft.sourceName.nilIfBlank; sourceURL=draft.sourceURL.nilIfBlank; prep=draft.prepMinutes; cook=draft.cookMinutes; total=draft.imported?.recipe.totalTimeMinutes ?? (((draft.prepMinutes ?? 0)+(draft.cookMinutes ?? 0)) > 0 ? (draft.prepMinutes ?? 0)+(draft.cookMinutes ?? 0) : nil); mealTypes=draft.mealTypes.map(\.rawValue); keywords=draft.tagsText.split(separator:",").map{String($0).trimmingCharacters(in:.whitespaces)}; ingredients=draft.ingredients.enumerated().filter{!$0.element.name.isEmpty}.map{CommunityIngredient(quantity:$0.element.quantity.nilIfBlank,sortOrder:$0.offset,isOptional:$0.element.optional,sectionName:$0.element.section.nilIfBlank,ingredientName:$0.element.name)}; steps=draft.steps.enumerated().filter{!$0.element.text.isEmpty}.map{CommunityStep(stepText:$0.element.text,sortOrder:$0.offset,sectionName:nil)} }
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
