import SwiftUI

struct ExploreRecipesView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @StateObject private var feed = ExploreRecipesViewModel()
    @State private var query = ExploreQuery()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search Recipes", text: $query.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.search.isEmpty {
                        Button { query.search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                Menu {
                    Picker("Meal type", selection: $query.filter) {
                        ForEach(RecipeFilter.allCases.filter { $0 != .favorites }) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                } label: {
                    Image(systemName: query.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .tint(HomeyColors.primary)
                .accessibilityLabel("Filter recipes")
                .accessibilityValue(query.filter.rawValue)
            }
            .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(feed.recipes) { recipe in
                        NavigationLink(value: recipe) {
                            ExploreRecipeImage(path: recipe.imageURL)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(recipe.title)
                        .accessibilityHint("Opens recipe details")
                        .onAppear {
                            Task { await feed.loadMoreIfNeeded(near: recipe) }
                        }
                    }
                }
                if feed.isLoading {
                    ProgressView().tint(HomeyColors.primary)
                        .frame(maxWidth: .infinity).padding()
                } else if let error = feed.errorMessage {
                    VStack(spacing: 8) {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Retry") { Task { await feed.loadNextPage() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else if feed.recipes.isEmpty {
                    ContentUnavailableView {
                        Label(query.search.isEmpty && query.filter == .all ? "No recipes yet" : "No recipes found", systemImage: "fork.knife")
                    } description: {
                        Text(query.search.isEmpty && query.filter == .all ? "Community recipes will appear here." : "Try another search or meal type.")
                    } actions: {
                        if !query.search.isEmpty || query.filter != .all {
                            Button("Reset search and filters") { query = ExploreQuery() }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await feed.reset(query: query) }
            .id(query)
        }
        .task(id: query) { await feed.update(query: query) }
        .navigationDestination(for: ExploreRecipe.self) { recipe in
            ExploreRecipeDestination(id: recipe.id, home: home, model: model)
                .toolbar(.visible, for: .navigationBar)
        }
        .onChange(of: model.recipesRevision) {
            Task { await feed.reset(query: query) }
        }
    }
}

/// Loads full data, then presents the existing detail and its existing actions unchanged.
private struct ExploreRecipeDestination: View {
    let id: UUID
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @State private var recipe: CommunityRecipe?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let recipe {
                CommunityDetailView(recipe: recipe, home: home, model: model)
            } else if failed {
                ContentUnavailableView {
                    Label("Recipe unavailable", systemImage: "fork.knife")
                } description: {
                    Text("It may have been removed, or the connection was interrupted.")
                } actions: {
                    Button("Retry") { attempt += 1 }
                }
            } else {
                ProgressView().tint(HomeyColors.primary)
            }
        }
        .task(id: attempt) {
            failed = false
            do { recipe = try await ExploreRecipeService().recipe(id: id) }
            catch {
                guard !Task.isCancelled else { return }
                failed = true
                #if DEBUG
                print("Explore detail failed: \(String(reflecting: error))")
                #endif
            }
        }
    }
}
