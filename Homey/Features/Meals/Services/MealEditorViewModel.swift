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
    @Published var ingredients: [MealEditorIngredient] = []
    @Published var steps: [MealEditorStep] = []
    @Published var isDraft = true
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var validationErrors: [MealEditorValidationError] = []

    let mode: MealEditorMode
    private let mealService: MealServicing
    private var initialDraft = MealEditorDraft()
    private var loadedMealID: UUID?
    private var persistedMealID: UUID?

    init(mode: MealEditorMode, mealService: MealServicing? = nil) {
        self.mode = mode
        self.mealService = mealService ?? MealService()
        persistedMealID = mode.mealID
        ingredients = [MealEditorIngredient(sortOrder: 1)]
        steps = [MealEditorStep(stepNumber: 1)]
        captureInitialDraft()
    }

    var title: String {
        if persistedMealID != nil {
            return "Edit Meal"
        }

        switch mode {
        case .create:
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
        case .create:
            return "Add a meal and recipe to your family's shared library."
        case .edit:
            return "Make changes to your recipe."
        }
    }

    var hasUnsavedChanges: Bool {
        buildDraft() != initialDraft || selectedPhotoData != nil
    }

    var hasPhoto: Bool {
        selectedPhotoImage != nil || existingPhotoPath != nil
    }

    var isCreatingNewMeal: Bool {
        persistedMealID == nil && mode.mealID == nil
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
        guard validateForPublish(permissions: permissions), let homeId else {
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

    func uploadPhotoIfNeeded(homeId: UUID, mealId: UUID) async throws -> MealPhoto? {
        guard let selectedPhotoData else { return nil }
        do {
            let compressedData = try compressedImageData(from: selectedPhotoData)
            return try await mealService.uploadMealPhoto(homeId: homeId, mealId: mealId, imageData: compressedData, fileExtension: "jpg")
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
        selectedPhotoData = nil
        selectedPhotoImage = nil
        validationErrors = []
        errorMessage = nil
    }

    func setPhotoData(_ data: Data) {
        do {
            selectedPhotoData = try compressedImageData(from: data)
            selectedPhotoImage = UIImage(data: selectedPhotoData ?? data)
            validationErrors.removeAll { $0.field == .photo }
        } catch {
            selectedPhotoData = nil
            selectedPhotoImage = nil
            validationErrors.append(MealEditorValidationError(field: .photo, message: "We could not prepare that photo. Please choose another image."))
        }
    }

    func removePhoto() {
        existingPhotoPath = nil
        existingPhotoURL = nil
        selectedPhotoData = nil
        selectedPhotoImage = nil
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

        var draft = buildDraft()

        do {
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

            apply(draft: draft)
            existingPhotoPath = draft.primaryPhotoPath
            selectedPhotoData = nil
            isDraft = saveAsDraft
            persistedMealID = savedMealID
            loadedMealID = savedMealID
            captureInitialDraft()
            let savedMeal = await fetchSavedMealAfterSave(mealID: savedMealID)
            successMessage = saveAsDraft ? "Draft saved." : "Meal saved."
            UIAccessibility.post(notification: .announcement, argument: successMessage)
            NotificationCenter.default.post(name: .homeyMealsDidChange, object: nil)
            return .saved(mealID: savedMealID, meal: savedMeal)
        } catch {
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
                _ = try await mealService.saveMealRecipe(
                    homeId: homeId,
                    mealId: createdMealID,
                    draft: draft,
                    isDraft: saveAsDraft
                )
            }
            return createdMealID
        } catch {
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

    private func updatePersistedMeal(homeId: UUID, mealId: UUID, draft: inout MealEditorDraft, saveAsDraft: Bool) async throws -> UUID {
        var uploadedPhoto: MealPhoto?

        do {
            uploadedPhoto = try await uploadPhotoIfNeeded(homeId: homeId, mealId: mealId)
            if let uploadedPhoto {
                draft.primaryPhotoPath = uploadedPhoto.path
            }
            return try await mealService.saveMealRecipe(homeId: homeId, mealId: mealId, draft: draft, isDraft: saveAsDraft)
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
            steps: steps
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
    }

    private func captureInitialDraft() {
        initialDraft = buildDraft()
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

    private func compressedImageData(from data: Data) throws -> Data {
        guard !data.isEmpty, let image = UIImage(data: data) else {
            throw MealServiceError.invalidPhotoData
        }
        let maxDimension: CGFloat = 1800
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
        return jpegData
    }
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
