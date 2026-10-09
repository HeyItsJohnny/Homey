import SwiftUI

private struct MealPickerContext: Identifiable {
    let mealType: MealType
    var id: String { mealType.rawValue }
}

struct MealsHomeHubView: View {
    @EnvironmentObject private var homeService: HomeService
    @Environment(\.homePermissions) private var permissions
    @StateObject private var viewModel = MealsHomeHubViewModel()
    @State private var pickerContext: MealPickerContext?

    private var homeID: UUID? { homeService.selectedHomeID }
    private var timezoneIdentifier: String {
        homeService.selectedHome()?.timezone ?? TimeZone.autoupdatingCurrent.identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    plannerSurface
                        .frame(height: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await viewModel.refreshMealPlanner()
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 38)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .center)
        .task(id: "\(homeID?.uuidString ?? "no-home"):\(timezoneIdentifier)") {
            await viewModel.configure(homeID: homeID, timezoneIdentifier: timezoneIdentifier)
        }
        .sheet(item: $pickerContext) { context in
            HomeMealPicker(
                mealType: context.mealType,
                meals: viewModel.homeMeals,
                isSaving: viewModel.isSaving
            ) { meal in
                await viewModel.addMeal(meal, to: context.mealType)
            }
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Meals")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text("What's on the menu today?")
                    .font(.title3)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            Spacer()

            HStack(spacing: 10) {
                todayButton
                dateNavigator
            }
                .padding(.trailing, 70)
        }
    }

    private var todayButton: some View {
        Button {
            Task { await viewModel.returnToToday() }
        } label: {
            Text("Today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to today")
    }

    private var dateNavigator: some View {
        HStack(spacing: 7) {
            dateArrow(systemImage: "chevron.left", label: "Previous day") {
                await viewModel.moveSelectedDate(by: -1)
            }

            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.bold))
                Text(viewModel.selectedDateLabel)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.selectedDateLabel)

            dateArrow(systemImage: "chevron.right", label: "Next day") {
                await viewModel.moveSelectedDate(by: 1)
            }
        }
        .padding(5)
        .background(HomeyDashboardTheme.cardBackground, in: Capsule())
        .overlay {
            Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .shadow(color: HomeyDashboardTheme.shadow, radius: 10, x: 0, y: 5)
    }

    private func dateArrow(
        systemImage: String,
        label: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 36, height: 36)
                .background(HomeyDashboardTheme.warmBrown.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(label)
    }

    private var plannerSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                .padding(12)
                .background(
                    HomeyDashboardTheme.destructiveRed.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }

            HStack(alignment: .top, spacing: 16) {
                ForEach(MealsHomeHubViewModel.visibleMealTypes) { mealType in
                    mealSection(mealType)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay {
                if viewModel.isLoading && viewModel.itemsByType.isEmpty {
                    ProgressView("Loading meal plan…")
                        .tint(HomeyDashboardTheme.warmBrown)
                        .padding(20)
                        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(cornerRadius: 30)
    }

    private func mealSection(_ mealType: MealType) -> some View {
        let items = viewModel.items(for: mealType)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: mealType.systemImageName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(sectionColor(mealType))

                VStack(alignment: .leading, spacing: 2) {
                    Text(sectionTitle(mealType))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    Text("\(items.count) planned")
                        .font(.caption)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Spacer(minLength: 4)

                Button {
                    pickerContext = MealPickerContext(mealType: mealType)
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 34, height: 34)
                        .background(HomeyDashboardTheme.cardBackground, in: Circle())
                        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .disabled(!permissions.meals.canPlanMeals || viewModel.isSaving)
                .accessibilityLabel("Add \(sectionTitle(mealType)) meal")
            }
            .padding(14)
            .background(sectionColor(mealType).opacity(0.10))

            ScrollView {
                LazyVStack(spacing: 10) {
                    if items.isEmpty {
                        emptyState(mealType)
                    } else {
                        ForEach(items) { item in
                            plannedMealCard(item)
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.75), lineWidth: 1)
        }
    }

    private func plannedMealCard(_ item: MealPlanItem) -> some View {
        HStack(spacing: 11) {
            MealPhotoThumbnail(path: item.meal.primaryPhotoPath)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.meal.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.entry.isLeftover {
                    Label("Leftover", systemImage: "arrow.uturn.forward.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.sageAccent)
                }
            }

            if viewModel.isDeleting(item) {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyDashboardTheme.warmBrown)
            } else if permissions.meals.canPlanMeals {
                Menu {
                    Button("Remove", systemImage: "calendar.badge.minus", role: .destructive) {
                        Task { await viewModel.removeMeal(item) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Actions for \(item.meal.name)")
            }
        }
        .padding(10)
        .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.65), lineWidth: 1)
        }
    }

    private func emptyState(_ mealType: MealType) -> some View {
        VStack(spacing: 10) {
            Image(systemName: mealType.systemImageName)
                .font(.title2)
                .foregroundStyle(sectionColor(mealType))
            Text("No \(sectionTitle(mealType).lowercased()) planned")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
            if permissions.meals.canPlanMeals {
                Button {
                    pickerContext = MealPickerContext(mealType: mealType)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(sectionTitle(mealType)) meal")
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    private func sectionColor(_ mealType: MealType) -> Color {
        switch mealType {
        case .breakfast:
            return HomeyDashboardTheme.orangeAccent
        case .lunch:
            return HomeyDashboardTheme.sageAccent
        case .dinner:
            return HomeyDashboardTheme.lavenderAccent
        case .snack, .dessert, .drink:
            return HomeyDashboardTheme.warmBrown
        }
    }

    private func sectionTitle(_ mealType: MealType) -> String {
        mealType == .snack ? "Snacks" : mealType.displayName
    }
}

private struct HomeMealPicker: View {
    @Environment(\.dismiss) private var dismiss
    let mealType: MealType
    let meals: [Meal]
    let isSaving: Bool
    let onSelect: (Meal) async -> Bool

    @State private var searchText = ""
    @State private var selectedMealID: UUID?
    @State private var errorMessage: String?

    private var filteredMeals: [Meal] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meals }
        return meals.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView(
                        "No Home Meals Yet",
                        systemImage: "fork.knife",
                        description: Text("Home Meals will appear here when they are available.")
                    )
                } else if filteredMeals.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredMeals) { meal in
                                Button {
                                    add(meal)
                                } label: {
                                    HStack(spacing: 13) {
                                        MealPhotoThumbnail(path: meal.primaryPhotoPath)
                                            .frame(width: 62, height: 62)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(meal.name)
                                                .font(.headline)
                                                .foregroundStyle(HomeyDashboardTheme.primaryText)
                                                .multilineTextAlignment(.leading)
                                            if let description = meal.description, !description.isEmpty {
                                                Text(description)
                                                    .font(.caption)
                                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        if selectedMealID == meal.id || (isSaving && selectedMealID == meal.id) {
                                            ProgressView()
                                                .tint(HomeyDashboardTheme.warmBrown)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                        }
                                    }
                                    .padding(11)
                                    .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedMealID != nil || isSaving)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background(HomeyDashboardTheme.appBackground)
            .navigationTitle("Choose \(mealType == .snack ? "Snacks" : mealType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Home Meals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.destructiveRed)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(HomeyDashboardTheme.cardBackground)
                }
            }
        }
    }

    private func add(_ meal: Meal) {
        guard selectedMealID == nil else { return }
        selectedMealID = meal.id
        errorMessage = nil
        Task {
            if await onSelect(meal) {
                dismiss()
            } else {
                selectedMealID = nil
                errorMessage = "That meal couldn't be added. Please try again."
            }
        }
    }
}
