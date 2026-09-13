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
        let parsedMilk = WebsiteIngredientParser.parse("1 1/4 cups milk")
        assert(parsedMilk.quantity == Decimal(string: "1.25") && parsedMilk.unit == "cups" && parsedMilk.ingredientName == "milk" && parsedMilk.preparation == nil)
        let parsedEgg = WebsiteIngredientParser.parse("1 egg")
        assert(parsedEgg.quantity == 1 && parsedEgg.unit == nil && parsedEgg.ingredientName == "egg")
        let parsedButter = WebsiteIngredientParser.parse("3 tablespoons melted butter")
        assert(parsedButter.quantity == 3 && parsedButter.unit == "tablespoons" && parsedButter.ingredientName == "butter" && parsedButter.preparation == "melted")
        let parsedFlour = WebsiteIngredientParser.parse("1 1/2 cups all-purpose flour")
        assert(parsedFlour.quantity == Decimal(string: "1.5") && parsedFlour.unit == "cups" && parsedFlour.ingredientName == "all-purpose flour")
        let parsedChips = WebsiteIngredientParser.parse("1/3 cup chocolate chips")
        assert(parsedChips.quantity != nil && parsedChips.unit == "cup" && parsedChips.ingredientName == "chocolate chips")
        let parsedUnicode = WebsiteIngredientParser.parse("2½ cups milk")
        assert(parsedUnicode.quantity == Decimal(string: "2.5") && parsedUnicode.ingredientName == "milk")
        let optionalIngredient = WebsiteIngredientParser.parse("Optional: 1/2 Cup ricotta cheese")
        assert(optionalIngredient.safety == .safe && optionalIngredient.isOptional && optionalIngredient.quantity == Decimal(string: "0.5") && optionalIngredient.unit == "cup" && optionalIngredient.ingredientName == "ricotta cheese")
        let optionalSuffix = WebsiteIngredientParser.parse("1 tbsp brown sugar (optional)")
        assert(optionalSuffix.safety == .safe && optionalSuffix.isOptional && optionalSuffix.ingredientName == "brown sugar")
        assert(WebsiteIngredientParser.parse("1 to 2 fresh strawberries").safety == .needsReview)
        assert(WebsiteIngredientParser.parse("8-10 slices bacon").safety == .needsReview)
        assert(WebsiteIngredientParser.parse("4 tablespoons (1/2 stick) unsalted butter").safety == .needsReview)
        assert(WebsiteIngredientParser.parse("Kosher salt").safety == .alreadyValid)
        assert(WebsiteIngredientParser.parse("6 large eggs").safety == .safe)
        assert(WebsiteIngredientParser.parse("2 tablespoons plus 2 teaspoons water").safety == .needsReview)
        assert(WebsiteIngredientParser.parse("2 tablespoons rice vinegar or 3 tablespoons apple cider vinegar").safety == .needsReview)
        let mushrooms = WebsiteIngredientParser.parse("8 ounces cremini mushrooms, sliced 1/4-inch thick")
        assert(mushrooms.ingredientName == "cremini mushrooms" && mushrooms.preparation == "sliced 1/4-inch thick")
        let onions = WebsiteIngredientParser.parse("2 green onions (, chopped, for garnish)")
        assert(onions.ingredientName == "green onions" && onions.preparation == "chopped, for garnish")
        assert(CommunityIngredientQuantityFormatter.string(quantity: Decimal(string: "0.5"), unit: "teaspoon") == "0.5 teaspoon")
        let structuredPreview = ImportedRecipePreview(
            title: "Imported pancakes", description: nil, imageUrl: nil,
            prepTimeMinutes: nil, cookTimeMinutes: nil, totalTimeMinutes: nil,
            servings: nil, cuisine: nil, mealTypes: [], keywords: [],
            ingredients: [
                .init(sectionName: nil, ingredientName: "1 1/4 cups milk", quantity: nil, isOptional: false, sortOrder: 0),
                .init(sectionName: nil, ingredientName: "1 egg", quantity: nil, isOptional: false, sortOrder: 1),
                .init(sectionName: nil, ingredientName: "3 tablespoons melted butter", quantity: nil, isOptional: false, sortOrder: 2)
            ],
            steps: [],
            source: .init(originalUrl: "https://example.com/pancakes", normalizedUrl: "https://example.com/pancakes", domain: "example.com", name: nil)
        )
        var structuredDraft = RecipeDraft()
        structuredDraft.apply(.init(importId: UUID(), globalRecipeId: nil, alreadyExists: false, normalizedUrl: structuredPreview.source.normalizedUrl, recipe: structuredPreview))
        let structuredPayload = try json(SaveMealParams(homeId: homeID, mealId: nil, draft: structuredDraft))
        let structuredRows = structuredPayload["requested_ingredients"] as! [[String: Any]]
        assert(structuredRows[0]["ingredient_name"] as? String == "milk")
        assert((structuredRows[0]["quantity"] as? NSNumber)?.doubleValue == 1.25)
        assert(structuredRows[0]["unit"] as? String == "cups")
        assert(structuredRows[1]["ingredient_name"] as? String == "egg")
        assert((structuredRows[1]["quantity"] as? NSNumber)?.doubleValue == 1)
        assert(structuredRows[2]["ingredient_name"] as? String == "butter")
        assert((structuredRows[2]["quantity"] as? NSNumber)?.doubleValue == 3)
        assert(structuredRows[2]["unit"] as? String == "tablespoons")
        assert(structuredRows[2]["preparation"] as? String == "melted")
        let structuredCommunity = try json(SaveCommunityParams(draft: structuredDraft))
        let communityRows = structuredCommunity["requested_ingredients"] as! [[String: Any]]
        assert(communityRows[0]["ingredient_name"] as? String == "milk")
        assert(communityRows[0]["quantity"] as? String == "1.25 cups")
        assert(communityRows[1]["ingredient_name"] as? String == "egg")
        assert(communityRows[1]["quantity"] as? String == "1")
        assert(communityRows[2]["ingredient_name"] as? String == "butter")
        assert(communityRows[2]["quantity"] as? String == "3 tablespoons")
        let preview = ImportedRecipePreview(title: draft.name, description: nil, imageUrl: "https://example.com/recipe.jpg", prepTimeMinutes: nil, cookTimeMinutes: nil, totalTimeMinutes: nil, servings: nil, cuisine: nil, mealTypes: ["dessert"], keywords: ["cake"], ingredients: [], steps: [], source: ImportedRecipeSource(originalUrl: "https://example.com/recipe", normalizedUrl: "https://example.com/recipe", domain: "example.com", name: nil))
        draft.imported = RecipeImportResponse(importId: UUID(), globalRecipeId: nil, alreadyExists: false, normalizedUrl: preview.source.normalizedUrl, recipe: preview)
        let imported = try json(SaveCommunityParams(draft: draft))
        assert(imported["requested_image_url"] as? String == preview.imageUrl)
        assert(imported["requested_source_type"] as? String == "url")
        let durableCommunity = try json(SaveCommunityParams(draft: draft, imageURL: "home/photo/path.jpg"))
        assert(durableCommunity["requested_image_url"] as? String == "home/photo/path.jpg")
        assert(CommunityRecipeDuplicateClassifier.isDuplicate(code: "23505", message: "duplicate key value violates unique constraint", details: nil))
        assert(CommunityRecipeDuplicateClassifier.isDuplicate(code: "P0001", message: "Recipe already exists", details: nil))
        assert(!CommunityRecipeDuplicateClassifier.isDuplicate(code: "42501", message: "permission denied", details: nil))
        assert(!CommunityRecipeDuplicateClassifier.isDuplicate(code: "23514", message: "check constraint failed", details: nil))
        assert(!CommunityRecipeDuplicateClassifier.isDuplicate(code: "P0001", message: "unexpected server failure", details: nil))
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
