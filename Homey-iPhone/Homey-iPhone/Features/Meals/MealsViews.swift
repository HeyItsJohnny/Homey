import PhotosUI
import SwiftUI
import Combine

@MainActor final class MealsViewModel: ObservableObject {
    @Published var homeRecipes: [HomeyMeal] = []
    @Published private(set) var recipesRevision = 0
    @Published var favoriteIDs: Set<UUID> = []
    @Published var planned: [PlannedMeal] = []
    @Published var isLoading = false
    @Published private(set) var isAutoPlanning = false
    @Published var errorMessage: String?
    private let service = MealsService()
    func load(home: HomeSummary) async { isLoading=true; defer{isLoading=false}; do { async let h=service.homeRecipes(homeId:home.id); async let f=service.favoriteIDs(); let week=Self.week(containing:Date(),home:home); async let p=service.plannedMeals(home:home,week:week); (homeRecipes,favoriteIDs,planned)=try await(h,f,p); recipesRevision += 1 } catch { errorMessage=error.localizedDescription } }
    func refreshRecipesAfterSave(home: HomeSummary) async throws {
        recipesRevision += 1
        homeRecipes = try await service.homeRecipes(homeId: home.id)
    }
    func refreshPlan(home: HomeSummary, containing date: Date = Date()) async {
        do {
            planned = try await service.plannedMeals(home: home, week: Self.week(containing: date, home: home))
            #if DEBUG
            let calendar = Self.calendar(home)
            let selectedDayMeals = planned.filter { calendar.isDate($0.startsAt, inSameDayAs: date) }
            let dateText = date.formatted(.iso8601.year().month().day())
            print("[MealPlan] Loaded date=\(dateText) total=\(selectedDayMeals.count)")
            for type in [MealType.breakfast, .lunch, .dinner] {
                print("[MealPlan] \(type.rawValue)=\(selectedDayMeals.count { $0.mealType == type })")
            }
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    func toggleFavorite(_ meal: HomeyMeal) async { let next = !favoriteIDs.contains(meal.id); do { try await service.setFavorite(mealId:meal.id,isFavorite:next); if next { favoriteIDs.insert(meal.id) } else { favoriteIDs.remove(meal.id) } } catch { errorMessage=error.localizedDescription } }
    @discardableResult func schedule(_ meal: HomeyMeal,type:MealType,day:Date,home:HomeSummary) async -> Bool {
        do {
            try await service.schedule(meal,type:type,day:day,home:home)
            #if DEBUG
            print("[MealPlan] Added recipe=\(meal.id.uuidString)")
            print("[MealPlan] mealType=\(type.rawValue)")
            print("[MealPlan] date=\(day.formatted(.iso8601.year().month().day()))")
            print("[MealPlan] refreshing day")
            #endif
            await refreshPlan(home:home, containing:day)
            return true
        } catch {
            #if DEBUG
            print("Meal plan scheduling failed: \(String(reflecting: error))")
            #endif
            errorMessage = "Homey couldn't add this recipe to your meal plan. Please try again."
            return false
        }
    }
    @discardableResult func replace(_ item: PlannedMeal, with meal: HomeyMeal, type: MealType, day: Date, home: HomeSummary) async -> Bool {
        do {
            // Create first so a failed replacement never removes the existing entry.
            try await service.schedule(meal, type: type, day: day, home: home)
            try await service.removePlanned(item.eventId)
            await refreshPlan(home: home, containing: day)
            return true
        } catch {
            await refreshPlan(home: home, containing: day)
            errorMessage = "Homey couldn't change this planned recipe. Please try again."
            return false
        }
    }
    func remove(_ item: PlannedMeal,home:HomeSummary, containing date:Date = Date()) async { do { try await service.removePlanned(item.eventId); await refreshPlan(home:home, containing:date) } catch { errorMessage=error.localizedDescription } }
    func autoPlanDay(home: HomeSummary, date: Date) async {
        guard !isAutoPlanning else { return }
        isAutoPlanning = true
        defer { isAutoPlanning = false }

        let calendar = Self.calendar(home)
        let selectedDay = calendar.startOfDay(for: date)
        let visibleTypes: [MealType] = [.breakfast, .lunch, .dinner]

        #if DEBUG
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDay)
        let dateText = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        print("[AutoPlan] selectedDate=\(dateText)")
        print("[AutoPlan] homeID=\(home.id.uuidString)")
        #endif

        do {
            planned = try await service.plannedMeals(home: home, week: Self.week(containing: selectedDay, home: home))
        } catch {
            errorMessage = "Homey couldn't load this day's meals. Please try again."
            return
        }

        let dayMeals = planned.filter { calendar.isDate($0.startsAt, inSameDayAs: selectedDay) }
        let missingTypes = visibleTypes.filter { type in
            !dayMeals.contains { $0.mealType == type }
        }

        #if DEBUG
        for type in visibleTypes {
            let count = dayMeals.count { $0.mealType == type }
            print("[AutoPlan] \(type.rawValue)Count=\(count)")
            if count > 0 { print("[AutoPlan] \(type.title) already planned - skipping") }
        }
        print("[AutoPlan] missingTypes=\(missingTypes.map(\.rawValue).joined(separator: ","))")
        #endif

        guard !missingTypes.isEmpty else {
            errorMessage = "All meals are planned for this day."
            return
        }
        guard !homeRecipes.isEmpty else {
            errorMessage = "Add some Home Recipes before using Auto Plan."
            return
        }

        var usedRecipeIDs = Set(dayMeals.map(\.meal.id))
        var created = 0
        var failed = 0
        var unavailableTypes: [MealType] = []

        for type in missingTypes {
            let eligible = homeRecipes.filter { $0.mealTypes.isEmpty || $0.mealTypes.contains(type) }
            #if DEBUG
            print("[AutoPlan] \(type.title) eligibleRecipes=\(eligible.count)")
            #endif
            guard !eligible.isEmpty else {
                unavailableTypes.append(type)
                continue
            }

            let unused = eligible.filter { !usedRecipeIDs.contains($0.id) }
            guard let selected = (unused.isEmpty ? eligible : unused).randomElement() else { continue }
            #if DEBUG
            print("[AutoPlan] \(type.title) selected=\(selected.id.uuidString)")
            #endif
            do {
                try await service.schedule(selected, type: type, day: selectedDay, home: home)
                usedRecipeIDs.insert(selected.id)
                created += 1
            } catch {
                failed += 1
                #if DEBUG
                print("[AutoPlan] FAILED mealType=\(type.rawValue)")
                print("[AutoPlan] message=\(error.localizedDescription)")
                #endif
            }
        }

        await refreshPlan(home: home, containing: selectedDay)
        #if DEBUG
        print("[AutoPlan] Complete created=\(created) skipped=\(visibleTypes.count - missingTypes.count + unavailableTypes.count)")
        #endif

        if failed > 0 {
            errorMessage = created > 0
                ? "Homey planned some meals, but couldn't finish the entire day."
                : "Homey couldn't plan this day. Please try again."
        } else if created == 0, !unavailableTypes.isEmpty {
            let names = unavailableTypes.map(\.title).joined(separator: ", ")
            errorMessage = "No eligible \(names) recipes are available yet."
        }
    }
    func autoPlan(home: HomeSummary, types: Set<MealType>, favoritesOnly: Bool) async { let calendar=Self.calendar(home); let week=Self.week(containing:Date(),home:home); let candidates=(favoritesOnly ? homeRecipes.filter{favoriteIDs.contains($0.id)}:homeRecipes); guard !candidates.isEmpty else { errorMessage="Add recipes to this Home before auto-planning."; return }; var index=0; for offset in 0..<7 { guard let day=calendar.date(byAdding:.day,value:offset,to:week.start), day >= calendar.startOfDay(for:Date()) else { continue }; for type in types { let occupied=planned.contains{calendar.isDate($0.startsAt,inSameDayAs:day) && $0.mealType == type}; guard !occupied else {continue}; let preferred=candidates.filter{$0.mealTypes.isEmpty || $0.mealTypes.contains(type)}; let pool=preferred.isEmpty ? candidates:preferred; do { try await service.schedule(pool[index % pool.count],type:type,day:day,home:home); index += 1 } catch { errorMessage=error.localizedDescription; await refreshPlan(home:home); return } }; await refreshPlan(home:home) } }
    static func calendar(_ home:HomeSummary)->Calendar { var c=Calendar(identifier:.gregorian); c.timeZone=home.timezone.flatMap(TimeZone.init(identifier:)) ?? .current; c.firstWeekday=home.weekStartsOn == 2 ? 2:1; return c }
    static func week(containing date:Date,home:HomeSummary)->DateInterval { let c=calendar(home); return c.dateInterval(of:.weekOfYear,for:date) ?? .init(start:c.startOfDay(for:date),duration:604800) }
}

struct MealsRootView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = MealsViewModel()
    @State private var section = 0
    @State private var showAdd = false
    @State private var creationPresentation: RecipeCreationPresentation?
    @State private var pendingEditorPresentation: RecipeCreationPresentation?
    @State private var selectedMealPlanDate = Date()
    @State private var comingSoonFeature: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                VStack(spacing: 12) {
                    HStack {
                        Text("Meals")
                            .font(.title.bold())
                            .foregroundStyle(HomeyColors.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if section == 0, session.activeHome != nil {
                            Menu {
                                Button("Auto Plan", systemImage: "wand.and.sparkles") {
                                    guard let home = session.activeHome else { return }
                                    Task { await model.autoPlanDay(home: home, date: selectedMealPlanDate) }
                                }
                                .disabled(model.isAutoPlanning)
                                Button("Leftovers", systemImage: "takeoutbag.and.cup.and.straw") { comingSoonFeature = "Leftovers" }
                                Button("Add to Groceries", systemImage: "cart.badge.plus") { comingSoonFeature = "Add to Groceries" }
                            } label: {
                                Group {
                                    if model.isAutoPlanning { ProgressView().tint(HomeyColors.primary) }
                                    else { Image(systemName: "ellipsis").font(.title3.weight(.semibold)) }
                                }
                                .foregroundStyle(HomeyColors.primary)
                                .frame(width: 44, height: 44)
                                .background(HomeyColors.field, in: Circle())
                            }
                            .accessibilityLabel("Meal plan actions")
                        } else if section == 1 {
                            Button { showAdd = true } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(HomeyColors.primary)
                                    .frame(width: 44, height: 44)
                                    .background(HomeyColors.field, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add Recipe")
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    Picker("Meals", selection: $section) {
                        Text("Meal Plan").tag(0)
                        Text("Recipes").tag(1)
                        Text("Explore").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if let home = session.activeHome {
                        if section == 0 {
                            MealPlanView(home: home, model: model, selectedDate: $selectedMealPlanDate)
                        } else if section == 1 {
                            RecipeLibraryView(home: home, model: model, onAddRecipe: { showAdd = true }, onExplore: { section = 2 })
                        } else {
                            ExploreRecipesView(home: home, model: model).id(home.id)
                        }
                    } else {
                        ContentUnavailableView("Choose a Home", systemImage: "house")
                    }
                }
            }
            .navigationTitle("Meals")
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Add Recipe", isPresented: $showAdd, titleVisibility: .visible) {
                Button("New Recipe") { creationPresentation = .manual() }
                Button("From Website") { creationPresentation = .website() }
                Button("Scan") { creationPresentation = .scan() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $creationPresentation, onDismiss: {
                if let editor = pendingEditorPresentation {
                    pendingEditorPresentation = nil
                    creationPresentation = editor
                }
            }) { presentation in
                if let home = session.activeHome {
                    switch presentation.content {
                    case .website:
                        RecipeImportView(home: home) { draft in
                            pendingEditorPresentation = .imported(draft)
                            creationPresentation = nil
                        }
                    case .editor(let initialDraft):
                        RecipeEditorView(home: home, model: model, initialDraft: initialDraft)
                            .id(presentation.id)
                    case .scan:
                        RecipeScanComingSoonView()
                    }
                }
            }
            .task(id: session.activeHome?.id) {
                if let home = session.activeHome {
                    selectedMealPlanDate = Self.startOfToday(home: home)
                    await model.load(home: home)
                }
            }
            .refreshable {
                if let home = session.activeHome { await model.load(home: home) }
            }
            .alert("Meals", isPresented: .init(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.errorMessage ?? "") }
            .alert(
                "\(comingSoonFeature ?? "Feature") Coming Soon",
                isPresented: .init(get: { comingSoonFeature != nil }, set: { if !$0 { comingSoonFeature = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This feature is coming soon.")
            }
        }
    }

    private static func startOfToday(home: HomeSummary) -> Date {
        MealsViewModel.calendar(home).startOfDay(for: Date())
    }
}

struct RecipePickerView: View {
    let recipes: [HomeyMeal]
    let favorites: Set<UUID>
    var mealTypeFilter: MealType? = nil
    var isLoading = false
    let select: (HomeyMeal) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var selectingID: UUID?
    @State private var errorMessage: String?

    private var filteredRecipes: [HomeyMeal] {
        recipes.filter { meal in
            (mealTypeFilter.map { meal.mealTypes.contains($0) } ?? true) &&
            (!favoritesOnly || favorites.contains(meal.id)) &&
            (search.isEmpty || meal.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HomeyColors.secondaryText)
                    TextField("Search recipes...", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(HomeyColors.secondaryText).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 52)
                .background(HomeyColors.field.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)

                if isLoading && recipes.isEmpty {
                    Spacer()
                    ProgressView("Loading recipes…").tint(HomeyColors.recipeGreenAccent)
                    Spacer()
                } else if filteredRecipes.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label(favoritesOnly ? "No favorite recipes found" : "No recipes found", systemImage: "fork.knife")
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        if !search.isEmpty || favoritesOnly {
                            Button("Clear search and filters") { search = ""; favoritesOnly = false }
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRecipes) { meal in
                                RecipePickerRow(meal: meal, loading: selectingID == meal.id) {
                                    Task { await choose(meal) }
                                }
                                .disabled(selectingID != nil)
                            }
                        }.padding(.horizontal, 16).padding(.bottom, 24)
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
            .background(HomeyColors.recipeBackground.ignoresSafeArea())
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { favoritesOnly.toggle() } label: {
                        Label("Favorites", systemImage: favoritesOnly ? "heart.fill" : "heart")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 36)
                            .foregroundStyle(favoritesOnly ? .white : HomeyColors.recipeGreenAccent)
                            .background(favoritesOnly ? HomeyColors.recipeGreenAccent : HomeyColors.recipeGreenAccent.opacity(0.1), in: Capsule())
                    }.buttonStyle(.plain).accessibilityValue(favoritesOnly ? "On" : "Off")
                }
            }
            .interactiveDismissDisabled(selectingID != nil)
            .alert("Couldn't Add Recipe", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var emptyDescription: String {
        if favoritesOnly { return "Try turning off Favorites or clearing your search." }
        if mealTypeFilter != nil { return "Add or retag a recipe to use it in this meal slot." }
        return "Try clearing your search."
    }

    private func choose(_ meal: HomeyMeal) async {
        guard selectingID == nil else { return }
        selectingID = meal.id
        let succeeded = await select(meal)
        selectingID = nil
        if succeeded { dismiss() }
        else { errorMessage = "Homey couldn't add this recipe to your meal plan. Please try again." }
    }
}

private struct RecipePickerRow: View {
    let meal: HomeyMeal
    let loading: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                HomeRecipeThumbnail(path: meal.primaryPhotoPath).frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(meal.name).font(.headline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if loading { ProgressView().tint(HomeyColors.recipeGreenAccent) }
                else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText) }
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: HomeyColors.text.opacity(0.035), radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(meal.name).accessibilityHint("Selects this recipe")
    }
}

struct RecipePlanSheet:View{let meal:HomeyMeal,home:HomeSummary;@ObservedObject var model:MealsViewModel;@Environment(\.dismiss)var dismiss;@State var day=Date();@State var type=MealType.dinner;var body:some View{NavigationStack{Form{DatePicker("Day",selection:$day,displayedComponents:.date);Picker("Meal",selection:$type){ForEach([MealType.breakfast,.lunch,.dinner]){Text($0.title).tag($0)}}}.navigationTitle("Add to Meal Plan").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Add"){Task{await model.schedule(meal,type:type,day:day,home:home);dismiss()}}}}}}}
struct AutoPlanSheet:View{let home:HomeSummary;@ObservedObject var model:MealsViewModel;@Environment(\.dismiss)var dismiss;@State var types:Set<MealType>=[];@State var favoritesOnly=false;var body:some View{NavigationStack{Form{Section("Fill empty slots"){ForEach([MealType.breakfast,.lunch,.dinner]){type in Toggle(type.title,isOn:.init(get:{types.contains(type)},set:{types.set(type,included:$0)}))}};Section("Recipe pool"){Toggle("Favorites only",isOn:$favoritesOnly);Text("Past days and existing planned meals are preserved.").font(.caption).foregroundStyle(.secondary)}}.navigationTitle("Auto Plan").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Plan"){Task{await model.autoPlan(home:home,types:types,favoritesOnly:favoritesOnly);dismiss()}}.disabled(types.isEmpty)}}}}}

private struct RecipeScanComingSoonView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                ContentUnavailableView("Coming Soon", systemImage: "doc.viewfinder")
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension StepDraft { init(text: String) { self.init(); self.text = text } }
private extension Set { mutating func set(_ member: Element, included: Bool) { if included { insert(member) } else { remove(member) } } }
