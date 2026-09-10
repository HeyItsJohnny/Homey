import PhotosUI
import SwiftUI
import Combine

@MainActor final class MealsViewModel: ObservableObject {
    @Published var homeRecipes: [HomeyMeal] = []
    @Published private(set) var recipesRevision = 0
    @Published var favoriteIDs: Set<UUID> = []
    @Published var planned: [PlannedMeal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let service = MealsService()
    func load(home: HomeSummary) async { isLoading=true; defer{isLoading=false}; do { async let h=service.homeRecipes(homeId:home.id); async let f=service.favoriteIDs(); let week=Self.week(containing:Date(),home:home); async let p=service.plannedMeals(home:home,week:week); (homeRecipes,favoriteIDs,planned)=try await(h,f,p); recipesRevision += 1 } catch { errorMessage=error.localizedDescription } }
    func refreshRecipesAfterSave(home: HomeSummary) async throws {
        recipesRevision += 1
        homeRecipes = try await service.homeRecipes(homeId: home.id)
    }
    func refreshPlan(home: HomeSummary) async { do { planned = try await service.plannedMeals(home: home, week: Self.week(containing: Date(), home: home)) } catch { errorMessage=error.localizedDescription } }
    func toggleFavorite(_ meal: HomeyMeal) async { let next = !favoriteIDs.contains(meal.id); do { try await service.setFavorite(mealId:meal.id,isFavorite:next); if next { favoriteIDs.insert(meal.id) } else { favoriteIDs.remove(meal.id) } } catch { errorMessage=error.localizedDescription } }
    func schedule(_ meal: HomeyMeal,type:MealType,day:Date,home:HomeSummary) async { do { try await service.schedule(meal,type:type,day:day,home:home); await refreshPlan(home:home) } catch { errorMessage=error.localizedDescription } }
    func remove(_ item: PlannedMeal,home:HomeSummary) async { do { try await service.removePlanned(item.eventId); await refreshPlan(home:home) } catch { errorMessage=error.localizedDescription } }
    func autoPlan(home: HomeSummary, types: Set<MealType>, favoritesOnly: Bool) async { let calendar=Self.calendar(home); let week=Self.week(containing:Date(),home:home); let candidates=(favoritesOnly ? homeRecipes.filter{favoriteIDs.contains($0.id)}:homeRecipes); guard !candidates.isEmpty else { errorMessage="Add recipes to this Home before auto-planning."; return }; var index=0; for offset in 0..<7 { guard let day=calendar.date(byAdding:.day,value:offset,to:week.start), day >= calendar.startOfDay(for:Date()) else { continue }; for type in types { let occupied=planned.contains{calendar.isDate($0.startsAt,inSameDayAs:day) && $0.mealType == type}; guard !occupied else {continue}; let preferred=candidates.filter{$0.mealTypes.isEmpty || $0.mealTypes.contains(type)}; let pool=preferred.isEmpty ? candidates:preferred; do { try await service.schedule(pool[index % pool.count],type:type,day:day,home:home); index += 1 } catch { errorMessage=error.localizedDescription; await refreshPlan(home:home); return } }; await refreshPlan(home:home) } }
    static func calendar(_ home:HomeSummary)->Calendar { var c=Calendar(identifier:.gregorian); c.timeZone=home.timezone.flatMap(TimeZone.init(identifier:)) ?? .current; c.firstWeekday=home.weekStartsOn == 2 ? 2:1; return c }
    static func week(containing date:Date,home:HomeSummary)->DateInterval { let c=calendar(home); return c.dateInterval(of:.weekOfYear,for:date) ?? .init(start:c.startOfDay(for:date),duration:604800) }
}

struct MealsRootView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = MealsViewModel()
    @State private var section = 0
    @State private var showAdd = false
    @State private var creationMethod: RecipeCreationMethod?

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
                        if section == 1 {
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
                            MealPlanView(home: home, model: model)
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
                Button("New Recipe") { creationMethod = .new }
                Button("From Website") { creationMethod = .website }
                Button("Scan") { creationMethod = .scan }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $creationMethod) { method in
                if let home = session.activeHome {
                    RecipeCreationView(home: home, model: model, method: method)
                }
            }
            .task(id: session.activeHome?.id) {
                if let home = session.activeHome { await model.load(home: home) }
            }
            .refreshable {
                if let home = session.activeHome { await model.load(home: home) }
            }
            .alert("Meals", isPresented: .init(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.errorMessage ?? "") }
        }
    }
}

