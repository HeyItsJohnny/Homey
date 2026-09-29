import SwiftUI

struct HomeSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var homeName = ""
    @State private var timezone = TimeZone.current.identifier
    @State private var weekStartsOn = 1
    @State private var original = SettingsValues(name: "", timezone: "", weekStartsOn: 1)
    @State private var showingTimezonePicker = false
    @State private var clearAction: HomeClearAction?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var home: HomeSummary? { session.activeHome }
    private var canEdit: Bool { session.activeRole == .owner || session.activeRole == .admin }
    private var isOwner: Bool { session.activeRole == .owner }
    private var values: SettingsValues {
        SettingsValues(
            name: homeName.trimmingCharacters(in: .whitespacesAndNewlines),
            timezone: timezone,
            weekStartsOn: weekStartsOn
        )
    }
    private var canSave: Bool { canEdit && values != original && !values.name.isEmpty && !isSaving }

    var body: some View {
        ZStack {
            HomeyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !canEdit, home != nil {
                        infoBanner("Home settings are managed by Home owners and admins.", systemImage: "lock.fill")
                    }
                    if let statusMessage { infoBanner(statusMessage, systemImage: "checkmark.circle.fill", tint: HomeyColors.success) }
                    homeCard
                    membersCard
                    calendarCard
                    if isOwner { dataManagementCard }
                }
                .padding(18)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: home?.id) { loadHome() }
        .sheet(isPresented: $showingTimezonePicker) {
            TimezoneSettingsPicker(selection: $timezone)
        }
        .sheet(item: $clearAction) { action in
            if let home {
                ClearHomeDataSheet(home: home, action: action) { result in
                    statusMessage = result
                    clearAction = nil
                }
            }
        }
        .alert("Settings", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("People", subtitle: "Everyone connected to this Home")
            if home != nil {
                NavigationLink {
                    HomeMembersView()
                } label: {
                    settingsRow(title: "Members", value: canEdit ? "View and invite" : "View household", icon: "person.2.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .homeyCard()
    }

    private var homeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Home", subtitle: "Shared details and calendar preferences")

            VStack(alignment: .leading, spacing: 7) {
                Text("Home Name").font(.subheadline.weight(.semibold))
                TextField("Home name", text: $homeName)
                    .textInputAutocapitalization(.words)
                    .homeyTextField()
                    .disabled(!canEdit || isSaving)
                if values.name.isEmpty { Text("Home name is required.").font(.caption).foregroundStyle(HomeyColors.danger) }
            }

            Button { showingTimezonePicker = true } label: {
                settingsRow(title: "Timezone", value: timezoneDisplayName, icon: "globe.americas.fill")
            }
            .buttonStyle(.plain)
            .disabled(!canEdit || isSaving)

            VStack(alignment: .leading, spacing: 8) {
                Text("Week Starts On").font(.subheadline.weight(.semibold))
                Picker("Week Starts On", selection: $weekStartsOn) {
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(!canEdit || isSaving)
            }

            if canEdit {
                Button { Task { await save() } } label: {
                    Group {
                        if isSaving { ProgressView().tint(.white) }
                        else { Text("Save Changes") }
                    }
                }
                .buttonStyle(HomeyButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.55)
            }
        }
        .homeyCard()
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Calendar", subtitle: "Shared colors and icons for events")
            if let home {
                NavigationLink {
                    CalendarCategoriesSettingsView(homeID: home.id, canManage: canEdit)
                } label: {
                    settingsRow(title: "Calendar Categories", value: canEdit ? "Manage" : "View", icon: "tag.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .homeyCard()
    }

    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Data Management", subtitle: "These owner-only actions cannot be undone", tint: HomeyColors.danger)
            clearButton(.meals)
            Divider()
            clearButton(.calendar)
            Divider()
            clearButton(.chores)
        }
        .homeyCard()
    }

    private func clearButton(_ action: HomeClearAction) -> some View {
        Button(role: .destructive) { clearAction = action } label: {
            HStack(spacing: 13) {
                Image(systemName: action.icon).frame(width: 34, height: 34).background(HomeyColors.danger.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title).font(.headline)
                    Text(action.summary).font(.caption).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadHome() {
        guard let home else { return }
        let loaded = SettingsValues(
            name: home.name,
            timezone: home.timezone.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 } ?? TimeZone.current.identifier,
            weekStartsOn: home.weekStartsOn == 2 ? 2 : 1
        )
        homeName = loaded.name
        timezone = loaded.timezone
        weekStartsOn = loaded.weekStartsOn
        original = loaded
        statusMessage = nil
    }

    private func save() async {
        guard canSave, let home, let userID = session.currentUser?.id else { return }
        isSaving = true
        statusMessage = nil
        let saved = await session.homes.updateHomeSettings(
            homeID: home.id,
            name: values.name,
            timezone: values.timezone,
            weekStartsOn: values.weekStartsOn,
            userID: userID
        )
        isSaving = false
        guard saved else {
            errorMessage = session.homes.errorMessage ?? "Unable to save Home settings."
            return
        }
        original = values
        homeName = values.name
        statusMessage = "Changes saved."
        postSettingsRefreshNotifications()
    }

    private var timezoneDisplayName: String {
        let city = timezone.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? timezone
        return "\(city) (\(timezone))"
    }

    private func sectionTitle(_ title: String, subtitle: String, tint: Color = HomeyColors.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(HomeyTypography.title).foregroundStyle(tint)
            Text(subtitle).font(.subheadline).foregroundStyle(HomeyColors.secondaryText)
        }
    }

    private func settingsRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).foregroundStyle(HomeyColors.primary).frame(width: 38, height: 38).background(HomeyColors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                Text(value).font(.caption).foregroundStyle(HomeyColors.secondaryText).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoBanner(_ message: String, systemImage: String, tint: Color = HomeyColors.primary) -> some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SettingsValues: Equatable {
    let name: String
    let timezone: String
    let weekStartsOn: Int
}

private func postSettingsRefreshNotifications() {
    NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
    NotificationCenter.default.post(name: Notification.Name("homeyMealsDidChange"), object: nil)
    NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
}

private struct TimezoneSettingsPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var search = ""

    private var timezones: [String] {
        guard !search.isEmpty else { return TimeZone.knownTimeZoneIdentifiers }
        return TimeZone.knownTimeZoneIdentifiers.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(timezones, id: \.self) { identifier in
                Button {
                    selection = identifier
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? identifier)
                                .foregroundStyle(HomeyColors.text)
                            Text(identifier).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                        }
                        Spacer()
                        if identifier == selection { Image(systemName: "checkmark").foregroundStyle(HomeyColors.primary) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search timezones")
            .navigationTitle("Timezone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private enum HomeClearAction: String, Identifiable {
    case meals, calendar, chores
    var id: String { rawValue }
    var title: String { switch self { case .meals: "Clear Meals"; case .calendar: "Clear Calendar"; case .chores: "Clear Chores" } }
    var icon: String { switch self { case .meals: "fork.knife"; case .calendar: "calendar.badge.minus"; case .chores: "checklist" } }
    var summary: String {
        switch self {
        case .meals: "Home recipes, meal plans, and linked meal events"
        case .calendar: "Regular events; meal and chore data stay intact"
        case .chores: "Chores, rooms, rewards, approvals, and points activity"
        }
    }
    var message: String {
        switch self {
        case .meals:
            "This permanently deletes this Home's recipes, recipe details, photos, favorites, collections, meal plans, and linked meal calendar events. Global and Community Recipes are preserved."
        case .calendar:
            "This permanently deletes regular calendar events for this Home. Meal-linked and chore-linked events, meal plans, recipes, chores, and rewards are preserved."
        case .chores:
            "This permanently deletes all chore templates, schedules, occurrences, assignments, claims, submissions, approvals, points activity, rooms, chore categories, rewards, redemptions, and linked chore calendar events for this Home."
        }
    }
}

private struct ClearHomeDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    let home: HomeSummary
    let action: HomeClearAction
    let onSuccess: (String) -> Void
    @State private var confirmation = ""
    @State private var isClearing = false
    @State private var errorMessage: String?
    private let repository = HomeSettingsRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(HomeyColors.danger)
                    Text(action.message).foregroundStyle(HomeyColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Text("This affects only \(home.name) and cannot be undone.").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type CLEAR to continue").font(.subheadline.weight(.semibold))
                        TextField("CLEAR", text: $confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled().homeyTextField()
                    }
                    if let errorMessage { HomeyErrorView(message: errorMessage) }
                    Button(role: .destructive) { Task { await clear() } } label: {
                        HStack {
                            if isClearing { ProgressView().tint(.white) }
                            Text(isClearing ? "Clearing…" : action.title)
                        }
                        .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52).foregroundStyle(.white)
                        .background(HomeyColors.danger, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(confirmation != "CLEAR" || isClearing)
                    .opacity(confirmation == "CLEAR" && !isClearing ? 1 : 0.5)
                }
                .padding(22)
            }
            .background(HomeyColors.background.ignoresSafeArea())
            .navigationTitle(action.title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isClearing)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isClearing) } }
        }
        .presentationDetents([.large])
    }

    private func clear() async {
        guard confirmation == "CLEAR", !isClearing else { return }
        isClearing = true
        errorMessage = nil
        do {
            let message: String
            switch action {
            case .meals:
                let result = try await repository.clearMeals(homeID: home.id)
                message = "Meals cleared (\(result.mealsDeleted) Home recipe\(result.mealsDeleted == 1 ? "" : "s"))."
                NotificationCenter.default.post(name: Notification.Name("homeyMealsDidChange"), object: nil)
                NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
            case .calendar:
                let result = try await repository.clearCalendar(homeID: home.id)
                message = "Calendar cleared (\(result.calendarEventsDeleted) event\(result.calendarEventsDeleted == 1 ? "" : "s"))."
                NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
            case .chores:
                let result = try await repository.clearChores(homeID: home.id)
                message = "Chore data cleared (\(result.choreDefinitionsDeleted) chore\(result.choreDefinitionsDeleted == 1 ? "" : "s"))."
                NotificationCenter.default.post(name: Notification.Name("homeyChoresDidChange"), object: nil)
                NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
            }
            isClearing = false
            onSuccess(message)
        } catch {
            isClearing = false
            errorMessage = error.localizedDescription
        }
    }
}

