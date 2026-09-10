// Compiled alongside the production view model by run-explore-checks.py.
import Foundation

@MainActor
final class ControlledExploreService: ExploreRecipeProviding {
    struct Call {
        let query: ExploreQuery
        let offset: Int
        let continuation: CheckedContinuation<ExploreRecipePage, Error>
    }
    var calls: [Call] = []
    func page(query: ExploreQuery, offset: Int) async throws -> ExploreRecipePage {
        try await withCheckedThrowingContinuation { calls.append(Call(query: query, offset: offset, continuation: $0)) }
    }
    func succeed(_ index: Int, _ recipes: [ExploreRecipe], next: Int? = nil) {
        calls[index].continuation.resume(returning: ExploreRecipePage(recipes: recipes, nextOffset: next))
    }
}

@main
struct ExplorePaginationChecks {
    @MainActor static func main() async {
        let service = ControlledExploreService()
        let model = ExploreRecipesViewModel(service: service)
        let a = recipe("A")
        let b = recipe("B")
        let c = recipe("C")
        let initial = Task { await model.reset(query: ExploreQuery()) }
        await wait { service.calls.count == 1 }
        await model.loadNextPage()
        assert(service.calls.count == 1, "Concurrent requests must coalesce")
        service.succeed(0, [a, b], next: 30)
        await initial.value
        let more = Task { await model.loadMoreIfNeeded(near: b) }
        await wait { service.calls.count == 2 }
        assert(service.calls[1].offset == 30)
        service.succeed(1, [b, c], next: 60)
        await more.value
        assert(model.recipes.map(\.id) == [a.id, b.id, c.id], "Deduplicate overlapping pages")
        let failing = Task { await model.loadNextPage() }
        await wait { service.calls.count == 3 }
        service.calls[2].continuation.resume(throwing: URLError(.notConnectedToInternet))
        await failing.value
        assert(model.recipes.count == 3 && model.errorMessage != nil)
        let retry = Task { await model.loadNextPage() }
        await wait { service.calls.count == 4 }
        assert(service.calls[3].offset == 60, "Retry the failed offset")
        service.succeed(3, [])
        await retry.value
        await model.loadNextPage()
        assert(service.calls.count == 4, "Stop naturally at end")
        await model.update(query: ExploreQuery())
        assert(service.calls.count == 4, "Returning from detail preserves feed")

        let old = Task { await model.reset(query: ExploreQuery(search: "old")) }
        await wait { service.calls.count == 5 }
        let fresh = Task { await model.reset(query: ExploreQuery(search: "new", filter: .dinner)) }
        await wait { service.calls.count == 6 }
        assert(model.recipes.isEmpty && service.calls[5].offset == 0)
        assert(service.calls[5].query.filter == .dinner)
        service.succeed(5, [c])
        await fresh.value
        service.succeed(4, [a], next: 30)
        await old.value
        assert(model.recipes.map(\.id) == [c.id], "Stale responses cannot overwrite refreshed search")
        assert(!model.isLoading && model.errorMessage == nil)

        let debounce = Task { await model.reset(query: ExploreQuery(search: "cancel"), debounce: true) }
        await Task.yield()
        debounce.cancel()
        await debounce.value
        assert(!model.isLoading)
        assert(service.calls.count == 6)
        let refresh = Task { await model.reset(query: ExploreQuery()) }
        await wait { service.calls.count == 7 }
        service.succeed(6, [a, a, b])
        await refresh.value
        assert(model.recipes.count == 2)
        print("PASS: paging, request coalescing, deduplication, end-of-feed, retry, refresh, stale search protection, cancellation, detail-return preservation")
    }
    static func recipe(_ title: String) -> ExploreRecipe {
        ExploreRecipe(id: UUID(), title: title, description: nil, imageURL: nil,
            prepTimeMinutes: nil, cookTimeMinutes: nil, totalTimeMinutes: nil,
            servings: nil, cuisine: nil, mealTypes: [], keywords: [], createdBy: nil)
    }
    @MainActor static func wait(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError("Timed out waiting for expected request")
    }
}
