import SwiftUI

struct CalendarCategoriesView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var homeService: HomeService

    var onClose: () -> Void = {}

    @StateObject private var viewModel = CalendarCategoriesViewModel()
    @State private var editMode: EditMode = .inactive
    @State private var isShowingAddSheet = false
    @State private var editingCategory: CalendarCategory?
    @State private var successMessage: String?
    @State private var isShowingError = false
    @State private var errorMessage: String?

    private var selectedHome: HomeSummary? {
        homeService.selectedHome()
    }

    private var currentHomeRole: HomeMemberRole? {
        if let currentMember = homeService.membersForSelectedHome().first(where: { $0.isCurrentUser }) {
            return currentMember.role
        }

        return selectedHome?.role
    }

    private var canManageCalendarCategories: Bool {
        currentHomeRole?.canManageCalendarCategories ?? false
    }

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if let successMessage {
                        CategoryStatusBanner(message: successMessage, style: .success)
                            .transition(.opacity)
                    }

                    if !canManageCalendarCategories && selectedHome != nil {
                        readOnlyBanner
                    }

                    categoriesCard
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshActiveHomeData()
            }
        }
        .task(id: selectedHome?.id) {
            await loadForActiveHome()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            CalendarCategoryEditorView(
                mode: .create,
                isSaving: viewModel.isSaving,
                isDeleting: false,
                onCancel: {
                    isShowingAddSheet = false
                },
                onSave: { name, colorHex, iconName in
                    await saveNewCategory(name: name, colorHex: colorHex, iconName: iconName)
                },
                onDelete: nil
            )
        }
        .sheet(item: $editingCategory) { category in
            CalendarCategoryEditorView(
                mode: .edit(category),
                isSaving: viewModel.isSaving,
                isDeleting: viewModel.isDeleting,
                onCancel: {
                    editingCategory = nil
                },
                onSave: { name, colorHex, iconName in
                    await updateCategory(category, name: name, colorHex: colorHex, iconName: iconName)
                },
                onDelete: {
                    await deleteCategory(category)
                }
            )
        }
        .alert("Calendar Categories", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .onChange(of: canManageCalendarCategories) { _, canManage in
            if !canManage {
                editMode = .inactive
                isShowingAddSheet = false
                editingCategory = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar Categories")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Organize shared events with home-wide colors and icons.")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            if canManageCalendarCategories {
                Button {
                    guard canManageCalendarCategories else {
                        handlePermissionDenied()
                        return
                    }

                    successMessage = nil
                    isShowingAddSheet = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus")
                        Text("Add Category")
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .frame(width: 180)
                .disabled(viewModel.isSaving)
            }

            Button {
                onClose()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var readOnlyBanner: some View {
        CategoryStatusBanner(
            message: "Calendar categories are managed by Home owners and admins.",
            style: .info
        )
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeading(
                    title: "Shared Categories",
                    subtitle: "These appear in the Calendar and event editor."
                )

                Spacer()

                if canManageCalendarCategories && !viewModel.categories.isEmpty {
                    Button(editMode == .active ? "Done" : "Reorder") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .buttonStyle(.plain)
                    .disabled(viewModel.isReordering)
                }
            }

            if selectedHome == nil {
                CategoryEmptyState(
                    systemImage: "house",
                    title: "Choose a Home",
                    message: "Select a Home before viewing calendar categories."
                )
            } else if viewModel.isLoading && viewModel.categories.isEmpty {
                loadingState
            } else if let message = viewModel.errorMessage, viewModel.categories.isEmpty {
                errorState(message: message)
            } else if viewModel.categories.isEmpty {
                CategoryEmptyState(
                    systemImage: "tag",
                    title: "No Categories",
                    message: canManageCalendarCategories ? "Add a category to organize shared events." : "No calendar categories have been created yet."
                )
            } else {
                categoryList
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
    }

    private var categoryList: some View {
        List {
            ForEach(viewModel.categories) { category in
                CategoryRow(
                    category: category,
                    canManage: canManageCalendarCategories,
                    isReordering: editMode == .active
                ) {
                    guard canManageCalendarCategories else {
                        return
                    }

                    successMessage = nil
                    editingCategory = category
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                guard canManageCalendarCategories else {
                    handlePermissionDenied()
                    return
                }

                Task {
                    let result = await viewModel.moveCategories(
                        from: source,
                        to: destination,
                        homeId: selectedHome?.id,
                        canManage: canManageCalendarCategories
                    )
                    handleMutationResult(result, successMessage: nil)
                }
            }
        }
        .environment(\.editMode, .constant(canManageCalendarCategories ? editMode : .inactive))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: CGFloat(max(viewModel.categories.count, 1)) * 74)
        .disabled(viewModel.isReordering)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(HomeyDashboardTheme.warmBrown)
            Text("Loading categories...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .accessibilityLabel("Loading calendar categories")
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 14) {
            CategoryEmptyState(systemImage: "exclamationmark.triangle", title: "Unable to Load Categories", message: message)

            Button("Retry") {
                Task {
                    await viewModel.reload()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadForActiveHome() async {
        await refreshMembersIfNeeded()
        await viewModel.load(homeId: selectedHome?.id)
    }

    private func refreshActiveHomeData() async {
        await refreshMembersIfNeeded(forceRefresh: true)
        await viewModel.reload()
    }

    private func refreshMembersIfNeeded(forceRefresh: Bool = false) async {
        guard let selectedHome,
              let currentUser = authenticationService.currentUser else {
            return
        }

        if forceRefresh || !homeService.hasLoadedMembersForSelectedHome() {
            await homeService.loadMembers(for: selectedHome.id, currentUser: currentUser, forceRefresh: true)
        }
    }

    private func saveNewCategory(name: String, colorHex: String, iconName: String?) async {
        guard canManageCalendarCategories else {
            handlePermissionDenied()
            return
        }

        let result = await viewModel.createCategory(
            homeId: selectedHome?.id,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
            canManage: canManageCalendarCategories
        )
        if result == .success {
            isShowingAddSheet = false
        }
        handleMutationResult(result, successMessage: "Category added")
    }

    private func updateCategory(_ category: CalendarCategory, name: String, colorHex: String, iconName: String?) async {
        guard canManageCalendarCategories else {
            handlePermissionDenied()
            return
        }

        let result = await viewModel.updateCategory(
            categoryId: category.id,
            name: name,
            colorHex: colorHex,
            iconName: iconName,
            canManage: canManageCalendarCategories
        )
        if result == .success {
            editingCategory = nil
        }
        handleMutationResult(result, successMessage: "Category updated")
    }

    private func deleteCategory(_ category: CalendarCategory) async {
        guard canManageCalendarCategories else {
            handlePermissionDenied()
            return
        }

        let result = await viewModel.deleteCategory(categoryId: category.id, canManage: canManageCalendarCategories)
        if result == .success {
            editingCategory = nil
        }
        handleMutationResult(result, successMessage: "Category deleted")
    }

    private func handleMutationResult(_ result: CalendarCategoryMutationResult, successMessage message: String?) {
        switch result {
        case .success:
            if let message {
                withAnimation(.easeInOut(duration: 0.2)) {
                    successMessage = message
                }
            }
        case .permissionDenied:
            handlePermissionDenied()
        case .failure:
            showError(viewModel.errorMessage ?? "Please try again.")
        }
    }

    private func handlePermissionDenied() {
        editMode = .inactive
        isShowingAddSheet = false
        editingCategory = nil
        showError(CalendarServiceError.categoryPermissionDenied.localizedDescription)

        Task {
            await refreshActiveHomeData()
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }
}

private struct CategoryRow: View {
    let category: CalendarCategory
    let canManage: Bool
    let isReordering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color(hex: category.colorHex) ?? HomeyDashboardTheme.lavenderAccent)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(HomeyDashboardTheme.cardBackground, lineWidth: 2)
                    }
                    .shadow(color: HomeyDashboardTheme.shadow.opacity(0.5), radius: 5, x: 0, y: 2)

                if let iconName = category.iconName, !iconName.isEmpty {
                    Image(systemName: iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 28)
                }

                Text(category.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(1)

                Spacer()

                if canManage && !isReordering {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(HomeyDashboardTheme.appBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canManage || isReordering)
        .accessibilityLabel(category.name)
    }
}

private struct CalendarCategoryEditorView: View {
    enum Mode {
        case create
        case edit(CalendarCategory)

        var title: String {
            switch self {
            case .create:
                "Add Category"
            case .edit:
                "Edit Category"
            }
        }

        var saveTitle: String {
            switch self {
            case .create:
                "Save"
            case .edit:
                "Save Changes"
            }
        }

        var existingCategory: CalendarCategory? {
            if case let .edit(category) = self {
                return category
            }
            return nil
        }
    }

    let mode: Mode
    let isSaving: Bool
    let isDeleting: Bool
    let onCancel: () -> Void
    let onSave: (String, String, String?) async -> Void
    let onDelete: (() async -> Void)?

    @State private var name: String
    @State private var colorHex: String
    @State private var iconName: String?
    @State private var validationMessage: String?
    @State private var isShowingDeleteConfirmation = false

    private let colors = [
        "4F7CAC", "F2C14E", "5C946E", "E76F51", "8E6CFF", "43AA8B",
        "577590", "F94144", "90BE6D", "9E9E9E", "EC6F91", "8B6F47"
    ]
    private let icons: [String?] = [
        nil,
        "house.fill", "graduationcap.fill", "briefcase.fill", "figure.run", "cross.case.fill",
        "fork.knife", "checklist", "gift.fill", "party.popper.fill", "tag.fill", "car.fill",
        "airplane", "cart.fill", "person.2.fill", "heart.fill", "calendar"
    ]

    init(
        mode: Mode,
        isSaving: Bool,
        isDeleting: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, String, String?) async -> Void,
        onDelete: (() async -> Void)?
    ) {
        self.mode = mode
        self.isSaving = isSaving
        self.isDeleting = isDeleting
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: mode.existingCategory?.name ?? "")
        _colorHex = State(initialValue: mode.existingCategory?.colorHex ?? "4F7CAC")
        _iconName = State(initialValue: mode.existingCategory?.iconName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving && !isDeleting && !trimmedName.isEmpty && isValidColorHex(colorHex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        editorField
                        colorPicker
                        iconPicker

                        if let validationMessage {
                            CategoryStatusBanner(message: validationMessage, style: .error)
                        }

                        Button {
                            Task {
                                await save()
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(mode.saveTitle)
                            }
                        }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                        .disabled(!canSave)

                        if case .edit = mode, onDelete != nil {
                            Button(role: .destructive) {
                                isShowingDeleteConfirmation = true
                            } label: {
                                if isDeleting {
                                    ProgressView()
                                        .tint(HomeyDashboardTheme.destructiveRed)
                                } else {
                                    Text("Delete Category")
                                }
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(HomeyDashboardTheme.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .buttonStyle(.plain)
                            .disabled(isSaving || isDeleting)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving || isDeleting)
                }
            }
            .confirmationDialog(
                "Delete Category?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Keep Category", role: .cancel) {}
                Button("Delete Category", role: .destructive) {
                    Task {
                        await onDelete?()
                    }
                }
            } message: {
                Text("Existing calendar events will remain, but they will become uncategorized.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var editorField: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Name")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            TextField("Category name", text: $name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .font(.body.weight(.medium))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(HomeyDashboardTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 12), count: 6), alignment: .leading, spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Button {
                        colorHex = color
                    } label: {
                        Circle()
                            .fill(Color(hex: color) ?? HomeyDashboardTheme.lavenderAccent)
                            .frame(width: 38, height: 38)
                            .overlay {
                                Circle()
                                    .stroke(colorHex == color ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.softBorder, lineWidth: colorHex == color ? 3 : 1)
                            }
                            .shadow(color: HomeyDashboardTheme.shadow.opacity(0.45), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(color)")
                }
            }
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(54), spacing: 10), count: 6), alignment: .leading, spacing: 10) {
                ForEach(icons.indices, id: \.self) { index in
                    let icon = icons[index]
                    Button {
                        iconName = icon
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(iconName == icon ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.cardBackground.opacity(0.72))
                                .frame(width: 50, height: 50)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(iconName == icon ? HomeyDashboardTheme.warmBrown.opacity(0.58) : HomeyDashboardTheme.softBorder, lineWidth: 1)
                                }

                            if let icon {
                                Image(systemName: icon)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            } else {
                                Text("None")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon ?? "No icon")
                }
            }
        }
    }

    private func save() async {
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a category name."
            return
        }

        guard isValidColorHex(colorHex) else {
            validationMessage = "Choose a valid category color."
            return
        }

        validationMessage = nil
        await onSave(trimmedName, colorHex, iconName)
    }

    private func isValidColorHex(_ value: String) -> Bool {
        value.count == 6 && Int(value, radix: 16) != nil
    }
}

private struct CategoryStatusBanner: View {
    enum Style {
        case success
        case info
        case error
    }

    let message: String
    let style: Style

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(message)
    }

    private var systemImage: String {
        switch style {
        case .success:
            "checkmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .error:
            "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch style {
        case .success:
            HomeyDashboardTheme.sageAccent
        case .info:
            HomeyDashboardTheme.warmBrown
        case .error:
            HomeyDashboardTheme.destructiveRed
        }
    }

    private var backgroundOpacity: Double {
        switch style {
        case .success:
            0.14
        case .info:
            0.10
        case .error:
            0.10
        }
    }
}

private struct CategoryEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HomeyDashboardTheme.selectedSidebarBackground)
                    .frame(width: 58, height: 58)

                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Calendar Categories") {
    CalendarCategoriesView()
        .environmentObject(AuthenticationService())
        .environmentObject(HomeService())
}