struct CalendarCategoriesSettingsView: View {
    let homeID: UUID
    let canManage: Bool
    @State private var categories: [PhoneCalendarCategory] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var editor: CategoryEditorMode?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive
    private let repository = HomeSettingsRepository()

    var body: some View {
        ZStack {
            HomeyBackground()
            Group {
                if isLoading && categories.isEmpty { ProgressView("Loading categories…") }
                else if categories.isEmpty { ContentUnavailableView("No Calendar Categories", systemImage: "tag", description: Text(canManage ? "Add a category to organize shared events." : "No categories are available.")) }
                else {
                    List {
                        ForEach(categories) { category in
                            Button { if canManage { editor = .edit(category) } } label: { categoryRow(category) }
                                .buttonStyle(.plain)
                                .disabled(!canManage || isSaving)
                        }
                        .onMove(perform: move)
                    }
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, $editMode)
                }
            }
        }
        .navigationTitle("Calendar Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(editMode == .active ? "Done" : "Reorder") { editMode = editMode == .active ? .inactive : .active }
                    Button { editor = .create } label: { Image(systemName: "plus") }.accessibilityLabel("Add Category")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editor) { mode in
            CategoryEditorSheet(mode: mode, isSaving: isSaving, onSave: saveCategory, onDelete: deleteCategory)
        }
        .alert("Calendar Categories", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func categoryRow(_ category: PhoneCalendarCategory) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(settingsColor(category.colorHex)).frame(width: 42, height: 42)
                Image(systemName: category.iconName ?? "tag.fill").foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name).font(.headline).foregroundStyle(HomeyColors.text)
                Text(category.isProtectedSystemCategory ? "Homey system category · color can be changed" : "Custom category")
                    .font(.caption).foregroundStyle(HomeyColors.secondaryText)
            }
            Spacer()
            if canManage && editMode != .active { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 5)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { categories = try await repository.fetchCategories(homeID: homeID) }
        catch { errorMessage = error.localizedDescription }
    }

    private func saveCategory(name: String, color: String, icon: String?) async {
        guard canManage, let editor else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch editor {
            case .create: try await repository.createCategory(homeID: homeID, name: name, colorHex: color, iconName: icon)
            case .edit(let category): try await repository.updateCategory(category, name: name, colorHex: color, iconName: icon)
            }
            self.editor = nil
            await load()
            NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteCategory(_ category: PhoneCalendarCategory) async {
        guard canManage else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.deleteCategory(category)
            editor = nil
            await load()
            NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: nil)
        } catch { errorMessage = error.localizedDescription }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard canManage else { return }
        categories.move(fromOffsets: source, toOffset: destination)
        let ids = categories.map(\.id)
        isSaving = true
        Task {
            do { try await repository.reorderCategories(homeID: homeID, categoryIDs: ids) }
            catch { errorMessage = error.localizedDescription; await load() }
            isSaving = false
        }
    }
}

