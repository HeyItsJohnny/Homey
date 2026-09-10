import SwiftUI

struct RecipeDetailIngredientItem: Identifiable {
    let id: String
    let text: String
    let preparation: String?
    let notes: String?
    let isOptional: Bool
}

struct RecipeDetailDirectionItem: Identifiable {
    let id: String
    let number: Int
    let text: String
    let timerMinutes: Int?
}

struct RecipeDetailPresentation {
    let title: String
    let imageReference: String?
    let description: String?
    let mealTypes: [MealType]
    let totalMinutes: Int?
    let servings: Double?
    let ingredients: [RecipeDetailIngredientItem]
    let directions: [RecipeDetailDirectionItem]
    let sourceName: String?
    let sourceURL: String?
    let notes: String?
    let cuisine: String?
    let difficulty: String?
    let prepMinutes: Int?
    let cookMinutes: Int?
    let tags: [String]
}

struct RecipeDetailHero: View {
    let imageReference: String?
    var body: some View {
        HomeRecipeThumbnail(path: imageReference)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct RecipeDetailSummaryCard: View {
    let presentation: RecipeDetailPresentation
    let favorite: Bool?
    let favoritePending: Bool
    let favoriteAction: (() -> Void)?
    var showsTitleAndFavorite = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsTitleAndFavorite {
                HStack(alignment: .top, spacing: 12) {
                    Text(presentation.title).font(HomeyTypography.title).frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let favorite, let favoriteAction {
                        RecipeFavoriteButton(favorite: favorite, pending: favoritePending, action: favoriteAction)
                    }
                }
            }
            RecipeBadgeFlow(spacing: 8) {
                ForEach(presentation.mealTypes) { type in
                    RecipeDetailMetadataBadge(title: type.title, icon: "fork.knife", color: HomeyColors.recipeOrangeAccent)
                }
                if let total = presentation.totalMinutes, total > 0 {
                    RecipeDetailMetadataBadge(title: "\(total) min", icon: "clock", color: HomeyColors.secondaryText)
                }
                if let servings = presentation.servings, servings > 0 {
                    RecipeDetailMetadataBadge(title: "\(servings.formatted()) servings", icon: "person.2", color: HomeyColors.secondaryText)
                }
            }
            if let description = nonemptyRecipeDetailText(presentation.description) {
                Text(description).foregroundStyle(HomeyColors.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).recipeDetailCard()
    }
}

struct RecipeFavoriteButton: View {
    let favorite: Bool
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: favorite ? "heart.fill" : "heart").font(.title2)
                .foregroundStyle(favorite ? HomeyColors.danger : HomeyColors.secondaryText)
                .frame(width: 44, height: 44).background(HomeyColors.danger.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain).disabled(pending)
        .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
    }
}

struct RecipeDetailIngredientsCard: View {
    let ingredients: [RecipeDetailIngredientItem]
    var body: some View {
        RecipeDetailSection(title: "Ingredients", icon: "cart", color: HomeyColors.recipeGreenAccent) {
            if ingredients.isEmpty {
                Text("No ingredients added yet.").foregroundStyle(HomeyColors.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ingredient.text).frame(maxWidth: .infinity, alignment: .leading)
                            if let preparation = nonemptyRecipeDetailText(ingredient.preparation) { Text(preparation).font(.caption).foregroundStyle(HomeyColors.secondaryText) }
                            if let notes = nonemptyRecipeDetailText(ingredient.notes) { Text(notes).font(.caption).foregroundStyle(HomeyColors.secondaryText) }
                            if ingredient.isOptional { Text("Optional").font(.caption).foregroundStyle(HomeyColors.secondaryText) }
                        }.padding(.vertical, 13)
                        if index < ingredients.count - 1 { Divider().overlay(HomeyColors.border.opacity(0.2)) }
                    }
                }.padding(.horizontal, 14).background(HomeyColors.field, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

struct RecipeDetailDirectionsCard: View {
    let directions: [RecipeDetailDirectionItem]
    var body: some View {
        RecipeDetailSection(title: "Directions", icon: "list.bullet", color: HomeyColors.recipeOrangeAccent) {
            if directions.isEmpty {
                Text("No directions added yet.").foregroundStyle(HomeyColors.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(directions) { step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(step.number)").font(.headline).frame(minWidth: 36, minHeight: 36)
                                .background(HomeyColors.field, in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.text).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                if let timer = step.timerMinutes, timer > 0 {
                                    Label("\(timer) min", systemImage: "timer").font(.caption).foregroundStyle(HomeyColors.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RecipeDetailAdditionalCard: View {
    let presentation: RecipeDetailPresentation
    private var hasContent: Bool {
        [presentation.sourceName, presentation.sourceURL, presentation.notes, presentation.cuisine, presentation.difficulty]
            .contains { nonemptyRecipeDetailText($0) != nil }
            || presentation.prepMinutes != nil || presentation.cookMinutes != nil || !presentation.tags.isEmpty
    }

    var body: some View {
        if hasContent {
            RecipeDetailSection(title: "About this recipe", icon: "book.closed", color: HomeyColors.recipeGreenAccent) {
                if let source = nonemptyRecipeDetailText(presentation.sourceName) { RecipeDetailField(title: "Source", text: source) }
                if let sourceURL = nonemptyRecipeDetailText(presentation.sourceURL) {
                    if let url = URL(string: sourceURL), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link(destination: url) { Label("View original recipe", systemImage: "arrow.up.right.square") }
                    } else { RecipeDetailField(title: "Source URL", text: sourceURL) }
                }
                if let notes = nonemptyRecipeDetailText(presentation.notes) { RecipeDetailField(title: "Notes", text: notes) }
                if let cuisine = nonemptyRecipeDetailText(presentation.cuisine) { RecipeDetailField(title: "Cuisine", text: cuisine) }
                if let difficulty = nonemptyRecipeDetailText(presentation.difficulty) { RecipeDetailField(title: "Difficulty", text: difficulty) }
                if let prep = presentation.prepMinutes { RecipeDetailField(title: "Prep time", text: "\(prep) min") }
                if let cook = presentation.cookMinutes { RecipeDetailField(title: "Cook time", text: "\(cook) min") }
                if !presentation.tags.isEmpty {
                    RecipeBadgeFlow(spacing: 8) {
                        ForEach(Array(presentation.tags.enumerated()), id: \.offset) { _, tag in
                            Text(tag).font(.caption).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(HomeyColors.recipeGreenAccent.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

struct RecipeDetailActionRow: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RecipeDetailIcon(symbol: icon, color: color)
                Text(title).foregroundStyle(HomeyColors.primary).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            }.padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct RecipeDetailMetadataBadge: View {
    let title: String
    let icon: String
    let color: Color
    var body: some View {
        Label(title, systemImage: icon).font(.subheadline).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 9).background(color.opacity(0.08), in: Capsule())
    }
}

struct RecipeDetailField: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RecipeDetailIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(color)
            .frame(width: 44, height: 44).background(color.opacity(0.1), in: Circle()).accessibilityHidden(true)
    }
}

struct RecipeDetailSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RecipeDetailIcon(symbol: icon, color: color)
                Text(title).font(HomeyTypography.headline).accessibilityAddTraits(.isHeader)
            }
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).recipeDetailCard()
    }
}

extension View {
    func recipeDetailCard() -> some View {
        background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: HomeyColors.text.opacity(0.035), radius: 12, y: 4)
    }
}

func nonemptyRecipeDetailText(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}
