import SwiftUI

struct RecipeLibraryView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    let onAddRecipe: () -> Void
    let onExplore: () -> Void
    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var viewedMeal: HomeyMeal?
    @State private var plannedMeal: HomeyMeal?
    @State private var recipeToRemove: HomeyMeal?
    @State private var removingIDs: Set<UUID> = []
    @State private var removalError: String?
    private var canRemove: Bool { home.role == .owner || home.role == .admin }
    @State private var pendingFavorites: [UUID: Bool] = [:]

    private var filteredRecipes: [HomeyMeal] {
        model.homeRecipes.filter { meal in
            (search.isEmpty || meal.name.localizedCaseInsensitiveContains(search)) &&
            (filter == .all || filter == .favorites && isFavorite(meal) || filter.mealType.map { meal.mealTypes.contains($0) } == true)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 14) {
                    searchBar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LibraryFilter.allCases) { value in
                                Button { filter = value } label: {
                                    Text(value.title).font(.subheadline.weight(filter == value ? .semibold : .regular))
                                        .padding(.horizontal, 16).frame(minHeight: 40)
                                        .foregroundStyle(filter == value ? .white : HomeyColors.text)
                                        .background(filter == value ? HomeyColors.recipeGreenAccent : HomeyColors.field.opacity(0.8), in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(filter == value ? .isSelected : [])
                            }
                        }
                    }
                    if model.isLoading && model.homeRecipes.isEmpty {
                        loadingState
                    } else if model.homeRecipes.isEmpty {
                        emptyState
                    } else if filteredRecipes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(HomeyColors.recipeGreenAccent)
                            Text("No matching recipes").font(HomeyTypography.title)
                            Text("Try another search or filter.").foregroundStyle(HomeyColors.secondaryText)
                            Button("Clear filters") { search = ""; filter = .all }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity).padding(.vertical, 36)
                    } else {
                        ForEach(filteredRecipes) { meal in
                            HomeRecipeCard(meal: meal, width: geometry.size.width - 32, favorite: isFavorite(meal), favoritePending: pendingFavorites[meal.id] != nil,
                                open: { viewedMeal = meal }, favoriteAction: { toggleFavorite(meal) }, plan: { plannedMeal = meal }, canRemove: canRemove, remove: { recipeToRemove = meal })
                                .disabled(removingIDs.contains(meal.id))
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
                .refreshable { await model.load(home: home) }
        }
        .navigationDestination(item: $viewedMeal) { RecipeDetailView(meal: $0, home: home, model: model) }
        .sheet(item: $plannedMeal) { RecipePlanSheet(meal: $0, home: home, model: model) }
        .confirmationDialog("Remove Recipe?", isPresented: .init(get: { recipeToRemove != nil }, set: { if !$0 { recipeToRemove = nil } }), titleVisibility: .visible, presenting: recipeToRemove) { meal in
            Button("Remove Recipe", role: .destructive) { Task { await removeRecipe(meal) } }
            Button("Cancel", role: .cancel) { recipeToRemove = nil }
        } message: { meal in
            Text("Are you sure you want to remove “\(meal.name)” from your Home Recipes?")
        }
        .alert("Couldn't Remove Recipe", isPresented: .init(get: { removalError != nil }, set: { if !$0 { removalError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(removalError ?? "") }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(HomeyColors.secondaryText)
                TextField("Search your recipes...", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear search").foregroundStyle(HomeyColors.secondaryText)
                }
            }.padding(.horizontal, 14).frame(minHeight: 52)
                .background(HomeyColors.field.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            Menu {
                Picker("Filter recipes", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(HomeyColors.text)
                    .frame(width: 52, height: 52).background(HomeyColors.field.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            }.accessibilityLabel("Filter recipes").accessibilityValue(filter.title)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 38)).foregroundStyle(HomeyColors.recipeGreenAccent)
                .frame(width: 84, height: 84).background(HomeyColors.recipeGreenAccent.opacity(0.1), in: Circle())
            Text("No recipes yet").font(HomeyTypography.title)
            Text("Add your first recipe or explore community recipes.")
                .multilineTextAlignment(.center).foregroundStyle(HomeyColors.secondaryText)
            Button("Add Recipe", action: onAddRecipe).buttonStyle(.borderedProminent).tint(HomeyColors.recipeGreenAccent)
            Button("Explore Recipes", action: onExplore).tint(HomeyColors.recipeGreenAccent)
        }.padding(28).frame(maxWidth: .infinity)
            .background(HomeyColors.recipeCardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) { ProgressView(); Text("Gathering your recipes…").font(.subheadline) }.padding(12)
            ForEach(0..<3) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 20).fill(HomeyColors.border.opacity(0.2)).frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: 6).fill(HomeyColors.border.opacity(0.25)).frame(height: 16)
                        RoundedRectangle(cornerRadius: 6).fill(HomeyColors.border.opacity(0.15)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 6).fill(HomeyColors.border.opacity(0.15)).frame(width: 90, height: 12)
                    }
                }.padding(12).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
            }
        }
    }

    private func removeRecipe(_ meal: HomeyMeal) async {
        guard canRemove, meal.homeId == home.id, !removingIDs.contains(meal.id) else { return }
        recipeToRemove = nil
        removingIDs.insert(meal.id)
        defer { removingIDs.remove(meal.id) }
        do {
            try await MealsService().removeHomeRecipe(meal, home: home)
            model.homeRecipes.removeAll { $0.id == meal.id }
            // Keep favorite records and planned meals intact; every library filter
            // derives from homeRecipes, so the archived card disappears everywhere.
        } catch {
            RecipeSaveDiagnostics.failure(error, stage: "removeHomeRecipe")
            removalError = "Homey couldn't remove this recipe. Please try again."
        }
    }

    private func isFavorite(_ meal: HomeyMeal) -> Bool { pendingFavorites[meal.id] ?? model.favoriteIDs.contains(meal.id) }
    private func toggleFavorite(_ meal: HomeyMeal) {
        guard pendingFavorites[meal.id] == nil else { return }
        pendingFavorites[meal.id] = !model.favoriteIDs.contains(meal.id)
        Task {
            await model.toggleFavorite(meal)
            pendingFavorites[meal.id] = nil // The model retains its original value if the request fails.
        }
    }
}

