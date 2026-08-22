import PhotosUI
import SwiftUI

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authenticationService: AuthenticationService
    @Environment(\.homePermissions) private var permissions
    @Environment(\.homePermissionResolution) private var permissionResolution
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var homeService: HomeService
    @StateObject private var viewModel: MealEditorViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingDeleteConfirmation = false
    @State private var editingIngredient: MealEditorIngredient?
    @State private var editingStep: MealEditorStep?
    @State private var tagText = ""
    @FocusState private var focusedField: MealEditorField?

    var onSaved: (UUID, Meal?, UUID?) -> Void
    var onCancel: () -> Void
    var onDelete: (UUID) -> Void

    init(
        mode: MealEditorMode,
        saveDestination: RecipeSaveDestination = .home,
        onSaved: @escaping (UUID, Meal?, UUID?) -> Void = { _, _, _ in },
        onCancel: @escaping () -> Void = { },
        onDelete: @escaping (UUID) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: MealEditorViewModel(mode: mode, saveDestination: saveDestination))
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        permissionState
                        editorContent
                        sectionJumpBar(proxy: proxy)
                    }
                    .padding(.horizontal, horizontalSizeClass == .compact ? 18 : 34)
                    .padding(.top, horizontalSizeClass == .compact ? 22 : 34)
                    .padding(.bottom, horizontalSizeClass == .compact ? 112 : 38)
                    .frame(maxWidth: 1180, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .task(id: homeService.selectedHomeID) {
            debugLogPermissionState()
            await viewModel.loadMealIfNeeded(homeId: homeService.selectedHomeID)
        }
        .onChange(of: permissionResolution) { _, _ in
            debugLogPermissionState()
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task { await loadPhoto(from: newValue) }
        }
        .sheet(item: $editingIngredient) { ingredient in
            IngredientEditorSheet(
                ingredient: ingredient,
                sections: ingredientSections,
                onSave: updateIngredient
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingStep) { step in
            StepEditorSheet(step: step, onSave: updateStep)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Discard Changes?", isPresented: $isShowingDiscardConfirmation) {
            Button("Keep Editing", role: .cancel) { }
            Button("Discard Changes", role: .destructive) {
                viewModel.discardChanges()
                onCancel()
                dismiss()
            }
        } message: {
            Text("Your unsaved meal and recipe changes will be lost.")
        }
        .alert("Meal Editor", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unable to save this meal.")
        }
        .alert("Meal Saved", isPresented: successBinding) {
            Button("OK", role: .cancel) { viewModel.successMessage = nil }
        } message: {
            Text(viewModel.successMessage ?? "Meal saved.")
        }
        .confirmationDialog("Delete Recipe?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive) {
                deleteMeal()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Delete this recipe from this Home? Future planned meal events for this recipe will be removed from the calendar. Past meal history will be preserved when needed.")
        }
        .safeAreaInset(edge: .bottom) {
            if horizontalSizeClass == .compact {
                compactBottomControls
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Previous") { moveFocus(previous: true) }
                Button("Next") { moveFocus(previous: false) }
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(viewModel.subtitle)
                        .font(.title3)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                Spacer()
                if horizontalSizeClass != .compact {
                    topControls
                }
            }
        }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            cancelButton
            if canSaveDraft {
                saveDraftButton
            }
            saveMealButton
        }
    }

    private var compactBottomControls: some View {
        HStack(spacing: 10) {
            cancelButton
                .frame(maxWidth: .infinity)
            if canSaveDraft {
                saveDraftButton
                    .frame(maxWidth: .infinity)
            }
            saveMealButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HomeyDashboardTheme.softBorder)
                .frame(height: 1)
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { requestCancel() }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(HomeyDashboardTheme.cardBackground, in: Capsule())
            .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            .accessibilityLabel("Cancel meal editing")
    }

    private var saveDraftButton: some View {
        Button {
            Task { await saveDraft() }
        } label: {
            saveButtonLabel(title: "Save Draft", compactTitle: "Draft", isPrimary: false)
        }
        .buttonStyle(.plain)
        .disabled(!canSaveDraft)
    }

    private var saveMealButton: some View {
        Button {
            Task { await saveMeal() }
        } label: {
            saveButtonLabel(title: primarySaveTitle, compactTitle: primarySaveCompactTitle, isPrimary: true)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving || !canSave)
    }

    @ViewBuilder
    private var permissionState: some View {
        if viewModel.showsDestinationControls && !viewModel.addToHomeRecipes {
            EmptyView()
        } else {
        switch effectivePermissionResolution {
        case .loading:
            MealEditorNoticeCard(
                title: "Loading Permissions",
                message: "Loading your Home permissions…",
                systemImage: "hourglass"
            )
        case .unavailable:
            MealEditorNoticeCard(
                title: "Meals Unavailable",
                message: "We cannot find your membership for this Home.",
                systemImage: "lock.fill"
            )
        case .resolved:
            if !canSave {
                MealEditorNoticeCard(
                    title: "Meals Unavailable",
                    message: permissionDeniedMessage,
                    systemImage: "lock.fill"
                )
            }
        }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if viewModel.isLoading {
            MealEditorLoadingView()
        } else if horizontalSizeClass == .compact {
            singleColumnEditor
        } else {
            twoColumnEditor
        }
    }

    private var twoColumnEditor: some View {
        VStack(spacing: 26) {
            HStack(alignment: .top, spacing: 26) {
                photoCard.id(MealEditorSection.photos)
                    .frame(width: 390, alignment: .top)
                mealDetailsCard.id(MealEditorSection.overview)
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            HStack(alignment: .top, spacing: 26) {
                ingredientsCard.id(MealEditorSection.ingredients)
                    .frame(maxWidth: .infinity, alignment: .top)
                directionsCard.id(MealEditorSection.steps)
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            HStack(alignment: .top, spacing: 26) {
                sourceCard
                    .frame(maxWidth: .infinity, alignment: .top)
                notesCard.id(MealEditorSection.notes)
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            deleteMealSection
        }
    }

    private var singleColumnEditor: some View {
        VStack(spacing: 16) {
            photoCard.id(MealEditorSection.photos)
            mealDetailsCard.id(MealEditorSection.overview)
            ingredientsCard.id(MealEditorSection.ingredients)
            directionsCard.id(MealEditorSection.steps)
            sourceCard
            notesCard.id(MealEditorSection.notes)
            deleteMealSection
        }
    }

    @ViewBuilder
    private var deleteMealSection: some View {
        if canDeleteMeal {
            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label("Delete Recipe", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.coralAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(HomeyDashboardTheme.coralAccent.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Delete Recipe")
        }
    }

    private var photoCard: some View {
        let hasPhoto = viewModel.hasPhoto
        return MealEditorCard(title: "Photo") {
            VStack(alignment: .leading, spacing: 14) {
                MealPhotoPreviewContainer(
                    height: photoBoxHeight,
                    fixedWidth: photoBoxWidth,
                    isProcessing: viewModel.isProcessingPhoto,
                    accessibilityLabel: hasPhoto ? "Meal photo" : "No meal photo selected"
                ) {
                    photoContent
                }

                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(hasPhoto ? "Change Photo" : "Choose Photo", systemImage: "photo")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(HomeyDashboardTheme.warmBrown)
                    .disabled(viewModel.isProcessingPhoto || viewModel.isSaving)

                    if hasPhoto {
                        Button(role: .destructive) {
                            viewModel.removePhoto()
                        } label: {
                            Label("Remove Photo", systemImage: "trash")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isProcessingPhoto || viewModel.isSaving)
                    }
                }
                validationText(for: .photo)
            }
        }
    }

    private var photoBoxHeight: CGFloat {
        horizontalSizeClass == .compact ? 220 : 300
    }

    private var photoBoxWidth: CGFloat? {
        horizontalSizeClass == .compact ? nil : 350
    }

    @ViewBuilder
    private var photoContent: some View {
        if let image = viewModel.selectedPhotoImage {
            MealPhotoPreviewImage(image: Image(uiImage: image))
        } else if let url = viewModel.existingPhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    MealPhotoPreviewImage(image: image)
                case .empty:
                    ProgressView().tint(HomeyDashboardTheme.warmBrown)
                case .failure:
                    photoPlaceholder
                @unknown default:
                    photoPlaceholder
                }
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
            Text("Add a meal photo")
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mealDetailsCard: some View {
        MealEditorCard(title: "Meal Details") {
            destinationControls
        } content: {
            VStack(alignment: .leading, spacing: 15) {
                destinationValidationText

                labeledTextField("Meal Name", text: $viewModel.name, field: .name, placeholder: "Chicken Tortilla Soup")
                validationText(for: .name)

                labeledTextEditor("Description", text: $viewModel.description, minHeight: 84)

                mealTypesPicker
                validationText(for: .mealTypes)

                HStack(spacing: 12) {
                    labeledTextField("Prep Time", text: $viewModel.prepTimeText, field: .prepTime, placeholder: "15", keyboard: .numberPad, suffix: "min")
                        .frame(maxWidth: .infinity)
                    labeledTextField("Cook Time", text: $viewModel.cookTimeText, field: .cookTime, placeholder: "30", keyboard: .numberPad, suffix: "min")
                        .frame(maxWidth: .infinity)
                    labeledTextField("Servings", text: $viewModel.servingsText, field: .servings, placeholder: "4", keyboard: .decimalPad)
                        .frame(maxWidth: .infinity)
                    difficultyPicker
                        .frame(maxWidth: .infinity)
                }
                validationText(for: .prepTime)
                validationText(for: .cookTime)
                validationText(for: .servings)

                labeledTextField("Cuisine", text: $viewModel.cuisine, field: .cuisine, placeholder: "Italian, Mexican, Thai...")
                cuisineSuggestions
                tagsEditor
            }
        }
    }

    @ViewBuilder
    private var destinationControls: some View {
        if viewModel.showsDestinationControls {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    destinationToggle("Add to Home Recipes", isOn: $viewModel.addToHomeRecipes)
                    destinationToggle("Share with Community", isOn: $viewModel.shareWithCommunity)
                }

                VStack(alignment: .trailing, spacing: 6) {
                    destinationToggle("Add to Home Recipes", isOn: $viewModel.addToHomeRecipes)
                    destinationToggle("Share with Community", isOn: $viewModel.shareWithCommunity)
                }
            }
            .tint(HomeyDashboardTheme.warmBrown)
        }
    }

    private func destinationToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .font(.caption.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.isSaving)
    }

    @ViewBuilder
    private var destinationValidationText: some View {
        if viewModel.showsDestinationControls && !viewModel.hasSelectedSaveDestination {
            Text("Choose at least one place to save this recipe.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.coralAccent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mealTypesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meal Types")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            FlowLayout(spacing: 10, minimumItemWidth: 126) {
                ForEach(MealType.allCases) { mealType in
                    let isSelected = viewModel.selectedMealTypes.contains(mealType)
                    Button {
                        viewModel.toggleMealType(mealType)
                    } label: {
                        Label(mealType.displayName, systemImage: mealType.systemImageName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(width: 126, height: 42)
                            .background(isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground, in: Capsule())
                            .foregroundStyle(isSelected ? .white : HomeyDashboardTheme.primaryText)
                            .overlay { Capsule().stroke(isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.softBorder, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mealType.displayName) meal type")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.selectedMealTypes)
        }
    }

    private var difficultyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            Picker("Difficulty", selection: $viewModel.difficulty) {
                Text("None").tag(MealDifficulty?.none)
                ForEach(MealDifficulty.allCases) { difficulty in
                    Text(difficulty.displayName).tag(Optional(difficulty))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 14)
            .background(HomeyDashboardTheme.appBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        }
    }

    private var cuisineSuggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.cuisineSuggestions, id: \.self) { cuisine in
                    Button(cuisine) { viewModel.cuisine = cuisine }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            HStack(spacing: 8) {
                TextField("Add tag", text: $tagText)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .tag)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(HomeyDashboardTheme.appBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Add") {
                    viewModel.addTag(tagText)
                    tagText = ""
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(minWidth: 58, minHeight: 44)
            }
            FlowLayout(spacing: 8) {
                ForEach(viewModel.tags, id: \.self) { tag in
                    Button {
                        viewModel.removeTag(tag)
                    } label: {
                        Label(tag, systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 34)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                            .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder.opacity(0.7), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.tags)
        }
    }

    private var ingredientsCard: some View {
        MealEditorCard(title: "Ingredients", spacing: 12) {
            Menu {
                Button("Add Ingredient") { viewModel.addIngredient(sectionName: ingredientSections.first ?? "Ingredients") }
                Button("Add Section") { viewModel.addIngredient(sectionName: "New Section") }
            } label: {
                Label("Add Ingredient", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 42)
            }
            .buttonStyle(.bordered)
            .tint(HomeyDashboardTheme.warmBrown)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                validationText(for: .ingredients)
                ForEach(groupedIngredients, id: \.section) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        if shouldShowIngredientSectionTitle(group.section) {
                            Text(group.section)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(HomeyDashboardTheme.primaryText)
                        }
                        ForEach(group.items) { ingredient in
                            IngredientRow(
                                ingredient: ingredient,
                                onEdit: { editingIngredient = ingredient },
                                onDuplicate: { viewModel.duplicateIngredient(ingredient) },
                                onDelete: { viewModel.deleteIngredient(ingredient) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func shouldShowIngredientSectionTitle(_ section: String) -> Bool {
        groupedIngredients.count > 1 || section != "Ingredients"
    }

    private var directionsCard: some View {
        MealEditorCard(title: "Directions", spacing: 12) {
            Button {
                viewModel.addStep()
            } label: {
                Label("Add Step", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 42)
            }
            .buttonStyle(.bordered)
            .tint(HomeyDashboardTheme.warmBrown)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                validationText(for: .steps)
                ForEach(viewModel.steps) { step in
                    StepRow(
                        step: step,
                        onEdit: { editingStep = step },
                        onDuplicate: { viewModel.duplicateStep(step) },
                        onDelete: { viewModel.deleteStep(step) }
                    )
                }
            }
        }
    }

    private var sourceCard: some View {
        MealEditorCard(title: "Source") {
            VStack(alignment: .leading, spacing: 14) {
                labeledTextField("Source Name", text: $viewModel.sourceName, field: .sourceName, placeholder: "Grandma's Recipe")
                labeledTextField("Source URL", text: $viewModel.sourceURLText, field: .sourceURL, placeholder: "https://example.com/recipe", keyboard: .URL)
                validationText(for: .sourceURL)
            }
            .frame(minHeight: horizontalSizeClass == .compact ? 0 : 158, alignment: .top)
        }
    }

    private var notesCard: some View {
        MealEditorCard(title: "Notes") {
            labeledTextEditor(
                "Family Notes",
                text: $viewModel.notes,
                minHeight: horizontalSizeClass == .compact ? 150 : 124,
                placeholder: "Add family preferences, substitutions, cooking tips, or anything worth remembering."
            )
        }
    }

    private func sectionJumpBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            ForEach(MealEditorSection.allCases) { section in
                Button(section.title) {
                    if section == .nutrition {
                        viewModel.successMessage = "Nutrition is coming soon."
                    } else {
                        withAnimation(.snappy) { proxy.scrollTo(section, anchor: .top) }
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .accessibilityLabel("Meal editor sections")
    }

    private func labeledTextField(_ title: String, text: Binding<String>, field: MealEditorField, placeholder: String, keyboard: UIKeyboardType = .default, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                    .autocorrectionDisabled(keyboard == .URL)
                    .focused($focusedField, equals: field)
                if let suffix, !text.wrappedValue.isEmpty {
                    Text(suffix)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(HomeyDashboardTheme.appBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        }
    }

    private func labeledTextEditor(_ title: String, text: Binding<String>, minHeight: CGFloat, placeholder: String = "Optional") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.75))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(HomeyDashboardTheme.appBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        }
    }

    @ViewBuilder
    private func validationText(for field: MealEditorValidationField) -> some View {
        if let message = viewModel.validationMessage(for: field) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.coralAccent)
                .accessibilityLabel(message)
        }
    }

    private func saveButtonLabel(title: String, compactTitle: String, isPrimary: Bool) -> some View {
        HStack(spacing: 8) {
            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .tint(isPrimary ? .white : HomeyDashboardTheme.warmBrown)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(horizontalSizeClass == .compact ? compactTitle : title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(isPrimary ? .white : HomeyDashboardTheme.warmBrown)
        .padding(.horizontal, horizontalSizeClass == .compact ? 12 : 16)
        .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : nil)
        .frame(minHeight: 44)
        .background(isPrimary ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.cardBackground, in: Capsule())
        .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: isPrimary ? 0 : 1) }
        .opacity((viewModel.isSaving || !canSave) ? 0.72 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewModel.isSaving)
    }

    private var groupedIngredients: [(section: String, items: [MealEditorIngredient])] {
        Dictionary(grouping: viewModel.ingredients) { ingredient in
            ingredient.sectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ingredients" : ingredient.sectionName
        }
        .map { (section: $0.key, items: $0.value.sorted { $0.sortOrder < $1.sortOrder }) }
        .sorted { $0.section.localizedCaseInsensitiveCompare($1.section) == .orderedAscending }
    }

    private var ingredientSections: [String] {
        let sections = Set(viewModel.ingredients.map { $0.sectionName.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return sections.isEmpty ? ["Ingredients"] : sections.sorted()
    }

    private var effectivePermissionResolution: PermissionResolutionState {
        let sharedResolution = homeService.permissionResolutionState(currentUser: authenticationService.currentUser)

        switch sharedResolution {
        case .resolved, .loading:
            return sharedResolution
        case .unavailable:
            break
        }

        switch permissionResolution {
        case .unavailable where hasInjectedMealPermissions:
            return .resolved(permissions)
        default:
            return permissionResolution
        }
    }

    private var hasInjectedMealPermissions: Bool {
        permissions.meals.canView
            || permissions.meals.canCreate
            || permissions.meals.canEdit
            || permissions.meals.canArchive
            || permissions.meals.canDelete
            || permissions.meals.canFavorite
    }

    private var resolvedPermissions: HomePermissions? {
        if case .resolved(let resolvedPermissions) = effectivePermissionResolution {
            return resolvedPermissions
        }
        return nil
    }

    private var canSave: Bool {
        guard viewModel.hasSelectedSaveDestination else {
            return false
        }

        if viewModel.showsDestinationControls {
            guard viewModel.addToHomeRecipes else {
                return true
            }

            guard let resolvedPermissions else {
                return false
            }

            return resolvedPermissions.meals.canCreate
        }

        guard let resolvedPermissions else {
            return false
        }

        return viewModel.isCreatingNewMeal ? resolvedPermissions.meals.canCreate : resolvedPermissions.meals.canEdit
    }

    private var canSaveDraft: Bool {
        guard !viewModel.isSaving else { return false }

        if viewModel.showsDestinationControls {
            guard viewModel.addToHomeRecipes,
                  let resolvedPermissions else {
                return false
            }
            return resolvedPermissions.meals.canCreate
        }

        guard let resolvedPermissions else {
            return false
        }
        return viewModel.isCreatingNewMeal ? resolvedPermissions.meals.canCreate : resolvedPermissions.meals.canEdit
    }

    private var primarySaveTitle: String {
        if viewModel.showsDestinationControls,
           !viewModel.addToHomeRecipes,
           viewModel.shareWithCommunity {
            return "Add to Community"
        }

        return "Save Meal"
    }

    private var primarySaveCompactTitle: String {
        if viewModel.showsDestinationControls,
           !viewModel.addToHomeRecipes,
           viewModel.shareWithCommunity {
            return "Add"
        }

        return "Save"
    }

    private var canDeleteMeal: Bool {
        guard !viewModel.isCreatingNewMeal,
              viewModel.mode.mealID != nil,
              let resolvedPermissions else {
            return false
        }

        return resolvedPermissions.meals.canDelete
    }

    private var permissionDeniedMessage: String {
        return viewModel.isCreatingNewMeal
            ? "You do not have permission to create meals in this Home."
            : "You do not have permission to edit meals in this Home."
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private var successBinding: Binding<Bool> {
        Binding(get: { viewModel.successMessage != nil }, set: { if !$0 { viewModel.successMessage = nil } })
    }

    private func requestCancel() {
        if viewModel.hasUnsavedChanges {
            isShowingDiscardConfirmation = true
        } else {
            onCancel()
            dismiss()
        }
    }

    private func saveDraft() async {
        guard let permissions = permissionsForSave() else { return }
        let result = await viewModel.saveDraft(homeId: homeService.selectedHomeID, permissions: permissions)
        if case .saved(let mealID, let meal, _) = result {
            onSaved(mealID, meal, nil)
        }
    }

    private func saveMeal() async {
        let permissions = permissionsForSave() ?? .restrictive
        let result = await viewModel.saveMeal(homeId: homeService.selectedHomeID, permissions: permissions)
        if case .saved(let mealID, let meal, let globalRecipeID) = result {
            onSaved(mealID, meal, globalRecipeID)
            dismiss()
        }
    }

    private func deleteMeal() {
        guard let mealID = viewModel.mode.mealID else { return }
        onDelete(mealID)
        dismiss()
    }

    private func permissionsForSave() -> HomePermissions? {
        switch effectivePermissionResolution {
        case .resolved(let permissions):
            return permissions
        case .loading:
            viewModel.errorMessage = "Loading your Home permissions…"
            return nil
        case .unavailable:
            viewModel.errorMessage = "We cannot find your membership for this Home."
            return nil
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            await viewModel.setPhotoData(data)
        } catch {
            #if DEBUG
            print("========== MEAL PHOTO SELECTION FAILED ==========")
            print("localizedDescription: \(error.localizedDescription)")
            print(String(reflecting: error))
            print("=================================================")
            #endif
            viewModel.errorMessage = "We could not load that photo. Please choose another image."
        }
    }

    private func updateIngredient(_ ingredient: MealEditorIngredient) {
        if let index = viewModel.ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            viewModel.ingredients[index] = ingredient
        }
    }

    private func updateStep(_ step: MealEditorStep) {
        if let index = viewModel.steps.firstIndex(where: { $0.id == step.id }) {
            viewModel.steps[index] = step
        }
    }

    private func moveFocus(previous: Bool) {
        let fields = MealEditorField.allCases
        guard let focusedField, let index = fields.firstIndex(of: focusedField) else {
            self.focusedField = previous ? fields.last : fields.first
            return
        }
        let nextIndex = previous ? max(fields.startIndex, index - 1) : min(fields.index(before: fields.endIndex), index + 1)
        self.focusedField = fields[nextIndex]
    }

    private func debugLogPermissionState() {
        #if DEBUG
        let stateDescription: String
        switch effectivePermissionResolution {
        case .loading:
            stateDescription = "loading"
        case .unavailable:
            stateDescription = "unavailable"
        case .resolved(let permissions):
            stateDescription = "resolved(canCreate: \(permissions.meals.canCreate), canEdit: \(permissions.meals.canEdit))"
        }

        let currentMembership = homeService.currentMembershipForSelectedHome(currentUserID: authenticationService.currentUser?.id)
        print("MealEditor permission resolution")
        print("authenticated_user_id: \(authenticationService.currentUser?.id.uuidString ?? "nil")")
        print("selected_home_id: \(homeService.selectedHomeID?.uuidString ?? "nil")")
        print("current_membership_user_id: \(currentMembership?.userId.uuidString ?? "nil")")
        print("current_membership_home_id: \(currentMembership?.homeId.uuidString ?? "nil")")
        print("decoded_role: \(currentMembership?.role.rawValue ?? homeService.selectedHome()?.role?.rawValue ?? "nil")")
        print("editor_mode: \(viewModel.isCreatingNewMeal ? "create" : "edit")")
        print("permission_loading_state: \(stateDescription)")
        if case .resolved(let permissions) = effectivePermissionResolution {
            print("can_view: \(permissions.meals.canView)")
            print("can_create: \(permissions.meals.canCreate)")
            print("can_edit: \(permissions.meals.canEdit)")
            print("can_archive: \(permissions.meals.canArchive)")
            print("can_delete: \(permissions.meals.canDelete)")
        }
        if let currentUserID = authenticationService.currentUser?.id,
           let selectedHomeID = homeService.selectedHomeID,
           let currentMembership,
           currentMembership.userId == currentUserID,
           currentMembership.homeId == selectedHomeID,
           case .unavailable = effectivePermissionResolution {
            assertionFailure("Matching Home membership must not resolve as unavailable.")
            print("Warning: matching Home membership resolved unavailable")
        }
        #endif
    }

    private static let cuisineSuggestions = [
        "American", "Italian", "Mexican", "Chinese", "Japanese", "Thai", "Indian", "Mediterranean", "French", "Korean", "Vietnamese", "Southern", "Other"
    ]
}

private enum MealEditorField: CaseIterable, Hashable {
    case name
    case prepTime
    case cookTime
    case servings
    case cuisine
    case tag
    case sourceName
    case sourceURL
}

private enum MealEditorSection: String, CaseIterable, Identifiable {
    case overview
    case ingredients
    case steps
    case notes
    case photos
    case nutrition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .ingredients: "Ingredients"
        case .steps: "Steps"
        case .notes: "Notes"
        case .photos: "Photos"
        case .nutrition: "Nutrition"
        }
    }
}

private struct MealEditorCard<HeaderAccessory: View, Content: View>: View {
    let title: String
    let spacing: CGFloat
    @ViewBuilder var headerAccessory: HeaderAccessory
    @ViewBuilder var content: Content

    init(
        title: String,
        spacing: CGFloat = 16,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.spacing = spacing
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Spacer(minLength: 12)
                headerAccessory
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(HomeyDashboardTheme.softBorder.opacity(0.85), lineWidth: 1) }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.22), radius: 14, x: 0, y: 7)
    }
}

private struct MealPhotoPreviewContainer<Content: View>: View {
    let height: CGFloat
    let fixedWidth: CGFloat?
    let isProcessing: Bool
    let accessibilityLabel: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(HomeyDashboardTheme.selectedSidebarBackground)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            if isProcessing {
                Color.black.opacity(0.18)
                ProgressView()
                    .tint(HomeyDashboardTheme.warmBrown)
            }
        }
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : fixedWidth)
        .frame(height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.28), radius: 14, x: 0, y: 8)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MealPhotoPreviewImage: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

private extension MealEditorCard where HeaderAccessory == EmptyView {
    init(
        title: String,
        spacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, spacing: spacing, headerAccessory: { EmptyView() }, content: content)
    }
}

private struct MealEditorNoticeCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 44, height: 44)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline.weight(.bold))
                Text(message).font(.subheadline).foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            Spacer()
        }
        .foregroundStyle(HomeyDashboardTheme.primaryText)
        .padding(18)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct MealEditorLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(HomeyDashboardTheme.warmBeige.opacity(0.28))
                    .frame(height: 190)
                    .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("Loading meal editor")
    }
}