struct MealPlanView: View {
    let home:HomeSummary; @ObservedObject var model:MealsViewModel
    @State private var pickerSlot: MealSlot?
    @State private var auto = false
    private var calendar:Calendar{MealsViewModel.calendar(home)}; private var week:DateInterval{MealsViewModel.week(containing:Date(),home:home)}
    var body:some View { ScrollView { LazyVStack(spacing:14) { HStack { VStack(alignment:.leading){Text(week.start.formatted(.dateTime.month().day())+" – "+week.end.addingTimeInterval(-1).formatted(.dateTime.month().day())).font(.headline);Text(home.timezone ?? TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)};Spacer();Button("Auto Plan"){auto = true}.buttonStyle(.borderedProminent) }.padding(.horizontal); ForEach(0..<7,id:\.self){offset in if let day=calendar.date(byAdding:.day,value:offset,to:week.start){VStack(alignment:.leading,spacing:10){Text(day.formatted(.dateTime.weekday(.wide).month().day())).font(.headline);ForEach([MealType.breakfast,.lunch,.dinner,.snack]){type in let item=model.planned.first{calendar.isDate($0.startsAt,inSameDayAs:day)&&$0.mealType==type}; HStack { Label(type.title,systemImage:type.symbol).frame(width:115,alignment:.leading); if let item { NavigationLink(item.meal.name){RecipeDetailView(meal:item.meal,home:home,model:model)};Spacer();Menu{Button("Change"){pickerSlot = .init(day:day,type:type)};Menu("Move"){ForEach(0..<7,id:\.self){n in Button(calendar.date(byAdding:.day,value:n,to:week.start)!.formatted(.dateTime.weekday())){Task{await model.remove(item,home:home);await model.schedule(item.meal,type:type,day:calendar.date(byAdding:.day,value:n,to:week.start)!,home:home)}}}};Button("Remove",role:.destructive){Task{await model.remove(item,home:home)}}}label:{Image(systemName:"ellipsis.circle")}} else {Button("Add recipe"){pickerSlot = .init(day:day,type:type)}.foregroundStyle(HomeyColors.primary);Spacer()} }.font(.subheadline)} }.homeyCard().padding(.horizontal)}} }.padding(.vertical) }.sheet(item:$pickerSlot){slot in RecipePickerView(recipes:model.homeRecipes,favorites:model.favoriteIDs){meal in Task{await model.schedule(meal,type:slot.type,day:slot.day,home:home)};pickerSlot = nil} }.sheet(isPresented:$auto){AutoPlanSheet(home:home,model:model)} }
}
private struct MealSlot:Identifiable{let day:Date,type:MealType;var id:String{"\(day.timeIntervalSince1970)-\(type.rawValue)"}}

private struct RecipeRow:View{let title:String,subtitle:String?,types:[String],favorite:Bool,action:()->Void;var body:some View{HStack{VStack(alignment:.leading){Text(title).font(.headline);Text(([subtitle].compactMap{$0}+types).joined(separator:" • ")).font(.caption).foregroundStyle(.secondary)};Spacer();Button(action:action){Image(systemName:favorite ? "heart.fill":"heart").foregroundStyle(favorite ? .pink:.secondary)}.buttonStyle(.plain)}}}

struct RecipePickerView:View{let recipes:[HomeyMeal],favorites:Set<UUID>,select:(HomeyMeal)->Void;@Environment(\.dismiss)var dismiss;@State var search="";@State var favoritesOnly=false;var body:some View{NavigationStack{List(recipes.filter{(!favoritesOnly||favorites.contains($0.id))&&(search.isEmpty||$0.name.localizedCaseInsensitiveContains(search))}){meal in Button{select(meal)}label:{RecipeRow(title:meal.name,subtitle:meal.cuisine,types:meal.mealTypes.map(\.title),favorite:favorites.contains(meal.id)){}}}.searchable(text:$search).navigationTitle("Choose Recipe").toolbar{ToolbarItem(placement:.topBarLeading){Button("Cancel"){dismiss()}};ToolbarItem(placement:.topBarTrailing){Toggle("Favorites",isOn:$favoritesOnly).labelsHidden()}}}}}

struct CommunityDetailView:View{let recipe:CommunityRecipe,home:HomeSummary;@ObservedObject var model:MealsViewModel;@EnvironmentObject var session:AppSession;@State var message:String?;let service=MealsService();var body:some View{List{Section{Text(recipe.title).font(.title2.bold());if let d=recipe.description{Text(d)}};Section("Ingredients"){ForEach(Array(recipe.ingredients.enumerated()),id:\.offset){_,i in Text([i.quantity,i.ingredientName].compactMap{$0}.joined(separator:" "))}};Section("Directions"){ForEach(Array(recipe.steps.enumerated()),id:\.offset){n,s in Text("\(n+1). \(s.stepText)")}};Section{Button("Add to My Home"){Task{do{_ = try await service.addToHome(recipe,homeId:home.id);await model.load(home:home);message="Added to \(home.name)."}catch{message=error.localizedDescription}}};if recipe.createdBy == session.currentUser?.id{Button("Delete Community Recipe",role:.destructive){Task{try? await service.deleteCommunityRecipe(recipe.id);await model.load(home:home)}}}}}.navigationTitle("Community Recipe").alert("Recipe",isPresented:.init(get:{message != nil},set:{if !$0{message=nil}})){Button("OK"){}}message:{Text(message ?? "")}}
}