private enum LibraryFilter: Hashable, Identifiable, CaseIterable {
    case all, favorites, breakfast, lunch, dinner, dessert
    var id: Self { self }
    var mealType: MealType? {
        switch self {
        case .all, .favorites: nil
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .dessert: .dessert
        }
    }
    var title: String {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        case .dessert: "Desserts"
        default: mealType?.title ?? ""
        }
    }
}

private struct HomeRecipeCard: View {
    let meal: HomeyMeal
    let width: CGFloat
    let favorite: Bool
    let favoritePending: Bool
    let open: () -> Void
    let favoriteAction: () -> Void
    let plan: () -> Void
    let canRemove: Bool
    let remove: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var imageSize: CGFloat { min(130, max(100, width * 0.30)) }
    private var badges: [String] {
        var seen = Set<String>()
        return (meal.tags + [meal.cuisine].compactMap { $0 }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: open) {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    HomeRecipeThumbnail(path: meal.primaryPhotoPath).frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(meal.name).font(.headline.weight(.bold)).lineLimit(2).foregroundStyle(HomeyColors.text)
                        if let description = meal.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                            Text(description).font(.subheadline).lineLimit(2).foregroundStyle(HomeyColors.secondaryText)
                        }
                        RecipeBadgeFlow(spacing: 7) {
                            let total = (meal.prepTimeMinutes ?? 0) + (meal.cookTimeMinutes ?? 0)
                            if total > 0 { Label("\(total) min", systemImage: "clock") }
                            ForEach(meal.mealTypes) { Label($0.title, systemImage: "fork.knife") }
                            if let servings = meal.servings, servings > 0 { Label("\(servings.formatted()) servings", systemImage: "person.2") }
                        }.font(.caption).foregroundStyle(HomeyColors.secondaryText)
                        if !badges.isEmpty {
                            RecipeBadgeFlow(spacing: 5) {
                                ForEach(Array(badges.prefix(3).enumerated()), id: \.offset) { index, tag in
                                    Text(tag).font(.caption2.weight(.medium)).lineLimit(1)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .foregroundStyle(badgeColor(index))
                                        .background(badgeColor(index).opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityHint("Opens recipe details")
            VStack(spacing: 0) {
                Button(action: favoriteAction) {
                    Image(systemName: favorite ? "heart.fill" : "heart").font(.system(size: 21))
                        .foregroundStyle(favorite ? HomeyColors.danger : HomeyColors.secondaryText).frame(width: 44, height: 44)
                }.buttonStyle(.plain).disabled(favoritePending)
                    .accessibilityLabel(favorite ? "Remove \(meal.name) from favorites" : "Favorite \(meal.name)")
                Menu {
                    Button("View Recipe", systemImage: "book", action: open)
                    Button("Add to Meal Plan", systemImage: "calendar.badge.plus", action: plan)
                    if canRemove {
                        Divider()
                        Button("Remove Recipe", systemImage: "trash", role: .destructive, action: remove)
                            .accessibilityLabel("Remove Recipe")
                    }
                } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(HomeyColors.secondaryText).frame(width: 44, height: 44)
                }.accessibilityLabel("Actions for \(meal.name)")
            }
        }.padding(10)
            .background(HomeyColors.recipeCardBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: HomeyColors.text.opacity(0.035), radius: 10, y: 4)
    }

    private func badgeColor(_ index: Int) -> Color {
        [HomeyColors.recipeGreenAccent, HomeyColors.primary, HomeyColors.recipeOrangeAccent][index % 3]
    }
}

struct HomeRecipeThumbnail: View {
    let path: String?
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HomeyColors.recipeGreenAccent.opacity(0.08)
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Image(systemName: "fork.knife").font(.title).foregroundStyle(HomeyColors.recipeGreenAccent.opacity(0.5))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
            .task(id: path) {
                image = nil
                guard let url = await MealsService().signedImageURL(path: path) else { return }
                let loaded = await ExploreImageCache.shared.image(url: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}

/// Wrap whole metadata labels/chips, never individual words within a metadata item.
struct RecipeBadgeFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 300, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
