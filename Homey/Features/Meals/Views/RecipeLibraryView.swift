import SwiftUI

struct RecipeLibraryView: View {
    let meals: [Meal]
    let canFavorite: Bool
    let isFavorite: (Meal) -> Bool
    let onToggleFavorite: (Meal) -> Void
    let onSelectMeal: (Meal) -> Void

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if meals.isEmpty {
                        MealLibraryEmptyCard()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(meals) { meal in
                                RecipeLibraryRow(
                                    meal: meal,
                                    isFavorite: isFavorite(meal),
                                    canFavorite: canFavorite,
                                    onToggleFavorite: { onToggleFavorite(meal) },
                                    onSelect: { onSelectMeal(meal) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Recipe Library")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipe Library")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Browse every saved recipe for this Home.")
                .font(.title3)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
    }
}

private struct RecipeLibraryRow: View {
    let meal: Meal
    let isFavorite: Bool
    let canFavorite: Bool
    let onToggleFavorite: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(HomeyDashboardTheme.selectedSidebarBackground)
                    Image(systemName: "fork.knife")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)

                    Text(meal.mealTypes.map(\.displayName).joined(separator: " • "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if canFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(isFavorite ? HomeyDashboardTheme.coralAccent : HomeyDashboardTheme.warmBrown)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }
            .padding(16)
            .dashboardCard(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }
}

private struct MealLibraryEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Recipes")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text("Create a meal to start building your family recipe library.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }
}