struct RecipePlanSheet:View{let meal:HomeyMeal,home:HomeSummary;@ObservedObject var model:MealsViewModel;@Environment(\.dismiss)var dismiss;@State var day=Date();@State var type=MealType.dinner;var body:some View{NavigationStack{Form{DatePicker("Day",selection:$day,displayedComponents:.date);Picker("Meal",selection:$type){ForEach([MealType.breakfast,.lunch,.dinner,.snack]){Text($0.title).tag($0)}}}.navigationTitle("Add to Meal Plan").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Add"){Task{await model.schedule(meal,type:type,day:day,home:home);dismiss()}}}}}}}
struct AutoPlanSheet:View{let home:HomeSummary;@ObservedObject var model:MealsViewModel;@Environment(\.dismiss)var dismiss;@State var types:Set<MealType>=[.dinner];@State var favoritesOnly=false;var body:some View{NavigationStack{Form{Section("Fill empty slots"){ForEach([MealType.breakfast,.lunch,.dinner,.snack]){type in Toggle(type.title,isOn:.init(get:{types.contains(type)},set:{types.set(type,included:$0)}))}};Section("Recipe pool"){Toggle("Favorites only",isOn:$favoritesOnly);Text("Past days and existing planned meals are preserved.").font(.caption).foregroundStyle(.secondary)}}.navigationTitle("Auto Plan").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Plan"){Task{await model.autoPlan(home:home,types:types,favoritesOnly:favoritesOnly);dismiss()}}.disabled(types.isEmpty)}}}}}

enum RecipeCreationMethod: String, Identifiable {
    case new, website, scan
    var id: String { rawValue }
}

struct RecipeCreationView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    let method: RecipeCreationMethod
    @State private var importedDraft: RecipeDraft?

    var body: some View {
        if let importedDraft {
            RecipeEditorView(home: home, model: model, initialDraft: importedDraft, showsImportMetadata: true)
        } else {
            switch method {
            case .new:
                RecipeEditorView(home: home, model: model)
            case .website:
                RecipeImportView(home: home) { importedDraft = $0 }
            case .scan:
                RecipeScanComingSoonView()
            }
        }
    }
}

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

private extension RecipeDraft {
    mutating func apply(_ response: RecipeImportResponse) {
        imported = response
        let recipe = response.recipe
        name = recipe.title
        description = recipe.description ?? ""
        cuisine = recipe.cuisine ?? ""
        sourceName = recipe.source.name ?? recipe.source.domain
        sourceURL = recipe.source.originalUrl
        prepMinutes = recipe.prepTimeMinutes
        cookMinutes = recipe.cookTimeMinutes
        servings = recipe.servings.flatMap(Double.init)
        mealTypes = Set(recipe.mealTypes.compactMap(MealType.init(rawValue:)))
        tagsText = recipe.keywords.joined(separator: ", ")
        ingredients = recipe.ingredients.map { ingredient in
            let quantity = ingredient.quantity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Match iPad import normalization: preserve descriptive amounts without sending text as numeric JSON.
            let numeric = quantity.isEmpty || (try? RecipeQuantity.decimal(quantity)) != nil
            return IngredientDraft(name: numeric ? ingredient.ingredientName : "\(quantity) \(ingredient.ingredientName)", quantity: numeric ? quantity : "", unit: "", section: ingredient.sectionName ?? "Ingredients", optional: ingredient.isOptional)
        }
        steps = recipe.steps.map { StepDraft(text: $0.stepText) }
    }
}
private extension StepDraft { init(text: String) { self.init(); self.text = text } }
private extension Set { mutating func set(_ member: Element, included: Bool) { if included { insert(member) } else { remove(member) } } }

struct RecipeImportView: View {
    let home: HomeSummary
    let onPreview: (RecipeDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var mealTypes: Set<MealType> = []
    @State private var tags = ""
    @State private var loading = false
    @State private var error: String?
    private let service = MealsService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe URL") {
                    TextField("https://…", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Meal types") {
                    ForEach(MealType.allCases) { type in
                        Toggle(type.title, isOn: .init(get: { mealTypes.contains(type) }, set: { mealTypes.set(type, included: $0) }))
                    }
                }
                Section("Tags") {
                    TextField("Tags, comma separated", text: $tags)
                }
                Text("Review the imported recipe before saving. Meal types and tags from the website will also be included.")
                    .font(.caption).foregroundStyle(.secondary)
                if loading { ProgressView("Importing recipe…") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Recipe URL")
            .disabled(loading)
            .interactiveDismissDisabled(loading)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") { Task { await preview() } }
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                }
            }
        }
    }

    private func preview() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let response = try await service.importURL(url.trimmingCharacters(in: .whitespacesAndNewlines), homeId: home.id)
            var draft = RecipeDraft()
            draft.apply(response)
            draft.mealTypes.formUnion(mealTypes)
            let combinedTags = (draft.tagsText + "," + tags).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var seen: Set<String> = []
            draft.tagsText = combinedTags.filter { seen.insert($0.lowercased()).inserted }.joined(separator: ", ")
            onPreview(draft)
        } catch { self.error = error.localizedDescription }
    }
}
