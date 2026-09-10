import Foundation

@main struct RecipeSaveContractChecks {
    static func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }
    static func main() throws {
        let homeID = UUID()
        var draft = RecipeDraft()
        draft.name = "Contract check"
        let home = try json(SaveMealParams(homeId: homeID, mealId: nil, draft: draft))
        let referenceHome = try json(SaveMealRecipeParameters(requestedHomeId: homeID, requestedMealId: nil, requestedName: draft.name, requestedDescription: nil, requestedMealTypes: [], requestedCuisine: nil, requestedDifficulty: "easy", requestedPrepTimeMinutes: nil, requestedCookTimeMinutes: nil, requestedServings: nil, requestedPrimaryPhotoPath: nil, requestedSourceName: nil, requestedSourceURL: nil, requestedNotes: nil, requestedTags: [], requestedIsDraft: false, requestedIngredients: [], requestedSteps: []))
        assert(NSDictionary(dictionary: home).isEqual(to: referenceHome), "Home payload must match the iPad contract, including explicit nulls")
        let community = try json(SaveCommunityParams(draft: draft))
        assert(community["requested_source_type"] as? String == "community", "Manual contributions must satisfy the deployed source-type constraint")
        let referenceCommunity = try json(SaveGlobalRecipeParameters(requestedTitle: draft.name, requestedDescription: nil, requestedImageURL: nil, requestedPrepTimeMinutes: nil, requestedCookTimeMinutes: nil, requestedTotalTimeMinutes: nil, requestedServings: nil, requestedCuisine: nil, requestedMealTypes: [], requestedKeywords: [], requestedIngredients: [], requestedSteps: [], requestedSourceType: "community", requestedSourceName: nil, requestedSourceURL: nil))
        assert(NSDictionary(dictionary: community).isEqual(to: referenceCommunity), "Community RPC has 15 required arguments, including null-valued arguments")
        draft.ingredients = [IngredientDraft(name: "Flour", quantity: "1 1/2")]
        let populated = try json(SaveMealParams(homeId: homeID, mealId: nil, draft: draft))
        let ingredient = (populated["requested_ingredients"] as! [[String: Any]])[0]
        assert(ingredient["quantity"] is NSNumber)
        assert((ingredient["quantity"] as! NSNumber).doubleValue == 1.5)
        assert(ingredient["sort_order"] as! Int == 1)
        let half = try RecipeQuantity.decimal("1/2")
        assert(half == Decimal(string: "0.5"))
        do { _ = try RecipeQuantity.decimal("2 cups"); fatalError("Invalid numeric quantity accepted") } catch {}
        let preview = ImportedRecipePreview(title: draft.name, description: nil, imageUrl: "https://example.com/recipe.jpg", prepTimeMinutes: nil, cookTimeMinutes: nil, totalTimeMinutes: nil, servings: nil, cuisine: nil, mealTypes: ["dessert"], keywords: ["cake"], ingredients: [], steps: [], source: ImportedRecipeSource(originalUrl: "https://example.com/recipe", normalizedUrl: "https://example.com/recipe", domain: "example.com", name: nil))
        draft.imported = RecipeImportResponse(importId: UUID(), globalRecipeId: nil, alreadyExists: false, normalizedUrl: preview.source.normalizedUrl, recipe: preview)
        let imported = try json(SaveCommunityParams(draft: draft))
        assert(imported["requested_image_url"] as? String == preview.imageUrl)
        assert(imported["requested_source_type"] as? String == "url")
        let savedID = UUID()
        let retry = try json(SaveMealParams(homeId: homeID, mealId: savedID, draft: draft, photoPath: "homes/test/meals/test/photo.jpg"))
        assert(retry["requested_meal_id"] as? String == savedID.uuidString)
        assert(retry["requested_primary_photo_path"] as? String == "homes/test/meals/test/photo.jpg")
        // Editing must retain metadata, structured fields, the original ID and photo.
        let meal = HomeyMeal(id: savedID, homeId: homeID, name: "Family pasta", description: "Sunday dinner", mealTypes: [.dinner, .lunch], cuisine: "Italian", difficulty: .medium, prepTimeMinutes: 12, cookTimeMinutes: 25, servings: 4, primaryPhotoPath: "homes/existing.jpg", sourceName: "Family", sourceURL: "https://example.com/family", sourceType: "manual", originGlobalRecipeId: nil, globalRecipeId: nil, notes: "Keep warm", tags: ["family", "pasta"], isArchived: false, createdBy: UUID(), createdAt: Date(), updatedAt: Date())
        let storedIngredient = RecipeIngredient(id: UUID(), recipeId: UUID(), sectionName: "Sauce", ingredientName: "Garlic", unit: "cloves", preparation: "Minced", notes: "Fresh", quantity: 3, sortOrder: 1, isOptional: true)
        let storedStep = RecipeStep(id: UUID(), recipeId: UUID(), instruction: "Simmer gently", stepNumber: 1, timerMinutes: 25)
        var edit = RecipeDraft(detail: HomeyRecipeDetail(meal: meal, ingredients: [storedIngredient], steps: [storedStep]))
        assert(edit.name == meal.name && edit.description == meal.description && edit.sourceName == meal.sourceName)
        assert(edit.sourceURL == meal.sourceURL && edit.notes == meal.notes && edit.tagsText == "family, pasta")
        assert(edit.prepMinutes == 12 && edit.cookMinutes == 25 && edit.servings == 4 && edit.difficulty == .medium)
        assert(edit.mealTypes == [.dinner, .lunch] && !edit.shareWithCommunity)
        assert(edit.ingredients[0].preparation == "Minced" && edit.ingredients[0].notes == "Fresh" && edit.ingredients[0].optional)
        assert(edit.steps[0].timerMinutes == 25)
        edit.name = "Updated pasta"
        edit.mealTypes = [.dinner]
        edit.sourceName = "Family book"
        edit.ingredients[0].quantity = "4"
        edit.steps[0].text = "Simmer and stir"
        let update = try json(SaveMealParams(homeId: homeID, mealId: meal.id, draft: edit, photoPath: meal.primaryPhotoPath))
        assert(update["requested_meal_id"] as? String == savedID.uuidString)
        assert(update["requested_primary_photo_path"] as? String == meal.primaryPhotoPath)
        assert(update["requested_name"] as? String == "Updated pasta")
        assert(update["requested_source_name"] as? String == "Family book")
        assert(RecipeDraft().shareWithCommunity, "Create retains default ON")
        edit.shareWithCommunity = true
        let toggleOn = try json(SaveMealParams(homeId: homeID, mealId: nil, draft: edit))
        edit.shareWithCommunity = false
        let toggleOff = try json(SaveMealParams(homeId: homeID, mealId: nil, draft: edit))
        assert(NSDictionary(dictionary: toggleOn).isEqual(to: toggleOff), "Community toggle never conditions Home saving")
        let photoID = UUID(uuidString: "ABCDEFAB-1234-5678-ABCD-ABCDEFABCDEF")!
        let photoPath = RecipeImageStoragePath.make(homeId: homeID, mealId: savedID, photoId: photoID)
        assert(photoPath == "\(homeID.uuidString.lowercased())/\(savedID.uuidString.lowercased())/abcdefab-1234-5678-abcd-abcdefabcdef.jpg")
        assert(photoPath.split(separator: "/").count == 3, "iPad Storage contract has no homes/meals literal folders")
        assert(RecipeImportInput.validURL("  https://example.com/recipe  ") == "https://example.com/recipe")
        assert(RecipeImportInput.validURL("") == nil)
        assert(RecipeImportInput.validURL("https://") == nil)
        assert(RecipeImportInput.validURL("file:///tmp/recipe") == nil)
        assert(RecipeImportInput.validURL("not a URL") == nil)
        assert(RecipeImportInput.safeLogURL("https://user:secret@example.com/recipe?token=secret#private") == "https://example.com/recipe")
        assert(RecipeImportInput.errorCode(data: Data("{\"error\":{\"code\":\"SOURCE_BLOCKED\"}}".utf8)) == "SOURCE_BLOCKED")
        assert(RecipeImportInput.message(for: "SOURCE_BLOCKED").contains("doesn't currently allow"))
        var importedDraft = RecipeDraft()
        importedDraft.apply(draft.imported!)
        assert(importedDraft.name == preview.title && importedDraft.sourceURL == preview.source.originalUrl)
        assert(importedDraft.imported?.normalizedUrl == preview.source.normalizedUrl)
        assert(importedDraft.importImageURL == preview.imageUrl)
        importedDraft.importedImageRemoved = true
        assert(importedDraft.importImageURL == nil && importedDraft.imported != nil)
        let removedPhotoPayload = try json(SaveCommunityParams(draft: importedDraft))
        assert(removedPhotoPayload["requested_image_url"] is NSNull)
        assert(RecipeImageReference(photoPath) == .storage(photoPath))
        assert(RecipeImageReference("  https://example.com/photo.jpg  ") == .remote(URL(string: "https://example.com/photo.jpg")!))
        assert(RecipeImageReference(nil) == nil && RecipeImageReference("") == nil)
        assert(RecipeImageReference("file:///tmp/photo.jpg") == nil)
        assert(RecipeImageReference("../photo.jpg") == nil)
        assert(RecipeImageReference.safeLog("https://example.com/photo.jpg?token=secret") == "https://example.com/photo.jpg")
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        struct LegacyResponse: Decodable {
            struct Recipe: Decodable { let ingredients: [CommunityIngredient] }
            let recipe: Recipe
        }
        do {
            _ = try JSONDecoder().decode(LegacyResponse.self, from: fixtureData)
            fatalError("Legacy database DTO should reject camelCase import ingredients")
        } catch let error as DecodingError {
            let details = RecipeImportDiagnostics.decodingDetails(error)
            assert(details.contains("DecodingError.keyNotFound"))
            assert(details.contains("missingKey=sort_order"))
            assert(details.contains("codingPath=recipe.ingredients[0]"))
            print("REPRODUCED old decoder: " + details.joined(separator: "; "))
        }
        let parsed = try RecipeImportResponseDecoder.decode(fixtureData)
        assert(parsed.recipe.title == "Sheet Pan Pancakes From Mix")
        assert(parsed.recipe.imageUrl?.isEmpty == false)
        assert(parsed.recipe.ingredients.count == 6 && parsed.recipe.steps.count == 6)
        var mapped = RecipeDraft()
        mapped.apply(parsed)
        assert(mapped.ingredients.count == 6 && mapped.steps.count == 6 && mapped.importImageURL != nil)
        assert(mapped.sourceURL == "https://www.frontrangefed.com/sheet-pan-pancakes-from-mix/")
        var sparse = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
        var sparseRecipe = sparse["recipe"] as! [String: Any]
        for key in ["imageUrl", "description", "servings", "prepTimeMinutes", "cookTimeMinutes", "totalTimeMinutes", "cuisine"] { sparseRecipe.removeValue(forKey: key) }
        sparse["recipe"] = sparseRecipe
        let sparseResult = try RecipeImportResponseDecoder.decode(JSONSerialization.data(withJSONObject: sparse))
        assert(sparseResult.recipe.imageUrl == nil && sparseResult.recipe.servings == nil && sparseResult.recipe.ingredients.count == 6)
        let blocked = Data("{\"error\":{\"code\":\"SOURCE_BLOCKED\",\"message\":\"blocked\"}}".utf8)
        do { _ = try RecipeImportResponseDecoder.decode(blocked); fatalError("Error envelope decoded as a recipe") }
        catch let error as RecipeImportResponseError { assert(error.code == "SOURCE_BLOCKED") }
        assert(!RecipeImportInput.message(for: "RESPONSE_DECODING_ERROR").contains("connection"))
        let secretBody = Data("{\"access_token\":\"SECRET\",\"imageUrl\":\"https://example.com/p.jpg?token=SECRET\"}".utf8)
        assert(!RecipeImportDiagnostics.sanitizedJSON(secretBody).contains("SECRET"))
        print("PASS: exact Front Range Fed parser output, six ingredients/six directions, optional metadata, error envelope, redaction")
        print("PASS: iPad RPC argument shapes with deployed Community source types, numeric/fraction quantities, imported image/source metadata, retry meal ID and photo path; edit prefill, metadata retention, and community-independent Home payload; iPad image object path")
    }
}
