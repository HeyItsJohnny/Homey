import SwiftUI

struct HomeCalendarMealsView: View {
    @Environment(\.homePermissions) private var permissions
    @StateObject private var viewModel = HomeCalendarMealsViewModel()
    @State private var addSlot: HomeCalendarMealSlot?
    @State private var moveTarget: HomeCalendarMealMoveTarget?

    let homeId: UUID?
    let weekStartsOn: Int?
    let timezone: String?
    let onOpenMeal: (PlannedMeal) -> Void

    private let mealTypes: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeCalendarMealsHeader(
                weekTitle: viewModel.visibleWeekTitle,
                plannedMealCount: viewModel.plannedMealCount,
                isSaving: viewModel.isSaving,
                onPreviousWeek: viewModel.moveToPreviousWeek,
                onNextWeek: viewModel.moveToNextWeek,
                onToday: viewModel.moveToToday
            )

            if homeId == nil {
                HomeCalendarMealsMessage(
                    title: "Choose a Home",
                    message: "Select a Home before planning meals.",
                    systemImage: "house.fill"
                )
            } else if !permissions.meals.canViewMealPlan {
                HomeCalendarMealsMessage(
                    title: "Meal Plan Unavailable",
                    message: "You do not have permission to view this Home's meal plan.",
                    systemImage: "lock.fill"
                )
            } else {
                if let errorMessage = viewModel.errorMessage {
                    HomeCalendarMealsError(message: errorMessage) {
                        Task { await viewModel.reload() }
                    }
                }

                HomeCalendarMealsWeekGrid(
                    days: viewModel.weekDays(),
                    mealTypes: mealTypes,
                    categories: viewModel.categories,
                    plannedMeals: { day, mealType in
                        viewModel.plannedMeals(on: day, mealType: mealType)
                    },
                    onAdd: { day, mealType in
                        guard permissions.meals.canPlanMeals else {
                            viewModel.errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
                            return
                        }
                        addSlot = HomeCalendarMealSlot(date: day, mealType: mealType)
                    },
                    onOpen: onOpenMeal,
                    onMove: { plannedMeal in
                        moveTarget = HomeCalendarMealMoveTarget(
                            plannedMeal: plannedMeal,
                            date: plannedMeal.startsAt,
                            mealType: plannedMeal.mealType
                        )
                    },
                    onRemove: { plannedMeal in
                        Task { await viewModel.removeMeal(plannedMeal, permissions: permissions) }
                    }
                )
            }
        }
        .task(id: loadTaskId) {
            await viewModel.configure(homeId: homeId, weekStartsOn: weekStartsOn, timezone: timezone)
        }
        .overlay {
            if viewModel.isLoading && viewModel.plannedMeals.isEmpty {
                ProgressView()
                    .tint(HomeyDashboardTheme.warmBrown)
                    .padding(14)
                    .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                    .shadow(color: HomeyDashboardTheme.shadow, radius: 10, x: 0, y: 6)
                    .accessibilityLabel("Loading meal plan")
            }
        }
        .sheet(item: $addSlot) { slot in
            HomeCalendarMealPickerView(
                title: "Add \(slot.mealType.displayName)",
                date: slot.date,
                mealType: slot.mealType,
                meals: viewModel.meals.filter { viewModel.mealMatches($0, mealType: slot.mealType, searchText: "") },
                matches: { meal, searchText in
                    viewModel.mealMatches(meal, mealType: slot.mealType, searchText: searchText)
                },
                onCancel: { addSlot = nil },
                onSelect: { meal in
                    Task {
                        await viewModel.addMeal(meal, to: slot.date, mealType: slot.mealType, permissions: permissions)
                        addSlot = nil
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $moveTarget) { target in
            HomeCalendarMealMoveView(
                plannedMeal: target.plannedMeal,
                weekDays: viewModel.weekDays(),
                selectedDate: target.date,
                selectedMealType: target.mealType,
                onCancel: { moveTarget = nil },
                onMove: { date, mealType in
                    Task {
                        await viewModel.moveMeal(target.plannedMeal, to: date, mealType: mealType, permissions: permissions)
                        moveTarget = nil
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var loadTaskId: String {
        "\(homeId?.uuidString ?? "no-home")-\(weekStartsOn ?? -1)-\(timezone ?? "")"
    }
}

private struct HomeCalendarMealsHeader: View {
    let weekTitle: String
    let plannedMealCount: Int
    let isSaving: Bool
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                periodControls
                Spacer(minLength: 18)
                actions
            }

            VStack(alignment: .leading, spacing: 14) {
                periodControls
                actions
            }
        }
        .padding(18)
        .dashboardCard(cornerRadius: 26)
    }

    private var periodControls: some View {
        HStack(spacing: 10) {
            iconButton(systemImage: "chevron.left", label: "Previous week", action: onPreviousWeek)

            VStack(alignment: .leading, spacing: 3) {
                Text("This Week's Meal Plan")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(weekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            iconButton(systemImage: "chevron.right", label: "Next week", action: onNextWeek)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Today", action: onToday)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to today")

            Menu {
                Button("Shopping List") { }
                    .disabled(true)
                Button("Nutrition Summary") { }
                    .disabled(true)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .accessibilityLabel("Meal plan options")

            Text(plannedMealText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .tint(HomeyDashboardTheme.warmBrown)
            }
        }
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(HomeyDashboardTheme.warmBrown)
        .background(HomeyDashboardTheme.cardBackground, in: Circle())
        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
        .accessibilityLabel(label)
    }

    private var plannedMealText: String {
        "\(plannedMealCount) \(plannedMealCount == 1 ? "Meal" : "Meals") Planned"
    }
}

private struct HomeCalendarMealsWeekGrid: View {
    let days: [Date]
    let mealTypes: [MealType]
    let categories: [CalendarCategory]
    let plannedMeals: (Date, MealType) -> [PlannedMeal]
    let onAdd: (Date, MealType) -> Void
    let onOpen: (PlannedMeal) -> Void
    let onMove: (PlannedMeal) -> Void
    let onRemove: (PlannedMeal) -> Void

    private let labelColumnWidth: CGFloat = 132
    private let dayColumnWidth: CGFloat = 232
    private let dayHeaderHeight: CGFloat = 52
    private let mealRowHeight: CGFloat = 108
    private let columnSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: columnSpacing) {
                mealTypeLabels
                dayColumns
            }

            Text(plannedMealText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .padding(.horizontal, 4)
        }
        .padding(18)
        .dashboardCard(cornerRadius: 26)
    }

    private var mealTypeLabels: some View {
        VStack(alignment: .leading, spacing: columnSpacing) {
            Color.clear
                .frame(width: labelColumnWidth, height: dayHeaderHeight)

            ForEach(mealTypes) { mealType in
                HomeCalendarMealsTypeLabel(mealType: mealType)
                    .frame(width: labelColumnWidth, height: mealRowHeight, alignment: .leading)
            }
        }
    }

    private var dayColumns: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: columnSpacing) {
                HStack(spacing: columnSpacing) {
                    ForEach(days, id: \.self) { day in
                        HomeCalendarMealsDayHeader(date: day)
                            .frame(width: dayColumnWidth, height: dayHeaderHeight)
                    }
                }

                ForEach(mealTypes) { mealType in
                    HStack(spacing: columnSpacing) {
                        ForEach(days, id: \.self) { day in
                            HomeCalendarMealsSlot(
                                date: day,
                                mealType: mealType,
                                plannedMeals: plannedMeals(day, mealType),
                                categories: categories,
                                onAdd: { onAdd(day, mealType) },
                                onOpen: onOpen,
                                onMove: onMove,
                                onRemove: onRemove
                            )
                            .frame(width: dayColumnWidth, height: mealRowHeight)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var plannedMealCount: Int {
        Set(days.flatMap { day in
            mealTypes.flatMap { mealType in
                plannedMeals(day, mealType).map(\.id)
            }
        }).count
    }

    private var plannedMealText: String {
        "\(plannedMealCount) \(plannedMealCount == 1 ? "Meal" : "Meals") Planned"
    }
}

private struct HomeCalendarMealsDayHeader: View {
    let date: Date

    var body: some View {
        VStack(spacing: 3) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Text(Self.dayFormatter.string(from: date))
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)

            Text(isToday ? "Today" : " ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(isToday ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isToday ? HomeyDashboardTheme.warmBrown.opacity(0.38) : HomeyDashboardTheme.softBorder.opacity(0.72), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var isToday: Bool {
        Calendar.autoupdatingCurrent.isDateInToday(date)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}

private struct HomeCalendarMealsTypeLabel: View {
    let mealType: MealType

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: mealType.systemImageName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 30, height: 30)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

            Text(mealType.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct HomeCalendarMealsSlot: View {
    let date: Date
    let mealType: MealType
    let plannedMeals: [PlannedMeal]
    let categories: [CalendarCategory]
    let onAdd: () -> Void
    let onOpen: (PlannedMeal) -> Void
    let onMove: (PlannedMeal) -> Void
    let onRemove: (PlannedMeal) -> Void

    var body: some View {
        VStack(spacing: 5) {
            if plannedMeals.isEmpty {
                Button(action: onAdd) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("Add")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(HomeyDashboardTheme.appBackground.opacity(0.36), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(HomeyDashboardTheme.softBorder.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Self.accessibilityDateFormatter.string(from: date)) \(mealType.displayName), add meal")
            } else {
                ForEach(plannedMeals.prefix(2)) { plannedMeal in
                    HomeCalendarMealCard(
                        plannedMeal: plannedMeal,
                        categories: categories,
                        onOpen: { onOpen(plannedMeal) },
                        onMove: { onMove(plannedMeal) },
                        onRemove: { onRemove(plannedMeal) }
                    )
                }

                if plannedMeals.count > 2 {
                    Text("+\(plannedMeals.count - 2) more")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(HomeyDashboardTheme.cardBackground.opacity(0.74), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.76), lineWidth: 1)
        }
    }

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return formatter
    }()
}

private struct HomeCalendarMealCard: View {
    let plannedMeal: PlannedMeal
    let categories: [CalendarCategory]
    let onOpen: () -> Void
    let onMove: () -> Void
    let onRemove: () -> Void

    @State private var isShowingActions = false

    var body: some View {
        Button {
            isShowingActions = true
        } label: {
            HStack(spacing: 7) {
                thumbnail

                Text(plannedMeal.meal.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: false)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .leading)
            .clipped()
            .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(accentColor.opacity(0.44), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog(plannedMeal.meal.name, isPresented: $isShowingActions, titleVisibility: .visible) {
            Button("Open Recipe", action: onOpen)
            Button("Reschedule", action: onMove)
            Button("Remove from Plan", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) { }
        }
        .accessibilityLabel("\(plannedMeal.mealType.displayName), \(plannedMeal.meal.name). Double tap for actions.")
    }

    private var thumbnail: some View {
        Group {
            if let url = plannedMeal.signedPhotoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(HomeyDashboardTheme.selectedSidebarBackground)
            .overlay {
                Image(systemName: plannedMeal.mealType.systemImageName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
    }

    private var accentColor: Color {
        CalendarEventColorResolver.color(for: plannedMeal.calendarEvent, categories: categories, fallback: HomeyDashboardTheme.warmBrown)
    }
}

private struct HomeCalendarMealPickerView: View {
    let title: String
    let date: Date
    let mealType: MealType
    let meals: [Meal]
    let matches: (Meal, String) -> Bool
    let onCancel: () -> Void
    let onSelect: (Meal) -> Void

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()
                List(filteredMeals) { meal in
                    Button {
                        onSelect(meal)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: meal.mealTypes.first?.systemImageName ?? mealType.systemImageName)
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                .frame(width: 34, height: 34)
                                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(meal.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                                Text(slotText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(HomeyDashboardTheme.cardBackground)
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search recipes")
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var filteredMeals: [Meal] {
        meals.filter { matches($0, searchText) }
    }

    private var slotText: String {
        "\(Self.dateFormatter.string(from: date)) · \(mealType.displayName)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()
}

private struct HomeCalendarMealMoveView: View {
    let plannedMeal: PlannedMeal
    let weekDays: [Date]
    let onCancel: () -> Void
    let onMove: (Date, MealType) -> Void

    @State private var selectedDate: Date
    @State private var selectedMealType: MealType

    init(
        plannedMeal: PlannedMeal,
        weekDays: [Date],
        selectedDate: Date,
        selectedMealType: MealType,
        onCancel: @escaping () -> Void,
        onMove: @escaping (Date, MealType) -> Void
    ) {
        self.plannedMeal = plannedMeal
        self.weekDays = weekDays
        self.onCancel = onCancel
        self.onMove = onMove
        _selectedDate = State(initialValue: selectedDate)
        _selectedMealType = State(initialValue: selectedMealType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Text(plannedMeal.meal.name)
                }

                Section("Date") {
                    Picker("Date", selection: $selectedDate) {
                        ForEach(weekDays, id: \.self) { day in
                            Text(Self.dayFormatter.string(from: day)).tag(day)
                        }
                    }
                }

                Section("Meal Type") {
                    Picker("Meal Type", selection: $selectedMealType) {
                        ForEach([MealType.breakfast, .lunch, .dinner, .snack]) { mealType in
                            Text(mealType.displayName).tag(mealType)
                        }
                    }
                }
            }
            .navigationTitle("Reschedule Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        onMove(selectedDate, selectedMealType)
                    }
                }
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()
}

private struct HomeCalendarMealsMessage: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 42, height: 42)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            Spacer()
        }
        .padding(18)
        .dashboardCard(cornerRadius: 24)
    }
}

private struct HomeCalendarMealsError: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeyDashboardTheme.orangeAccent)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.footnote.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
    }
}

private struct HomeCalendarMealSlot: Identifiable {
    let id = UUID()
    let date: Date
    let mealType: MealType
}

private struct HomeCalendarMealMoveTarget: Identifiable {
    let plannedMeal: PlannedMeal
    let date: Date
    let mealType: MealType

    var id: String {
        plannedMeal.id
    }
}
