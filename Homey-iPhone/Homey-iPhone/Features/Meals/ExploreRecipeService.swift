import Combine
import Foundation
import Supabase

/// Lightweight card data; full ingredients and directions are fetched only on opening a card.
struct ExploreRecipe: Identifiable, Decodable, Hashable {
    let id: UUID
    let title: String
    let description, imageURL: String?
    let prepTimeMinutes, cookTimeMinutes, totalTimeMinutes: Int?
    let servings, cuisine: String?
    let mealTypes: [MealType]
    let keywords: [String]
    let createdBy: UUID?

    var displayedTotalMinutes: Int? {
        if let totalTimeMinutes, totalTimeMinutes > 0 { return totalTimeMinutes }
        let total = (prepTimeMinutes ?? 0) + (cookTimeMinutes ?? 0)
        return total > 0 ? total : nil
    }
    var displayedServings: Double? { servings.flatMap(Double.init) }

    enum CodingKeys: String, CodingKey {
        case id, title
        case description, servings, cuisine, keywords
        case imageURL = "image_url", prepTimeMinutes = "prep_time_minutes", cookTimeMinutes = "cook_time_minutes"
        case totalTimeMinutes = "total_time_minutes", mealTypes = "meal_types", createdBy = "created_by"
    }
}

struct ExploreQuery: Hashable {
    var search = ""
    var filter: RecipeLibraryFilter = .all
}

struct ExploreRecipePage {
    let recipes: [ExploreRecipe]
    let nextOffset: Int?
}

@MainActor
protocol ExploreRecipeProviding {
    func page(query: ExploreQuery, offset: Int) async throws -> ExploreRecipePage
}

/// Keeps ordering and backend queries out of the discovery UI for future feed sources.
@MainActor
final class ExploreRecipeService: ExploreRecipeProviding {
    private let client = SupabaseManager.shared.client
    private let pageSize = 30

    func page(query: ExploreQuery, offset: Int) async throws -> ExploreRecipePage {
        var request = client.from("global_recipes")
            .select("id,title,description,image_url,prep_time_minutes,cook_time_minutes,total_time_minutes,servings,cuisine,meal_types,keywords,created_by")
            .eq("status", value: "active")
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            // Search text is literal, not an SQL wildcard expression.
            let escaped = search.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
                .replacingOccurrences(of: "*", with: "\\*")
            request = request.ilike("title", pattern: "%\(escaped)%")
        }
        if let mealType = query.filter.mealType {
            request = request.contains("meal_types", value: [mealType.rawValue])
        }
        let recipes: [ExploreRecipe] = try await request
            .order("save_count", ascending: false)
            .order("id", ascending: true)
            .range(from: offset, to: offset + pageSize - 1)
            .execute().value
        return ExploreRecipePage(recipes: recipes, nextOffset: recipes.count == pageSize ? offset + recipes.count : nil)
    }

    func recipe(id: UUID) async throws -> CommunityRecipe {
        try await client.from("global_recipes").select().eq("id", value: id.uuidString)
            .single().execute().value
    }
}

@MainActor
final class ExploreRecipesViewModel: ObservableObject {
    @Published private(set) var recipes: [ExploreRecipe] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var nextOffset: Int? = 0
    private var query = ExploreQuery()
    private var hasStarted = false
    private var generation = UUID()
    private let service: any ExploreRecipeProviding

    init(service: (any ExploreRecipeProviding)? = nil) {
        self.service = service ?? ExploreRecipeService()
    }

    func update(query: ExploreQuery) async {
        guard !hasStarted || self.query != query || (recipes.isEmpty && !isLoading && errorMessage == nil) else { return }
        await reset(query: query, debounce: !query.search.isEmpty)
    }

    func reset(query: ExploreQuery, debounce: Bool = false) async {
        let token = UUID()
        generation = token
        hasStarted = true
        self.query = query
        recipes = []
        nextOffset = 0
        errorMessage = nil
        isLoading = false
        if debounce {
            isLoading = true
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch {
                if generation == token { isLoading = false }
                return
            }
            guard generation == token else { return }
            isLoading = false
        }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, let offset = nextOffset else { return }
        let token = generation
        isLoading = true
        errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            let page = try await service.page(query: query, offset: offset)
            try Task.checkCancellation()
            guard generation == token else { return }
            var seen = Set(recipes.map(\.id))
            recipes.append(contentsOf: page.recipes.filter { seen.insert($0.id).inserted })
            nextOffset = page.nextOffset
        } catch {
            guard generation == token else { return }
            if Task.isCancelled || error is CancellationError { return }
            errorMessage = "Couldn’t load recipes. Please try again."
            #if DEBUG
            print("Explore page failed (offset \(offset)): \(String(reflecting: error))")
            #endif
        }
    }

    func loadMoreIfNeeded(near recipe: ExploreRecipe) async {
        guard errorMessage == nil,
              let index = recipes.firstIndex(where: { $0.id == recipe.id }),
              index >= recipes.count - 9 else { return }
        await loadNextPage()
    }

    func remove(id: UUID) {
        recipes.removeAll { $0.id == id }
    }
}
