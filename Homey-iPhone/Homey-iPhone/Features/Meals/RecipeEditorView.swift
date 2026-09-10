import PhotosUI
import SwiftUI
import ImageIO

private enum RecipeEditorMode {
    case create, edit
    var title: String { self == .create ? "Create Recipe" : "Edit Recipe" }
    var subtitle: String { self == .create ? "Bring a new favorite to your Homey collection." : "Update the details of this recipe." }
    var saveTitle: String { self == .create ? "Save Recipe" : "Save Changes" }
}

struct RecipeEditorView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    let existingMeal: HomeyMeal?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: RecipeDraft
    @State private var saving = false
    @State private var error: String?
    @State private var savedHomeID: UUID?
    @State private var savedCommunityID: UUID?
    @State private var savedPhotoPath: String?
    @State private var destinationsComplete = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var selectedPhoto: UIImage?
    @State private var photoURL: URL?
    @State private var loadingPhoto = false
    @State private var uploadedSelectedPhoto = false
    @FocusState private var fieldFocused: Bool
    private let service = MealsService()
    private var mode: RecipeEditorMode { existingMeal == nil ? .create : .edit }
    private var valid: Bool { (try? service.validateSave(draft, homeId: home.id)) != nil }
    private var validationMessage: String? {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { try service.validateSave(draft, homeId: home.id); return nil }
        catch { return error.localizedDescription }
    }

    init(home: HomeSummary, model: MealsViewModel, initialDraft: RecipeDraft? = nil, showsImportMetadata: Bool = false, existingMeal: HomeyMeal? = nil) {
        self.home = home
        self.model = model
        self.existingMeal = existingMeal
        _savedHomeID = State(initialValue: existingMeal?.id)
        _savedPhotoPath = State(initialValue: existingMeal?.primaryPhotoPath)
        _draft = State(initialValue: initialDraft ?? RecipeDraft())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode.title).font(HomeyTypography.hero).accessibilityAddTraits(.isHeader)
                            Text(mode.subtitle).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                        }
                        photoSection
                        RecipeEditorField("Recipe Title *") {
                            TextField("e.g. Creamy Garlic Chicken Pasta", text: $draft.name, axis: .vertical).focused($fieldFocused)
                                .lineLimit(1...3).accessibilityIdentifier("recipeTitle")
                        }
                        let stacked = geometry.size.width < 390 || dynamicTypeSize.isAccessibilitySize
                        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                        layout {
                            mealTypeField
                            RecipeEditorField("Source") {
                                TextField("e.g. Our Family, Website, Book", text: $draft.sourceName, axis: .vertical).focused($fieldFocused).lineLimit(1...3)
                            }
                        }
                        communitySection
                        ingredientsSection
                        directionsSection
                        detailsSection
                        if let error { HomeyErrorView(message: error) }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .disabled(saving || destinationsComplete)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(HomeyColors.recipeBackground.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
            }
            .foregroundStyle(HomeyColors.text)
            .tint(HomeyColors.recipeGreenAccent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HomeyColors.recipeBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("Recipes", systemImage: "chevron.left").font(.headline) }
                        .disabled(saving || loadingPhoto)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
            .interactiveDismissDisabled(saving || loadingPhoto)
            .alert("Recipe Save", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .task { photoURL = await service.signedImageURL(path: savedPhotoPath ?? draft.imported?.recipe.imageUrl) }
            .task(id: photoSelection) { await preparePhoto() }
        }
    }

    private var photoSection: some View {
        PhotosPicker(selection: $photoSelection, matching: .images) {
            Color.clear
                .frame(height: 190)
                .overlay {
                    GeometryReader { geometry in
                        Group {
                            if let selectedPhoto {
                                Image(uiImage: selectedPhoto).resizable().scaledToFill()
                            } else if let photoURL {
                                AsyncImage(url: photoURL) { image in image.resizable().scaledToFill() } placeholder: { photoPlaceholder }
                            } else { photoPlaceholder }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if selectedPhoto != nil || photoURL != nil {
                        Label("Change Photo", systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(.black.opacity(0.65), in: Capsule()).padding(14)
                    }
                }
                .overlay { if loadingPhoto { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .disabled(loadingPhoto)
        .accessibilityLabel(selectedPhoto != nil || photoURL != nil ? "Change Photo" : "Add Photo")
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [HomeyColors.warmCream, HomeyColors.recipeGreenAccent.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: "camera.fill").font(.system(size: 28)).padding(17)
                    .background(.white.opacity(0.65), in: Circle())
                Text("Add Photo").font(.headline)
                Text("A little inspiration for your next meal.").font(.caption).foregroundStyle(HomeyColors.secondaryText)
            }.foregroundStyle(HomeyColors.recipeGreenAccent)
        }
    }

    private var mealTypeField: some View {
        RecipeEditorField("Meal Type") {
            Menu {
                ForEach(MealType.allCases) { type in
                    Toggle(type.title, isOn: .init(get: { draft.mealTypes.contains(type) }, set: { selected in
                        if selected { draft.mealTypes.insert(type) } else { draft.mealTypes.remove(type) }
                    }))
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                    Text(draft.mealTypes.isEmpty ? "Select" : MealType.allCases.filter { draft.mealTypes.contains($0) }.map(\.title).joined(separator: ", "))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }.frame(minHeight: 24)
            }.accessibilityIdentifier("recipeMealTypes")
        }
    }

    private var communitySection: some View {
        HStack(alignment: .top, spacing: 12) {
            RecipeEditorIcon(symbol: "person.2", color: HomeyColors.recipeOrangeAccent)
            if mode == .create {
                Toggle(isOn: $draft.shareWithCommunity) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Contribute to Community").font(.headline)
                        Text("Share this recipe with the Homey community.").font(.caption).foregroundStyle(HomeyColors.secondaryText)
                    }
                }.tint(HomeyColors.recipeOrangeAccent).accessibilityIdentifier("recipeCommunity")
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Community sharing").font(.headline)
                    Text("Your changes update this Home recipe. Community recipes are managed separately.")
                        .font(.caption).foregroundStyle(HomeyColors.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(HomeyColors.recipeOrangeAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(HomeyColors.recipeOrangeAccent.opacity(0.18)) }
    }

    private var ingredientsSection: some View {
        RecipeEditorCard(title: "Ingredients", subtitle: "Add each ingredient on a new line.", symbol: "cart", color: HomeyColors.recipeGreenAccent) {
            ForEach($draft.ingredients) { $ingredient in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        TextField("Ingredient", text: $ingredient.name, axis: .vertical).focused($fieldFocused).lineLimit(1...4)
                        removeButton("Remove ingredient") { draft.ingredients.removeAll { $0.id == ingredient.id } }
                    }
                    HStack(spacing: 12) {
                        TextField("Quantity", text: $ingredient.quantity).focused($fieldFocused).keyboardType(.numbersAndPunctuation)
                        TextField("Unit", text: $ingredient.unit).focused($fieldFocused)
                    }.font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
                }.padding(14).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 16))
            }
            addButton("Add Ingredient") { draft.ingredients.append(.init()) }
        }
    }

    private var directionsSection: some View {
        RecipeEditorCard(title: "Directions", subtitle: "Add step by step instructions.", symbol: "list.bullet", color: HomeyColors.recipeOrangeAccent) {
            ForEach($draft.steps) { $step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\((draft.steps.firstIndex { $0.id == step.id } ?? 0) + 1)")
                        .font(.subheadline.weight(.semibold)).frame(width: 32, height: 32)
                        .background(HomeyColors.recipeGreenAccent.opacity(0.09), in: Circle())
                    TextField("Describe this step…", text: $step.text, axis: .vertical).focused($fieldFocused).lineLimit(2...10)
                    removeButton("Remove step") { draft.steps.removeAll { $0.id == step.id } }
                }.padding(12).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 16))
            }
            addButton("Add Step") { draft.steps.append(.init()) }
        }
    }

    private var detailsSection: some View {
        RecipeEditorCard(title: "Other details", subtitle: "The little things that make it yours.", symbol: "text.book.closed", color: HomeyColors.recipeGreenAccent) {
            RecipeEditorField("Description") { TextField("Tell us about this recipe", text: $draft.description, axis: .vertical).focused($fieldFocused).lineLimit(2...6) }
            RecipeEditorField("Cuisine") { TextField("e.g. Italian", text: $draft.cuisine).focused($fieldFocused) }
            RecipeEditorField("Difficulty") {
                Picker("Difficulty", selection: $draft.difficulty) {
                    Text("Not set").tag(nil as MealDifficulty?)
                    ForEach(MealDifficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            RecipeEditorField("Prep time (minutes)") { TextField("Optional", value: $draft.prepMinutes, format: .number).focused($fieldFocused).keyboardType(.numberPad) }
            RecipeEditorField("Cook time (minutes)") { TextField("Optional", value: $draft.cookMinutes, format: .number).focused($fieldFocused).keyboardType(.numberPad) }
            RecipeEditorField("Servings") { TextField("Optional", value: $draft.servings, format: .number).focused($fieldFocused).keyboardType(.decimalPad) }
            RecipeEditorField("Source URL") { TextField("https://", text: $draft.sourceURL).focused($fieldFocused).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
            RecipeEditorField("Tags") { TextField("Separate with commas", text: $draft.tagsText, axis: .vertical).focused($fieldFocused).lineLimit(1...4) }
            RecipeEditorField("Notes") { TextField("Tips, substitutions, or family traditions…", text: $draft.notes, axis: .vertical).focused($fieldFocused).lineLimit(3...8) }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            Button { fieldFocused = false; Task { await save() } } label: {
                HStack(spacing: 10) {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "Saving…" : destinationsComplete ? "Retry Refresh" : mode.saveTitle).font(.headline)
                }.frame(maxWidth: .infinity).frame(minHeight: 54)
                    .foregroundStyle(.white)
                    .background(HomeyColors.recipeGreenAccent, in: Capsule())
                    .opacity(saving || loadingPhoto || !valid ? 0.5 : 1)
            }
            .disabled(saving || loadingPhoto || !valid).accessibilityIdentifier("recipeSave")
            if let validationMessage { HomeyErrorView(message: validationMessage) }
            if !fieldFocused {
                Text(mode == .create ? "This recipe will be added to your Home Recipes." : "Changes are saved to your Home Recipes.")
                    .font(.caption).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
            }
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(HomeyColors.recipeBackground.opacity(0.98))
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 11)
            .background(HomeyColors.recipeGreenAccent.opacity(0.1), in: Capsule()) }
    }

    private func removeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
            .foregroundStyle(HomeyColors.secondaryText).accessibilityLabel(title)
    }

    private func preparePhoto() async {
        guard let photoSelection else { return }
        loadingPhoto = true
        defer { loadingPhoto = false }
        do {
            guard let data = try await photoSelection.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800
                  ] as CFDictionary),
                  let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
                throw MealsError.message("We couldn’t prepare that photo. Please choose another image.")
            }
            guard !Task.isCancelled else { return }
            selectedPhotoData = jpeg
            selectedPhoto = UIImage(data: jpeg)
            uploadedSelectedPhoto = false
        } catch {
            guard !Task.isCancelled else { return }
            RecipeSaveDiagnostics.failure(error, stage: "photoSelection")
            self.error = "We couldn’t prepare that photo. Please choose another image."
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        error = nil
        var stage = "validation"
        RecipeSaveDiagnostics.log("Starting save title=\(draft.name) addToHome=true contributeToCommunity=\(draft.shareWithCommunity) imported=\(draft.imported != nil) homeID=\(home.id)")
        defer { saving = false }
        do {
            try service.validateSave(draft, homeId: home.id)
            stage = "authentication"
            try await service.requireSaveSession()
            if !destinationsComplete {
                stage = "homeRecipe"
                RecipeSaveDiagnostics.log("Saving Home recipe…")
                let homeID = try await service.save(draft, homeId: home.id, mealId: savedHomeID, photoPath: savedPhotoPath)
                savedHomeID = homeID
                RecipeSaveDiagnostics.log("Home recipe succeeded: \(homeID)")

                if let selectedPhotoData {
                    if !uploadedSelectedPhoto {
                        stage = "imageUpload"
                        savedPhotoPath = try await service.uploadPhoto(selectedPhotoData, homeId: home.id, mealId: homeID)
                        uploadedSelectedPhoto = true
                    }
                    stage = "imageAttachment"
                    _ = try await service.save(draft, homeId: home.id, mealId: homeID, photoPath: savedPhotoPath)
                } else if let imageURL = draft.imported?.recipe.imageUrl, !imageURL.isEmpty {
                    if savedPhotoPath == nil {
                        stage = "imageUpload"
                        RecipeSaveDiagnostics.log("Downloading/uploading imported image to meal-images…")
                        savedPhotoPath = try await service.importPhoto(imageURL, homeId: home.id, mealId: homeID)
                        RecipeSaveDiagnostics.log("Image upload succeeded")
                    }
                    stage = "imageAttachment"
                    _ = try await service.save(draft, homeId: home.id, mealId: homeID, photoPath: savedPhotoPath)
                    RecipeSaveDiagnostics.log("Image attachment succeeded")
                } else {
                    RecipeSaveDiagnostics.log("Image upload skipped: no selected/imported photo")
                }

                if existingMeal == nil && draft.shareWithCommunity && savedCommunityID == nil {
                    stage = "communityRecipe"
                    RecipeSaveDiagnostics.log("Saving Community recipe…")
                    savedCommunityID = try await service.share(draft, homeRecipeID: homeID, homePhotoPath: savedPhotoPath)
                    RecipeSaveDiagnostics.log("Community recipe succeeded: \(savedCommunityID!.uuidString)")
                }
                destinationsComplete = true
            }
            stage = "refresh"
            RecipeSaveDiagnostics.log("Refreshing Home Recipes and Explore; no favorite operations requested")
            try await model.refreshRecipesAfterSave(home: home)
            if existingMeal != nil { await model.refreshPlan(home: home) }
            RecipeSaveDiagnostics.log("Finished successfully; dismissing editor")
            dismiss()
        } catch {
            RecipeSaveDiagnostics.failure(error, stage: stage)
            if destinationsComplete {
                self.error = "Your recipe was saved, but Homey couldn’t refresh the recipe list. Tap Retry Refresh to try again."
            } else if stage == "communityRecipe", savedHomeID != nil {
                self.error = "Saved to Home Recipes, but Community sharing failed. Try Save again to retry sharing, or turn off Contribute to Community to finish."
            } else if stage == "imageUpload" || stage == "imageAttachment" {
                self.error = "Saved to Home Recipes, but the photo couldn’t be saved. Please try Save again."
            } else if let validation = error as? MealsError {
                self.error = validation.localizedDescription
            } else {
                self.error = "Homey couldn’t save this recipe. Please try again."
            }
        }
    }

}

private struct RecipeEditorField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content.padding(.horizontal, 14).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(HomeyColors.border.opacity(0.3)) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecipeEditorIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 21, weight: .medium))
            .foregroundStyle(color).frame(width: 44, height: 44)
            .background(color.opacity(0.11), in: Circle()).accessibilityHidden(true)
    }
}

private struct RecipeEditorCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RecipeEditorIcon(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(HomeyTypography.headline).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                }
            }
            content
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(HomeyColors.border.opacity(0.15)) }
            .shadow(color: HomeyColors.text.opacity(0.035), radius: 12, y: 4)
    }
}
