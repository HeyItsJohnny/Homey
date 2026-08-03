import SwiftUI

struct MealDetailView: View {
    let meal: Meal
    let isFavorite: Bool
    let canFavorite: Bool
    let canEdit: Bool
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ZStack {
            HomeyDashboardTheme.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    detailsCard
                    notesCard
                }
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .padding(.bottom, 38)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(meal.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(meal.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                if let description = meal.description, !description.isEmpty {
                    Text(description)
                        .font(.title3)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
            }

            Spacer()

            if canEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 50, height: 50)
                        .background(HomeyDashboardTheme.cardBackground, in: Circle())
                        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                        .shadow(color: HomeyDashboardTheme.shadow, radius: 14, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit meal")
            }

            if canFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isFavorite ? HomeyDashboardTheme.coralAccent : HomeyDashboardTheme.warmBrown)
                        .frame(width: 50, height: 50)
                        .background(HomeyDashboardTheme.cardBackground, in: Circle())
                        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                        .shadow(color: HomeyDashboardTheme.shadow, radius: 14, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                MealDetailFact(title: "Type", value: meal.mealTypes.map(\.displayName).joined(separator: ", ").nilIfEmpty ?? "Not set")
                MealDetailFact(title: "Cuisine", value: meal.cuisine ?? "Not set")
                MealDetailFact(title: "Difficulty", value: meal.difficulty?.displayName ?? "Not set")
                MealDetailFact(title: "Total Time", value: totalTimeText)
                MealDetailFact(title: "Servings", value: meal.servings.map(String.init(describing:)) ?? "Not set")
            }
        }
        .padding(24)
        .dashboardCard(cornerRadius: 30)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            Text(meal.notes?.nilIfEmpty ?? "Recipe steps, ingredients, and photos will appear here as the Meals module expands.")
                .font(.subheadline)
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(cornerRadius: 30)
    }

    private var totalTimeText: String {
        let total = (meal.prepTimeMinutes ?? 0) + (meal.cookTimeMinutes ?? 0)
        guard total > 0 else { return "Not set" }
        return "\(total) min"
    }
}

private struct MealDetailFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeyDashboardTheme.appBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
