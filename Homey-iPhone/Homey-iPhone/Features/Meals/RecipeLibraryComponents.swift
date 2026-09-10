import SwiftUI

enum RecipeLibraryFilter: Hashable, Identifiable, CaseIterable {
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

struct RecipeLibrarySearchBar: View {
    @Binding var search: String
    @Binding var filter: RecipeLibraryFilter
    let placeholder: String
    let filters: [RecipeLibraryFilter]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(HomeyColors.secondaryText)
                TextField(placeholder, text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear search").foregroundStyle(HomeyColors.secondaryText)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(HomeyColors.field.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            Menu {
                Picker("Filter recipes", selection: $filter) {
                    ForEach(filters) { Text($0.title).tag($0) }
                }
            } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(HomeyColors.text)
                    .frame(width: 52, height: 52).background(HomeyColors.field.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
            }
            .accessibilityLabel("Filter recipes").accessibilityValue(filter.title)
        }
    }
}

struct RecipeLibraryFilterChips: View {
    @Binding var selection: RecipeLibraryFilter
    let filters: [RecipeLibraryFilter]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { value in
                    Button { selection = value } label: {
                        Text(value.title).font(.subheadline.weight(selection == value ? .semibold : .regular))
                            .padding(.horizontal, 16).frame(minHeight: 40)
                            .foregroundStyle(selection == value ? .white : HomeyColors.text)
                            .background(selection == value ? HomeyColors.recipeGreenAccent : HomeyColors.field.opacity(0.8), in: Capsule())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
        }
    }
}

struct RecipeCardContent {
    let title: String
    let imageReference: String?
    let description: String?
    let mealTypes: [MealType]
    let totalMinutes: Int?
    let servings: Double?
    let badges: [String]
}

struct RecipeCard<MenuContent: View>: View {
    let content: RecipeCardContent
    let width: CGFloat
    let favorite: Bool?
    let favoritePending: Bool
    let open: () -> Void
    let favoriteAction: (() -> Void)?
    @ViewBuilder let menu: () -> MenuContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var imageSize: CGFloat { min(130, max(100, width * 0.30)) }
    private var uniqueBadges: [String] {
        var seen = Set<String>()
        return content.badges.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: open) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    HomeRecipeThumbnail(path: content.imageReference).frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(content.title).font(.headline.weight(.bold)).lineLimit(2).foregroundStyle(HomeyColors.text)
                        if let description = content.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                            Text(description).font(.subheadline).lineLimit(2).foregroundStyle(HomeyColors.secondaryText)
                        }
                        RecipeBadgeFlow(spacing: 7) {
                            if let total = content.totalMinutes, total > 0 { Label("\(total) min", systemImage: "clock") }
                            ForEach(content.mealTypes) { Label($0.title, systemImage: "fork.knife") }
                            if let servings = content.servings, servings > 0 { Label("\(servings.formatted()) servings", systemImage: "person.2") }
                        }.font(.caption).foregroundStyle(HomeyColors.secondaryText)
                        if !uniqueBadges.isEmpty {
                            RecipeBadgeFlow(spacing: 5) {
                                ForEach(Array(uniqueBadges.prefix(3).enumerated()), id: \.offset) { index, tag in
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
                if let favorite, let favoriteAction {
                    Button(action: favoriteAction) {
                        Image(systemName: favorite ? "heart.fill" : "heart").font(.system(size: 21))
                            .foregroundStyle(favorite ? HomeyColors.danger : HomeyColors.secondaryText).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).disabled(favoritePending)
                        .accessibilityLabel(favorite ? "Remove \(content.title) from favorites" : "Favorite \(content.title)")
                }
                Menu(content: menu) {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(HomeyColors.secondaryText).frame(width: 44, height: 44)
                }.accessibilityLabel("Actions for \(content.title)")
            }
        }
        .padding(10)
        .background(HomeyColors.recipeCardBackground.opacity(0.95), in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: HomeyColors.text.opacity(0.035), radius: 10, y: 4)
    }

    private func badgeColor(_ index: Int) -> Color {
        [HomeyColors.recipeGreenAccent, HomeyColors.primary, HomeyColors.recipeOrangeAccent][index % 3]
    }
}

struct RecipeLibraryLoadingState: View {
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) { ProgressView(); Text(message).font(.subheadline) }.padding(12)
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
}

struct RecipeLibraryNoMatches: View {
    let title: String
    let clear: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(HomeyColors.recipeGreenAccent)
            Text(title).font(HomeyTypography.title)
            Text("Try another search or filter.").foregroundStyle(HomeyColors.secondaryText)
            Button("Clear filters", action: clear).buttonStyle(.bordered)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
}