private enum CategoryEditorMode: Identifiable {
    case create
    case edit(PhoneCalendarCategory)
    var id: String { switch self { case .create: "create"; case .edit(let category): category.id.uuidString } }
    var category: PhoneCalendarCategory? { if case .edit(let category) = self { category } else { nil } }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mode: CategoryEditorMode
    let isSaving: Bool
    let onSave: (String, String, String?) async -> Void
    let onDelete: (PhoneCalendarCategory) async -> Void
    @State private var name: String
    @State private var color: String
    @State private var icon: String?
    @State private var showingDelete = false
    private let colors = ["4F7CAC", "F2C14E", "5C946E", "E76F51", "8E6CFF", "43AA8B", "577590", "F94144", "90BE6D", "9E9E9E", "EC6F91", "8B6F47"]
    private let icons = ["tag.fill", "house.fill", "graduationcap.fill", "briefcase.fill", "figure.run", "cross.case.fill", "fork.knife", "checklist", "gift.fill", "party.popper.fill", "car.fill", "airplane", "cart.fill", "person.2.fill", "heart.fill", "calendar"]

    init(mode: CategoryEditorMode, isSaving: Bool, onSave: @escaping (String, String, String?) async -> Void, onDelete: @escaping (PhoneCalendarCategory) async -> Void) {
        self.mode = mode; self.isSaving = isSaving; self.onSave = onSave; self.onDelete = onDelete
        _name = State(initialValue: mode.category?.name ?? "")
        _color = State(initialValue: mode.category?.colorHex ?? "4F7CAC")
        _icon = State(initialValue: mode.category?.iconName ?? "tag.fill")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    if mode.category?.canRename == false { LabeledContent("System Category", value: name) }
                    else { TextField("Category name", text: $name) }
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(colors, id: \.self) { value in
                            Button { color = value } label: {
                                Circle().fill(settingsColor(value)).frame(width: 34, height: 34).overlay { Circle().stroke(color == value ? HomeyColors.text : .clear, lineWidth: 3) }
                            }.buttonStyle(.plain).accessibilityLabel("Color \(value)")
                        }
                    }.padding(.vertical, 6)
                }
                if mode.category?.canChangeIcon != false {
                    Section("Icon") {
                        Picker("Icon", selection: Binding(get: { icon ?? "tag.fill" }, set: { icon = $0 })) {
                            ForEach(icons, id: \.self) { value in Label(value, systemImage: value).tag(value) }
                        }
                    }
                } else {
                    Section("Icon") { Label("System category icons are fixed", systemImage: icon ?? "tag.fill") }
                }
                if let category = mode.category, category.canDelete {
                    Section { Button("Delete Category", role: .destructive) { showingDelete = true } }
                }
            }
            .navigationTitle(mode.category == nil ? "Add Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await onSave(name, color, icon) } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .confirmationDialog("Delete Category?", isPresented: $showingDelete, titleVisibility: .visible) {
                Button("Delete Category", role: .destructive) { if let category = mode.category { Task { await onDelete(category) } } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Existing events will remain but become uncategorized.") }
        }
    }
}

private func settingsColor(_ hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return HomeyColors.primary }
    return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}
