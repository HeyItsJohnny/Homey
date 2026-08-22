import Combine
import Foundation
import PostgREST
import SwiftUI
import UIKit

@MainActor
final class MealEditorViewModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    @Published var selectedMealTypes: [MealType] = []
    @Published var prepTimeText = ""
    @Published var cookTimeText = ""
    @Published var servingsText = ""
    @Published var difficulty: MealDifficulty?
    @Published var cuisine = ""
    @Published var tags: [String] = []
    @Published var notes = ""
    @Published var sourceName = ""
    @Published var sourceURLText = ""
    @Published var existingPhotoPath: String?
    @Published var existingPhotoURL: URL?
    @Published var selectedPhotoData: Data?
    @Published var selectedPhotoImage: UIImage?
    @Published private(set) var isProcessingPhoto = false
    @Published var ingredients: [MealEditorIngredient] = []
    @Published var steps: [MealEditorStep] = []
    @Published var isDraft = true
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var validationErrors: [MealEditorValidationError] = []
    @Published var addToHomeRecipes = true
    @Published var shareWithCommunity = true

    let mode: MealEditorMode
    private let mealService: MealServicing
    private let globalMealsService: GlobalMealsServicing
    private var initialDraft = MealEditorDraft()
    private var loadedMealID: UUID?
    private var persistedMealID: UUID?
    private var selectedPhotoSource: MealEditorSelectedPhotoSource?
    private var initialAddToHomeRecipes = true
    private var initialShareWithCommunity = true
    private var committedGlobalRecipeId: UUID?

    init(mode: MealEditorMode, saveDestination: RecipeSaveDestination = .home, mealService: MealServicing? = nil, globalMealsService: GlobalMealsServicing? = nil) {
        self.mode = mode
        self.mealService = mealService ?? MealService()
        self.globalMealsService = globalMealsService ?? GlobalMealsService()
        persistedMealID = mode.mealID
        switch mode {
        case .create, .imported:
            addToHomeRecipes = saveDestination != .community
            shareWithCommunity = true
        case .edit:
            addToHomeRecipes = true
            shareWithCommunity = false
        }
        if let importedResponse = mode.importedResponse {
            applyImportedResponse(importedResponse)
        } else {
            ingredients = [MealEditorIngredient(sortOrder: 1)]
            steps = [MealEditorStep(stepNumber: 1)]
        }
        captureInitialDraft()
    }

    var title: String {
        if persistedMealID != nil {
            return "Edit Meal"
        }

        switch mode {
        case .create, .imported:
            return "Create Meal"
        case .edit:
            return "Edit Meal"
        }
    }

    var subtitle: String {
        if persistedMealID != nil {
            return "Make changes to your recipe."
        }

        switch mode {
        case .create, .imported:
            return "Add a meal and recipe to your family's shared library."
        case .edit:
            return "Make changes to your recipe."
        }
    }

    var hasUnsavedChanges: Bool {
        buildDraft() != initialDraft
            || selectedPhotoData != nil
            || addToHomeRecipes != initialAddToHomeRecipes
            || shareWithCommunity != initialShareWithCommunity
    }

    var hasPhoto: Bool {
        selectedPhotoImage != nil || existingPhotoPath != nil || existingPhotoURL != nil
    }

    var isCreatingNewMeal: Bool {
        persistedMealID == nil && mode.mealID == nil
    }

    var showsDestinationControls: Bool {
        isCreatingNewMeal
    }

    var hasSelectedSaveDestination: Bool {
        !showsDestinationControls || addToHomeRecipes || shareWithCommunity
    }

    private var permissionDeniedMessage: String {
        isCreatingNewMeal
            ? "You do not have permission to create meals in this Home."
            : "You do not have permission to edit meals in this Home."
    }

    func loadMealIfNeeded(homeId: UUID?) async {
        guard case .edit(let mealID) = mode else { return }
        guard loadedMealID != mealID else { return }
        guard homeId != nil else {
            errorMessage = "Choose a Home before editing this meal."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            logLoadDiagnostic(operation: "fetch meal", homeId: homeId, mealId: mealID)
            let meal = try await mealService.fetchMeal(id: mealID)

            logLoadDiagnostic(operation: "fetch meal recipe details", homeId: homeId, mealId: mealID)
            let recipeDetails = try await mealService.fetchRecipe(mealId: mealID)

            guard !Task.isCancelled else { return }
            logLoadDiagnostic(operation: "map database models into MealEditorDraft", homeId: homeId, mealId: mealID, recipeId: recipeDetails.recipe?.id)
            apply(meal: meal, recipeDetails: recipeDetails)
            loadedMealID = mealID
            persistedMealID = mealID
            captureInitialDraft()

            if let path = existingPhotoPath {
                do {
                    logLoadDiagnostic(operation: "fetch signed meal photo URL", homeId: homeId, mealId: mealID, recipeId: recipeDetails.recipe?.id)
                    existingPhotoURL = try await mealService.createSignedMealPhotoURL(path: path)
                } catch {
                    existingPhotoURL = nil
                    logLoadDiagnostic(
                        error: error,
                        operation: "fetch signed meal photo URL",
                        homeId: homeId,
                        mealId: mealID,
                        recipeId: recipeDetails.recipe?.id
                    )
                }
            }
        } catch {
            logLoadDiagnostic(error: error, operation: "loadMealIfNeeded", homeId: homeId, mealId: mealID)
            errorMessage = error.localizedDescription
        }
    }

    func retry(homeId: UUID?) async {
        loadedMealID = nil
        await loadMealIfNeeded(homeId: homeId)
    }

    func validateForDraft(permissions: HomePermissions) -> Bool {
        validationErrors = baseValidationErrors(permissions: permissions, requiresCompleteRecipe: false)
        return validationErrors.isEmpty
    }

    func validateForPublish(permissions: HomePermissions) -> Bool {
        validationErrors = baseValidationErrors(permissions: permissions, requiresCompleteRecipe: true)
        return validationErrors.isEmpty
    }

    func saveDraft(homeId: UUID?, permissions: HomePermissions) async -> MealEditorSaveResult {
        guard !showsDestinationControls || addToHomeRecipes else {
            validationErrors = [MealEditorValidationError(field: .destination, message: "Drafts can only be saved to Home Recipes.")]
            return .failed
        }

        guard validateForDraft(permissions: permissions), let homeId else {
            if homeId == nil {
                validationErrors.append(MealEditorValidationError(field: .permission, message: "Choose a Home before saving."))
            }
            logSaveDiagnostic(
                error: nil,
                operation: "saveDraft_validation",
                homeId: homeId,
                mealId: mode.mealID,
                isDraft: true
            )
            return .failed
        }
        return await save(homeId: homeId, permissions: permissions, saveAsDraft: true)
    }

    func saveMeal(homeId: UUID?, permissions: HomePermissions) async -> MealEditorSaveResult {
        if showsDestinationControls && !hasSelectedSaveDestination {
            validationErrors = [MealEditorValidationError(field: .destination, message: "Choose at least one place to save this recipe.")]
            return .failed
        }

        if showsDestinationControls && shareWithCommunity && !addToHomeRecipes {
            return await saveCommunityRecipe()
        }

        guard validateForPublish(permissions: permissions), let homeId, addToHomeRecipes || !showsDestinationControls else {
            if homeId == nil {
                validationErrors.append(MealEditorValidationError(field: .permission, message: "Choose a Home before saving."))
            }
            logSaveDiagnostic(
                error: nil,
                operation: "saveMeal_validation",
                homeId: homeId,
                mealId: mode.mealID,
                isDraft: false
            )
            return .failed
        }
        return await save(homeId: homeId, permissions: permissions, saveAsDraft: false)
    }

    func saveCommunityRecipe() async -> MealEditorSaveResult {
        if showsDestinationControls && !hasSelectedSaveDestination {
            validationErrors = [MealEditorValidationError(field: .destination, message: "Choose at least one place to save this recipe.")]
            return .failed
        }

        guard validateForCommunityPublish() else {
            logSaveDiagnostic(
                error: nil,
                operation: "saveCommunityRecipe_validation",
                homeId: nil,
                mealId: nil,
                isDraft: false
            )
            return .failed
        }

        guard !isSaving else { return .failed }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let draft = buildDraft()
            let globalRecipeId = try await globalMealsService.saveCommunityRecipe(draft: draft)
            apply(draft: draft)
            existingPhotoPath = nil
            selectedPhotoData = nil
            selectedPhotoSource = nil
            isDraft = false
            persistedMealID = nil
            loadedMealID = nil
            captureInitialDraft()
            successMessage = nil
            return .saved(mealID: globalRecipeId, meal: nil, globalRecipeID: globalRecipeId)
        } catch {
            let draft = buildDraft()
            logSaveDiagnostic(
                error: error,
                operation: "saveCommunityRecipe",
                homeId: nil,
                mealId: nil,
                isDraft: false,
                draft: draft
            )
            if errorMessage == nil {
                errorMessage = "Homey couldn't save this community recipe."
            }
            return .failed
        }
    }

    func uploadPhotoIfNeeded(homeId: UUID, mealId: UUID) async throws -> MealPhoto? {
        guard let selectedPhotoData else { return nil }
        do {
            logPhotoDiagnostic(
                operation: "meal_photo_upload_started",
                homeId: homeId,
                mealId: mealId,
                byteCount: selectedPhotoData.count
            )
            return try await mealService.uploadMealPhoto(homeId: homeId, mealId: mealId, imageData: selectedPhotoData, fileExtension: "jpg")
        } catch {
            logSaveDiagnostic(
                error: error,
                operation: "uploadPhotoIfNeeded",
                homeId: homeId,
                mealId: mealId,
                isDraft: nil
            )
            throw error
        }
    }

    func buildIngredientsJSON() throws -> [SaveMealRecipeIngredient] {
        try ingredients.enumerated().compactMap { index, ingredient in
            let name = ingredient.name.trimmed
            let hasContent = !name.isEmpty || !ingredient.quantityText.trimmed.isEmpty || !ingredient.unit.trimmed.isEmpty || !ingredient.preparation.trimmed.isEmpty || !ingredient.notes.trimmed.isEmpty
            guard hasContent else { return nil }
            guard !name.isEmpty else { throw MealServiceError.emptyIngredientName }
            return SaveMealRecipeIngredient(
                sectionName: ingredient.sectionName.nilIfTrimmedEmpty,
                ingredientName: name,
                quantity: try MealService.decimalFromQuantityText(ingredient.quantityText),
                unit: ingredient.unit.nilIfTrimmedEmpty,
                preparation: ingredient.preparation.nilIfTrimmedEmpty,
                notes: ingredient.notes.nilIfTrimmedEmpty,
                sortOrder: index + 1,
                isOptional: ingredient.isOptional
            )
        }
    }

    func buildStepsJSON() throws -> [SaveMealRecipeStep] {
        try steps.enumerated().compactMap { index, step in
            let instruction = step.instruction.trimmed
            let timerText = step.timerMinutesText.trimmed
            guard !instruction.isEmpty || !timerText.isEmpty else { return nil }
            guard !instruction.isEmpty else { throw MealServiceError.emptyRecipeStep }
            let timerMinutes = try optionalInt(timerText, field: .steps)
            return SaveMealRecipeStep(stepNumber: index + 1, instruction: instruction, timerMinutes: timerMinutes, photoPath: step.photoPath)
        }
    }

    func discardChanges() {
        apply(draft: initialDraft)
        addToHomeRecipes = initialAddToHomeRecipes
        shareWithCommunity = initialShareWithCommunity
        selectedPhotoData = nil
        selectedPhotoImage = nil
        selectedPhotoSource = nil
        validationErrors = []
        errorMessage = nil
    }

    func setPhotoData(_ data: Data) async {
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }

        do {
            let processedPhoto = try processedJPEGPhoto(from: data)
            selectedPhotoData = processedPhoto.data
            selectedPhotoImage = processedPhoto.image
            selectedPhotoSource = .userSelected
            validationErrors.removeAll { $0.field == .photo }
            logPhotoDiagnostic(
                operation: "meal_photo_processed",
                homeId: nil,
                mealId: persistedMealID,
                originalPixelSize: processedPhoto.originalPixelSize,
                resizedPixelSize: processedPhoto.resizedPixelSize,
                originalByteCount: processedPhoto.originalByteCount,
                byteCount: processedPhoto.data.count
            )
        } catch {
            selectedPhotoData = nil
            selectedPhotoImage = nil
            selectedPhotoSource = nil
            validationErrors.append(MealEditorValidationError(field: .photo, message: "We could not prepare that photo. Please choose another image."))
            logSaveDiagnostic(
                error: error,
                operation: "photo_selection_processing",
                homeId: nil,
                mealId: persistedMealID,
                isDraft: nil
            )
        }
    }

    func removePhoto() {
        existingPhotoPath = nil
        existingPhotoURL = nil
        selectedPhotoData = nil
        selectedPhotoImage = nil
        selectedPhotoSource = nil
        isProcessingPhoto = false
    }

    func toggleMealType(_ mealType: MealType) {
        if selectedMealTypes.contains(mealType) {
            selectedMealTypes.removeAll { $0 == mealType }
        } else {
            selectedMealTypes.append(mealType)
        }
    }

    func addTag(_ value: String) {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmedValue) == .orderedSame }) else { return }
        tags.append(trimmedValue)
        tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    func addIngredient(sectionName: String = "Ingredients") {
        ingredients.append(MealEditorIngredient(sectionName: sectionName, sortOrder: ingredients.count + 1))
    }

    func duplicateIngredient(_ ingredient: MealEditorIngredient) {
        var copy = ingredient
        copy = MealEditorIngredient(
            sectionName: ingredient.sectionName,
            name: ingredient.name,
            quantityText: ingredient.quantityText,
            unit: ingredient.unit,
            preparation: ingredient.preparation,
            notes: ingredient.notes,
            isOptional: ingredient.isOptional,
            sortOrder: ingredients.count + 1
        )
        ingredients.append(copy)
    }

    func deleteIngredient(_ ingredient: MealEditorIngredient) {
        ingredients.removeAll { $0.id == ingredient.id }
        if ingredients.isEmpty { addIngredient() }
        renumberIngredients()
    }

    func moveIngredients(from source: IndexSet, to destination: Int) {
        ingredients.move(fromOffsets: source, toOffset: destination)
        renumberIngredients()
    }

    func addStep() {
        steps.append(MealEditorStep(stepNumber: steps.count + 1))
    }

    func duplicateStep(_ step: MealEditorStep) {
        steps.append(MealEditorStep(instruction: step.instruction, timerMinutesText: step.timerMinutesText, photoPath: step.photoPath, stepNumber: steps.count + 1))
    }

    func deleteStep(_ step: MealEditorStep) {
        steps.removeAll { $0.id == step.id }
        if steps.isEmpty { addStep() }
        renumberSteps()
    }

    func moveSteps(from source: IndexSet, to destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
        renumberSteps()
    }

    func validationMessage(for field: MealEditorValidationField) -> String? {
        validationErrors.first(where: { $0.field == field })?.message
    }

    private func save(homeId: UUID, permissions: HomePermissions, saveAsDraft: Bool) async -> MealEditorSaveResult {
        guard !isSaving else { return .failed }
        let canSave = isCreatingNewMeal ? permissions.meals.canCreate : permissions.meals.canEdit
        guard canSave else {
            validationErrors = [MealEditorValidationError(field: .permission, message: permissionDeniedMessage)]
            return .failed
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var draft = buildDraft()
            let globalRecipeId = try await commitGlobalRecipeIfNeeded(draft: &draft, saveAsDraft: saveAsDraft)

            let savedMealID: UUID
            if let existingMealID = persistedMealID {
                savedMealID = try await updatePersistedMeal(
                    homeId: homeId,
                    mealId: existingMealID,
                    draft: &draft,
                    saveAsDraft: saveAsDraft
                )
            } else {
                savedMealID = try await createMeal(
                    homeId: homeId,
                    draft: &draft,
                    saveAsDraft: saveAsDraft
                )
            }

            if let importedMetadata = draft.importedMetadata {
                try await mealService.applyImportedRecipeMetadata(
                    homeId: homeId,
                    mealId: savedMealID,
                    metadata: importedMetadata
                )
            } else if let globalRecipeId {
                try await mealService.linkMealToGlobalRecipe(
                    homeId: homeId,
                    mealId: savedMealID,
                    globalRecipeId: globalRecipeId
                )
            }

            apply(draft: draft)
            existingPhotoPath = draft.primaryPhotoPath
            selectedPhotoData = nil
            selectedPhotoSource = nil
            isDraft = saveAsDraft
            persistedMealID = savedMealID
            loadedMealID = savedMealID
            captureInitialDraft()
            let savedMeal = await fetchSavedMealAfterSave(mealID: savedMealID)
            if saveAsDraft {
                successMessage = "Draft saved."
                UIAccessibility.post(notification: .announcement, argument: successMessage)
            } else {
                successMessage = nil
            }
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            return .saved(mealID: savedMealID, meal: savedMeal, globalRecipeID: globalRecipeId)
        } catch {
            let draft = buildDraft()
            logSaveDiagnostic(
                error: error,
                operation: saveAsDraft ? "saveDraft" : "saveMeal",
                homeId: homeId,
                mealId: persistedMealID,
                isDraft: saveAsDraft,
                draft: draft
            )
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
            return .failed
        }
    }

    private func createMeal(homeId: UUID, draft: inout MealEditorDraft, saveAsDraft: Bool) async throws -> UUID {
        if let importedMetadata = draft.importedMetadata,
           let globalRecipeId = importedMetadata.globalRecipeId,
           try await mealService.fetchImportedMeal(homeId: homeId, globalRecipeId: globalRecipeId) != nil {
            throw MealServiceError.duplicateImportedRecipe
        }

        await prepareImportedSourcePhotoIfNeeded()
        draft = buildDraft()

        let selectedPhotoData = selectedPhotoData
        if selectedPhotoData != nil {
            draft.primaryPhotoPath = nil
        }

        let createdMealID = try await mealService.saveMealRecipe(
            homeId: homeId,
            mealId: nil,
            draft: draft,
            isDraft: saveAsDraft
        )
        persistedMealID = createdMealID
        loadedMealID = createdMealID

        guard selectedPhotoData != nil else {
            return createdMealID
        }

        do {
            if let uploadedPhoto = try await uploadPhotoIfNeeded(homeId: homeId, mealId: createdMealID) {
                draft.primaryPhotoPath = uploadedPhoto.path
                logPhotoDiagnostic(
                    operation: "primary_photo_path_update_started",
                    homeId: homeId,
                    mealId: createdMealID,
                    path: uploadedPhoto.path,
                    byteCount: selectedPhotoData?.count
                )
                _ = try await mealService.saveMealRecipe(
                    homeId: homeId,
                    mealId: createdMealID,
                    draft: draft,
                    isDraft: saveAsDraft
                )
                logPhotoDiagnostic(
                    operation: "primary_photo_path_update_succeeded",
                    homeId: homeId,
                    mealId: createdMealID,
                    path: uploadedPhoto.path,
                    byteCount: selectedPhotoData?.count
                )
                if selectedPhotoSource == .importedSource {
                    #if DEBUG
                    print("Imported image uploaded successfully")
                    #endif
                }
            }
            return createdMealID
        } catch {
            if selectedPhotoSource == .importedSource {
                let byteCount = selectedPhotoData?.count
                clearImportedSourcePhotoSelection()
                errorMessage = nil
                logPhotoDiagnostic(
                    operation: "imported_image_persistence_failed_saving_without_image",
                    homeId: homeId,
                    mealId: createdMealID,
                    byteCount: byteCount
                )
                return createdMealID
            }

            errorMessage = "Meal saved, but we could not upload the photo. Please try changing the photo and saving again."
            logSaveDiagnostic(
                error: error,
                operation: "createMeal_photo_upload_or_update",
                homeId: homeId,
                mealId: createdMealID,
                isDraft: saveAsDraft,
                draft: draft
            )
            throw MealServiceError.uploadPhotoFailed
        }
    }

    private func commitGlobalRecipeIfNeeded(draft: inout MealEditorDraft, saveAsDraft: Bool) async throws -> UUID? {
        guard !saveAsDraft,
              shareWithCommunity else {
            return nil
        }

        if let globalRecipeId = draft.importedMetadata?.globalRecipeId {
            return globalRecipeId
        }

        if let committedGlobalRecipeId {
            return committedGlobalRecipeId
        }

        let globalRecipeId = try await globalMealsService.saveCommunityRecipe(draft: draft)
        committedGlobalRecipeId = globalRecipeId
        if let importedMetadata = draft.importedMetadata {
            let committedMetadata = importedMetadata.committed(globalRecipeId: globalRecipeId)
            draft.importedMetadata = committedMetadata
            initialDraft.importedMetadata = committedMetadata
        }

        #if DEBUG
        print("Home recipe committed to global recipe after review")
        print("global_recipe_id: \(globalRecipeId.uuidString)")
        print("home_recipe_created: pending")
        #endif

        return globalRecipeId
    }

    private func prepareImportedSourcePhotoIfNeeded() async {
        guard mode.importedResponse != nil,
              selectedPhotoData == nil,
              existingPhotoPath == nil,
              let sourceImageURL = existingPhotoURL else {
            return
        }

        do {
            #if DEBUG
            print("Imported recipe has source image URL")
            print("Downloading imported recipe image")
            #endif

            let imageData = try await downloadImportedSourceImage(from: sourceImageURL)
            let processedPhoto = try processedJPEGPhoto(from: imageData)
            selectedPhotoData = processedPhoto.data
            selectedPhotoImage = processedPhoto.image
            selectedPhotoSource = .importedSource

            logPhotoDiagnostic(
                operation: "imported_image_download_processed",
                homeId: nil,
                mealId: persistedMealID,
                originalPixelSize: processedPhoto.originalPixelSize,
                resizedPixelSize: processedPhoto.resizedPixelSize,
                originalByteCount: processedPhoto.originalByteCount,
                byteCount: processedPhoto.data.count
            )

            #if DEBUG
            print("Imported image download succeeded: \(imageData.count) bytes")
            print("Imported image passed to existing meal upload pipeline")
            #endif
        } catch {
            clearImportedSourcePhotoSelection()
            logSaveDiagnostic(
                error: error,
                operation: "imported_image_download_or_processing",
                homeId: nil,
                mealId: persistedMealID,
                isDraft: nil
            )
            #if DEBUG
            print("Imported image persistence failed; saving recipe without image")
            #endif
        }
    }

    private func downloadImportedSourceImage(from url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw MealServiceError.invalidPhotoData
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw MealServiceError.loadPhotoFailed
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.isEmpty || contentType.hasPrefix("image/") else {
            throw MealServiceError.invalidPhotoData
        }

        let maxImageBytes = 12 * 1024 * 1024
        guard !data.isEmpty, data.count <= maxImageBytes else {
            throw MealServiceError.invalidPhotoData
        }

        return data
    }

    private func clearImportedSourcePhotoSelection() {
        guard selectedPhotoSource == .importedSource else { return }
        selectedPhotoData = nil
        selectedPhotoImage = nil
        selectedPhotoSource = nil
    }

    private func updatePersistedMeal(homeId: UUID, mealId: UUID, draft: inout MealEditorDraft, saveAsDraft: Bool) async throws -> UUID {
        var uploadedPhoto: MealPhoto?

        do {
            uploadedPhoto = try await uploadPhotoIfNeeded(homeId: homeId, mealId: mealId)
            if let uploadedPhoto {
                draft.primaryPhotoPath = uploadedPhoto.path
                logPhotoDiagnostic(
                    operation: "primary_photo_path_update_started",
                    homeId: homeId,
                    mealId: mealId,
                    path: uploadedPhoto.path,
                    byteCount: selectedPhotoData?.count
                )
            }
            let savedMealId = try await mealService.saveMealRecipe(homeId: homeId, mealId: mealId, draft: draft, isDraft: saveAsDraft)
            if let uploadedPhoto {
                logPhotoDiagnostic(
                    operation: "primary_photo_path_update_succeeded",
                    homeId: homeId,
                    mealId: mealId,
                    path: uploadedPhoto.path,
                    byteCount: selectedPhotoData?.count
                )
            }
            return savedMealId
        } catch {
            if let uploadedPhoto {
                do {
                    try await mealService.deleteMealPhoto(photo: uploadedPhoto)
                } catch {
                    logSaveDiagnostic(
                        error: error,
                        operation: "save_cleanup_uploaded_photo",
                        homeId: homeId,
                        mealId: mealId,
                        isDraft: saveAsDraft
                    )
                }
            }
            throw error
        }
    }

    private func fetchSavedMealAfterSave(mealID: UUID) async -> Meal? {
        do {
            return try await mealService.fetchMeal(id: mealID)
        } catch {
            logSaveDiagnostic(
                error: error,
                operation: "fetchSavedMealAfterSave",
                homeId: nil,
                mealId: mealID,
                isDraft: nil
            )
            return nil
        }
    }

    private func logSaveDiagnostic(
        error: Error?,
        operation: String,
        homeId: UUID?,
        mealId: UUID?,
        isDraft: Bool?,
        draft: MealEditorDraft? = nil
    ) {
        #if DEBUG
        print("========== MEAL EDITOR SAVE DIAGNOSTIC ==========")
        print("operation: \(operation)")
        print("editor_mode: \(isCreatingNewMeal ? "create" : "edit")")
        print("home_id: \(homeId?.uuidString ?? "nil")")
        print("meal_id: \(mealId?.uuidString ?? "nil")")
        if let isDraft {
            print("is_draft: \(isDraft)")
        }
        if let draft {
            print("draft_name: \(draft.name)")
            print("draft_meal_types: \(draft.mealTypes.map(\.rawValue))")
            print("draft_ingredient_count: \(draft.ingredients.count)")
            print("draft_step_count: \(draft.steps.count)")
            print("draft_has_photo_path: \(draft.primaryPhotoPath != nil)")
            print("draft_tag_count: \(draft.tags.count)")
        }
        if let error {
            print("localizedDescription: \(error.localizedDescription)")
            print(String(reflecting: error))
            if let postgrestError = error as? PostgrestError {
                print("PostgREST code: \(postgrestError.code ?? "")")
                print("PostgREST message: \(postgrestError.message)")
                print("PostgREST detail: \(postgrestError.detail ?? "")")
                print("PostgREST hint: \(postgrestError.hint ?? "")")
            }
        } else {
            print("validation_errors: \(validationErrors.map(\.message))")
        }
        print("=================================================")
        #endif
    }

    private func logPhotoDiagnostic(
        operation: String,
        homeId: UUID?,
        mealId: UUID?,
        path: String? = nil,
        originalPixelSize: CGSize? = nil,
        resizedPixelSize: CGSize? = nil,
        originalByteCount: Int? = nil,
        byteCount: Int? = nil
    ) {
        #if DEBUG
        print("========== MEAL PHOTO DIAGNOSTIC ==========")
        print("operation: \(operation)")
        print("editor_mode: \(isCreatingNewMeal ? "create" : "edit")")
        print("bucket: meal-images")
        print("home_id: \(homeId?.uuidString ?? "nil")")
        print("persisted_meal_id: \(persistedMealID?.uuidString ?? "nil")")
        print("upload_meal_id: \(mealId?.uuidString ?? "nil")")
        if let path { print("path: \(path)") }
        print("file_extension: jpg")
        print("mime_type: image/jpeg")
        if let originalPixelSize {
            print("original_pixels: \(Int(originalPixelSize.width))x\(Int(originalPixelSize.height))")
        }
        if let resizedPixelSize {
            print("resized_pixels: \(Int(resizedPixelSize.width))x\(Int(resizedPixelSize.height))")
        }
        if let originalByteCount {
            print("original_bytes: \(originalByteCount)")
        }
        if let byteCount {
            print("compressed_bytes: \(byteCount)")
        }
        print("===========================================")
        #endif
    }

    private func logLoadDiagnostic(
        error: Error? = nil,
        operation: String,
        homeId: UUID?,
        mealId: UUID,
        recipeId: UUID? = nil
    ) {
        #if DEBUG
        print("========== MEAL EDITOR LOAD DIAGNOSTIC ==========")
        print("operation: \(operation)")
        print("editor_mode: edit")
        print("home_id: \(homeId?.uuidString ?? "nil")")
        print("meal_id: \(mealId.uuidString)")
        if let recipeId {
            print("recipe_id: \(recipeId.uuidString)")
        }
        if let error {
            print("localizedDescription: \(error.localizedDescription)")
            print(String(reflecting: error))
            if let postgrestError = error as? PostgrestError {
                print("PostgREST code: \(postgrestError.code ?? "")")
                print("PostgREST message: \(postgrestError.message)")
                print("PostgREST detail: \(postgrestError.detail ?? "")")
                print("PostgREST hint: \(postgrestError.hint ?? "")")
            }
            logDecodingErrorDetails(error)
        }
        print("=================================================")
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
        @unknown default:
            print("DecodingError: \(String(reflecting: decodingError))")
        }
        #endif
    }

    private func baseValidationErrors(permissions: HomePermissions, requiresCompleteRecipe: Bool) -> [MealEditorValidationError] {
        var errors: [MealEditorValidationError] = []
        let canSave = isCreatingNewMeal ? permissions.meals.canCreate : permissions.meals.canEdit
        if !canSave {
            errors.append(MealEditorValidationError(field: .permission, message: permissionDeniedMessage))
        }
        if name.trimmed.isEmpty {
            errors.append(MealEditorValidationError(field: .name, message: "Meal name is required."))
        } else if name.trimmed.count > 120 {
            errors.append(MealEditorValidationError(field: .name, message: "Use 120 characters or fewer."))
        }
        if requiresCompleteRecipe && selectedMealTypes.isEmpty {
            errors.append(MealEditorValidationError(field: .mealTypes, message: "Choose at least one meal type."))
        }
        validateNonNegativeInt(prepTimeText, field: .prepTime, message: "Prep time cannot be negative.", errors: &errors)
        validateNonNegativeInt(cookTimeText, field: .cookTime, message: "Cook time cannot be negative.", errors: &errors)
        validateServings(errors: &errors)
        validateSourceURL(errors: &errors)
        validateIngredients(errors: &errors)
        validateSteps(errors: &errors)
        return errors
    }

    private func validateForCommunityPublish() -> Bool {
        validationErrors = communityValidationErrors(requiresCompleteRecipe: true)
        return validationErrors.isEmpty
    }

    private func communityValidationErrors(requiresCompleteRecipe: Bool) -> [MealEditorValidationError] {
        var errors: [MealEditorValidationError] = []
        if name.trimmed.isEmpty {
            errors.append(MealEditorValidationError(field: .name, message: "Meal name is required."))
        } else if name.trimmed.count > 120 {
            errors.append(MealEditorValidationError(field: .name, message: "Use 120 characters or fewer."))
        }
        if requiresCompleteRecipe && selectedMealTypes.isEmpty {
            errors.append(MealEditorValidationError(field: .mealTypes, message: "Choose at least one meal type."))
        }
        validateNonNegativeInt(prepTimeText, field: .prepTime, message: "Prep time cannot be negative.", errors: &errors)
        validateNonNegativeInt(cookTimeText, field: .cookTime, message: "Cook time cannot be negative.", errors: &errors)
        validateServings(errors: &errors)
        validateSourceURL(errors: &errors)
        validateIngredients(errors: &errors)
        validateSteps(errors: &errors)
        return errors
    }

    private func validateNonNegativeInt(_ value: String, field: MealEditorValidationField, message: String, errors: inout [MealEditorValidationError]) {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else { return }
        guard let intValue = Int(trimmedValue), intValue >= 0 else {
            errors.append(MealEditorValidationError(field: field, message: message))
            return
        }
    }

    private func validateServings(errors: inout [MealEditorValidationError]) {
        let trimmedValue = servingsText.trimmed
        guard !trimmedValue.isEmpty else { return }
        guard let servings = Decimal(string: trimmedValue, locale: Locale(identifier: "en_US_POSIX")), servings > 0 else {
            errors.append(MealEditorValidationError(field: .servings, message: "Servings must be greater than zero."))
            return
        }
    }

    private func validateSourceURL(errors: inout [MealEditorValidationError]) {
        let trimmedValue = sourceURLText.trimmed
        guard !trimmedValue.isEmpty else { return }
        guard let url = URL(string: trimmedValue), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            errors.append(MealEditorValidationError(field: .sourceURL, message: "Enter a valid URL."))
            return
        }
    }

    private func validateIngredients(errors: inout [MealEditorValidationError]) {
        do {
            _ = try buildIngredientsJSON()
        } catch {
            errors.append(MealEditorValidationError(field: .ingredients, message: error.localizedDescription))
        }
    }

    private func validateSteps(errors: inout [MealEditorValidationError]) {
        do {
            _ = try buildStepsJSON()
        } catch {
            errors.append(MealEditorValidationError(field: .steps, message: error.localizedDescription))
        }
    }

    private func buildDraft() -> MealEditorDraft {
        MealEditorDraft(
            name: name.trimmed,
            description: description.trimmed,
            mealTypes: selectedMealTypes,
            cuisine: cuisine.trimmed,
            difficulty: difficulty,
            prepTimeMinutes: Int(prepTimeText.trimmed),
            cookTimeMinutes: Int(cookTimeText.trimmed),
            servings: Decimal(string: servingsText.trimmed, locale: Locale(identifier: "en_US_POSIX")),
            primaryPhotoPath: existingPhotoPath,
            sourceName: sourceName.trimmed,
            sourceURL: sourceURLText.trimmed,
            notes: notes.trimmed,
            tags: tags,
            ingredients: ingredients,
            steps: steps,
            importedMetadata: initialDraft.importedMetadata,
            importedImageURL: selectedPhotoData == nil ? existingPhotoURL : nil
        )
    }

    private func apply(meal: Meal, recipeDetails: MealRecipeDetails) {
        name = meal.name
        description = meal.description ?? ""
        selectedMealTypes = meal.mealTypes
        cuisine = meal.cuisine ?? ""
        difficulty = meal.difficulty
        prepTimeText = meal.prepTimeMinutes.map(String.init) ?? ""
        cookTimeText = meal.cookTimeMinutes.map(String.init) ?? ""
        servingsText = meal.servings.map(String.init(describing:)) ?? ""
        existingPhotoPath = meal.primaryPhotoPath
        sourceName = meal.sourceName ?? ""
        sourceURLText = meal.sourceURL ?? ""
        notes = meal.notes ?? recipeDetails.recipe?.notes ?? ""
        tags = meal.tags
        ingredients = recipeDetails.ingredients.enumerated().map { index, ingredient in
            MealEditorIngredient(
                sectionName: ingredient.sectionName ?? "Ingredients",
                name: ingredient.ingredientName,
                quantityText: ingredient.quantity.map(String.init(describing:)) ?? "",
                unit: ingredient.unit ?? "",
                preparation: ingredient.preparation ?? "",
                notes: ingredient.notes ?? "",
                isOptional: ingredient.isOptional,
                sortOrder: index + 1
            )
        }
        if ingredients.isEmpty { addIngredient() }
        steps = recipeDetails.steps.enumerated().map { index, step in
            MealEditorStep(
                instruction: step.instruction,
                timerMinutesText: step.timerMinutes.map(String.init) ?? "",
                photoPath: step.photoPath,
                stepNumber: index + 1
            )
        }
        if steps.isEmpty { addStep() }
    }

    private func applyImportedResponse(_ response: RecipeImportResponse) {
        let metadata = ImportedMealMetadata(
            importId: response.importId,
            globalRecipeId: response.globalRecipeId,
            originalURL: response.recipe.source.originalUrl,
            normalizedURL: response.recipe.source.normalizedUrl,
            sourceDomain: response.recipe.source.domain,
            sourceName: response.recipe.source.name
        )

        name = response.recipe.title
        description = response.recipe.description ?? ""
        selectedMealTypes = response.recipe.mealTypes
        cuisine = response.recipe.cuisine ?? ""
        difficulty = nil
        prepTimeText = response.recipe.prepTimeMinutes.map(String.init) ?? ""
        cookTimeText = response.recipe.cookTimeMinutes.map(String.init) ?? ""
        servingsText = normalizedServingsText(response.recipe.servings)
        existingPhotoPath = nil
        existingPhotoURL = response.recipe.imageUrl.flatMap(URL.init(string:))
        sourceName = metadata.sourceDisplayName
        sourceURLText = metadata.originalURL
        notes = ""
        tags = response.recipe.keywords
        ingredients = response.recipe.ingredients
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, ingredient in
                let quantity = ingredient.quantity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let ingredientName = ingredient.ingredientName.trimmingCharacters(in: .whitespacesAndNewlines)
                let quantityIsDecimal = quantity.isEmpty || (try? MealService.decimalFromQuantityText(quantity)) != nil
                let name = quantityIsDecimal || quantity.isEmpty ? ingredientName : "\(quantity) \(ingredientName)".trimmingCharacters(in: .whitespacesAndNewlines)

                return MealEditorIngredient(
                    sectionName: ingredient.sectionName?.nilIfTrimmedEmpty ?? "Ingredients",
                    name: name,
                    quantityText: quantityIsDecimal ? quantity : "",
                    unit: "",
                    preparation: "",
                    notes: "",
                    isOptional: ingredient.isOptional,
                    sortOrder: index + 1
                )
            }
        if ingredients.isEmpty { addIngredient() }
        steps = response.recipe.steps
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, step in
                let section = step.sectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = step.stepText.trimmingCharacters(in: .whitespacesAndNewlines)
                let instruction = section.isEmpty ? text : "\(section): \(text)"
                return MealEditorStep(instruction: instruction, timerMinutesText: "", stepNumber: index + 1)
            }
        if steps.isEmpty { addStep() }
        initialDraft.importedMetadata = metadata
        initialDraft.importedImageURL = existingPhotoURL
    }

    private func apply(draft: MealEditorDraft) {
        name = draft.name
        description = draft.description
        selectedMealTypes = draft.mealTypes
        cuisine = draft.cuisine
        difficulty = draft.difficulty
        prepTimeText = draft.prepTimeMinutes.map(String.init) ?? ""
        cookTimeText = draft.cookTimeMinutes.map(String.init) ?? ""
        servingsText = draft.servings.map(String.init(describing:)) ?? ""
        existingPhotoPath = draft.primaryPhotoPath
        sourceName = draft.sourceName
        sourceURLText = draft.sourceURL
        notes = draft.notes
        tags = draft.tags
        ingredients = draft.ingredients.isEmpty ? [MealEditorIngredient(sortOrder: 1)] : draft.ingredients
        steps = draft.steps.isEmpty ? [MealEditorStep(stepNumber: 1)] : draft.steps
        existingPhotoURL = draft.importedImageURL
    }

    private func captureInitialDraft() {
        initialDraft = buildDraft()
        initialAddToHomeRecipes = addToHomeRecipes
        initialShareWithCommunity = shareWithCommunity
    }

    private func renumberIngredients() {
        for index in ingredients.indices {
            ingredients[index].sortOrder = index + 1
        }
    }

    private func renumberSteps() {
        for index in steps.indices {
            steps[index].stepNumber = index + 1
        }
    }

    private func optionalInt(_ value: String, field: MealEditorValidationField) throws -> Int? {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else { return nil }
        guard let intValue = Int(trimmedValue), intValue >= 0 else {
            throw MealServiceError.invalidMealTime
        }
        return intValue
    }

    private func normalizedServingsText(_ value: String?) -> String {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedValue.isEmpty else { return "" }
        if Decimal(string: trimmedValue, locale: Locale(identifier: "en_US_POSIX")) != nil {
            return trimmedValue
        }

        let pattern = #"^\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmedValue, range: NSRange(trimmedValue.startIndex..., in: trimmedValue)),
              let range = Range(match.range(at: 1), in: trimmedValue) else {
            return ""
        }
        return String(trimmedValue[range])
    }

    private func processedJPEGPhoto(from data: Data) throws -> ProcessedMealPhoto {
        guard !data.isEmpty, let image = UIImage(data: data) else {
            throw MealServiceError.invalidPhotoData
        }
        let maxDimension: CGFloat = 2048
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.82), !jpegData.isEmpty else {
            throw MealServiceError.invalidPhotoData
        }
        return ProcessedMealPhoto(
            data: jpegData,
            image: renderedImage,
            originalPixelSize: size,
            resizedPixelSize: targetSize,
            originalByteCount: data.count
        )
    }
}

private struct ProcessedMealPhoto {
    let data: Data
    let image: UIImage
    let originalPixelSize: CGSize
    let resizedPixelSize: CGSize
    let originalByteCount: Int
}

private enum MealEditorSelectedPhotoSource {
    case userSelected
    case importedSource
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfTrimmedEmpty: String? {
        let trimmedValue = trimmed
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