private struct IngredientRow: View {
    let ingredient: MealEditorIngredient
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .frame(width: 28, height: 44)
                .accessibilityLabel("Drag handle")
            VStack(alignment: .leading, spacing: 5) {
                Text(ingredientTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                if !ingredient.preparation.isEmpty || !ingredient.notes.isEmpty {
                    Text([ingredient.preparation, ingredient.notes].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                if ingredient.isOptional {
                    Text("Optional")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.sageAccent)
                }
            }
            .frame(minHeight: 44, alignment: .center)
            Spacer()
            Menu {
                Button("Edit", action: onEdit)
                Button("Duplicate", action: onDuplicate)
                Button("Move to Section", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Ingredient actions")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softBorder.opacity(0.72), lineWidth: 1) }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private var ingredientTitle: String {
        let parts = [ingredient.quantityText, ingredient.unit, ingredient.name].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? "New ingredient" : parts.joined(separator: " ")
    }
}

private struct StepRow: View {
    let step: MealEditorStep
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .frame(width: 28, height: 44)
                .accessibilityLabel("Drag handle")
            Text("\(step.stepNumber)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(HomeyDashboardTheme.warmBrown, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New direction" : step.instruction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                if !step.timerMinutesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("\(step.timerMinutesText) min", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
            }
            .frame(minHeight: 44, alignment: .center)
            Spacer()
            Menu {
                Button("Edit", action: onEdit)
                Button("Duplicate", action: onDuplicate)
                Button("Move Up", action: onEdit)
                Button("Move Down", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Step actions")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softBorder.opacity(0.72), lineWidth: 1) }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

private struct IngredientEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MealEditorIngredient
    let sections: [String]
    let onSave: (MealEditorIngredient) -> Void

    init(ingredient: MealEditorIngredient, sections: [String], onSave: @escaping (MealEditorIngredient) -> Void) {
        _draft = State(initialValue: ingredient)
        self.sections = sections
        self.onSave = onSave
    }

    private var saveTitle: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add Ingredient" : "Save Ingredient"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Ingredient")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Section", selection: $draft.sectionName) {
                                ForEach(sections, id: \.self) { section in Text(section).tag(section) }
                                Text("New Section").tag("New Section")
                            }
                            .pickerStyle(.menu)
                            mealSheetTextField("Quantity", text: $draft.quantityText, keyboard: .decimalPad)
                            mealSheetTextField("Unit", text: $draft.unit)
                            mealSheetTextField("Ingredient", text: $draft.name)
                            mealSheetTextField("Preparation", text: $draft.preparation)
                            mealSheetTextField("Notes", text: $draft.notes, axis: .vertical)
                                .lineLimit(3...6)
                            Toggle("Optional", isOn: $draft.isOptional)
                                .tint(HomeyDashboardTheme.warmBrown)
                                .frame(minHeight: 44)
                        }
                        .padding(22)
                        .dashboardCard(cornerRadius: 26)

                        bottomActions
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Ingredient")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }

            Button {
                onSave(draft)
                dismiss()
            } label: {
                Text(saveTitle)
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StepEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MealEditorStep
    let onSave: (MealEditorStep) -> Void

    init(step: MealEditorStep, onSave: @escaping (MealEditorStep) -> Void) {
        _draft = State(initialValue: step)
        self.onSave = onSave
    }

    private var saveTitle: String {
        draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add Step" : "Save Step"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Direction")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: 16) {
                            mealSheetTextField("Instruction", text: $draft.instruction, axis: .vertical)
                                .lineLimit(5...10)
                            mealSheetTextField("Timer Minutes", text: $draft.timerMinutesText, keyboard: .numberPad)
                            LabeledContent("Step Photo") {
                                Text("Coming Soon")
                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            }
                            .font(.body.weight(.medium))
                            .frame(minHeight: 44)
                        }
                        .padding(22)
                        .dashboardCard(cornerRadius: 26)

                        bottomActions
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Direction")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }

            Button {
                onSave(draft)
                dismiss()
            } label: {
                Text(saveTitle)
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .frame(maxWidth: .infinity)
        }
    }
}

private func mealSheetTextField(_ title: String, text: Binding<String>, axis: Axis = .horizontal, keyboard: UIKeyboardType = .default) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.secondaryText)
        TextField(title, text: text, axis: axis)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.sentences)
            .font(.body.weight(.medium))
            .foregroundStyle(HomeyDashboardTheme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, axis == .vertical ? 10 : 0)
            .frame(minHeight: axis == .vertical ? 112 : 56, alignment: axis == .vertical ? .topLeading : .center)
            .background(HomeyDashboardTheme.appBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder.opacity(0.9), lineWidth: 1)
            }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    var minimumItemWidth: CGFloat = 90
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumItemWidth), spacing: spacing)], alignment: .leading, spacing: spacing) {
            content
        }
    }
}

#Preview("Create Meal - iPad", traits: .landscapeLeft) {
    MealEditorView(mode: .create)
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
        .environment(\.homePermissions, HomePermissions(role: .owner))
}

#Preview("Create Meal - iPhone", traits: .portrait) {
    MealEditorView(mode: .create)
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
        .environment(\.homePermissions, HomePermissions(role: .owner))
}

#Preview("Validation State") {
    MealEditorView(mode: .create)
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
        .environment(\.homePermissions, HomePermissions(role: .member))
}
