import SwiftUI

struct MealPlannerView: View {
    @ObservedObject var viewModel: MealPlannerViewModel
    let meals: [Meal]
    let favoriteMeals: [Meal]
    let collections: [MealCollection]
    let householdMembers: [HomeMemberDisplay]
    let permissions: HomePermissions
    let selectedHomeID: UUID?
    let weekStartsOn: Int?
    let timezone: String?
    let onSelectMeal: (Meal) -> Void
    let onOpenCalendar: (Date?) -> Void
    let onComingSoon: (String) -> Void

    @State private var activeAddSlot: MealPlannerSlot?
    @State private var pendingSelection: MealPlannerPendingSelection?
    @State private var moveTarget: MealPlannerMoveTarget?
    @State private var isAutoPlanPresented = false
    @State private var isResetPlanConfirmationPresented = false

    private let defaultSlotTypes: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            viewModePicker
            content
            summaryBar
        }
        .task(id: loadTaskID) {
            viewModel.load(homeId: selectedHomeID, weekStartsOn: weekStartsOn, timezone: timezone)
        }
        .alert("Meal Planner", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "We could not update the meal plan.")
        }
        .sheet(item: $activeAddSlot) { slot in
            MealPlannerPickerView(
                title: "Add \(slot.mealType.displayName)",
                meals: meals,
                favoriteMeals: favoriteMeals,
                collections: collections,
                preselectedMealType: slot.mealType,
                onCancel: { activeAddSlot = nil },
                onSelectMeal: { meal in
                    activeAddSlot = nil
                    pendingSelection = MealPlannerPendingSelection(meal: meal, date: slot.date, mealType: slot.mealType)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingSelection) { selection in
            MealPlannerConfirmationView(selection: selection) { servings, notes in
                Task {
                    await viewModel.addMeal(selection.meal, to: selection.date, mealType: selection.mealType, servings: servings, notes: notes, permissions: permissions)
                    pendingSelection = nil
                }
            } onCancel: {
                pendingSelection = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $moveTarget) { target in
            MealPlannerMoveView(
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
        .sheet(isPresented: $isAutoPlanPresented) {
            AutoPlanSheet(
                viewModel: viewModel,
                meals: meals,
                favoriteMeals: favoriteMeals,
                collections: collections,
                householdMembers: householdMembers,
                permissions: permissions,
                onDismiss: { isAutoPlanPresented = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Reset Plan", isPresented: $isResetPlanConfirmationPresented) {
            Button("No", role: .cancel) { }
            Button("Yes", role: .destructive) {
                Task {
                    await viewModel.resetVisibleWeekPlan(permissions: permissions)
                }
            }
        } message: {
            Text(resetPlanConfirmationMessage)
        }
        .overlay {
            if viewModel.isResettingPlan {
                ResetPlanProgressDialog(
                    completedCount: viewModel.resetPlanCompletedCount,
                    totalCount: viewModel.resetPlanTotalCount
                )
            }
        }
    }

    private var loadTaskID: String {
        "\(selectedHomeID?.uuidString ?? "no-home")-\(weekStartsOn ?? -1)-\(timezone ?? "")"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                viewModel.moveToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .background(HomeyDashboardTheme.cardBackground, in: Circle())
            .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            .accessibilityLabel("Previous week")

            VStack(alignment: .leading, spacing: 2) {
                Text("This Week")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(viewModel.visibleWeekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            Button {
                viewModel.moveToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .background(HomeyDashboardTheme.cardBackground, in: Circle())
            .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            .accessibilityLabel("Next week")

            Spacer()

            Text("\(viewModel.plannedMealCount) Meals Planned")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)

            Button("Today") { viewModel.moveToToday() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to today")

            Button("Auto Plan") {
                if permissions.meals.canRunAutoPlan {
                    isAutoPlanPresented = true
                } else {
                    onComingSoon("You do not have permission to run Auto Plan.")
                }
            }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                .overlay { Capsule().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                .buttonStyle(.plain)

            Button("Reset Plan") {
                if permissions.meals.canClearMealPlan {
                    isResetPlanConfirmationPresented = true
                } else {
                    onComingSoon("You do not have permission to reset this week's meal plan.")
                }
            }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(Color.red, in: Capsule())
                .buttonStyle(.plain)
                .disabled(viewModel.plannedMealCount == 0 || viewModel.isSaving || viewModel.isResettingPlan)
                .opacity((viewModel.plannedMealCount == 0 || viewModel.isResettingPlan) ? 0.55 : 1)

            Menu {
                Button("Generate Shopping List") { onComingSoon("Shopping lists are coming in the next phase.") }
                Button("Nutrition Summary") { onComingSoon("Nutrition summary is coming soon.") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .accessibilityLabel("Meal planner options")
        }
    }

    private var viewModePicker: some View {
        Picker("Meal planner view", selection: $viewModel.displayMode) {
            ForEach(MealPlannerDisplayMode.visibleModes) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 440)
        .padding(.bottom, 2)
        .accessibilityLabel("Meal planner view")
    }

    @ViewBuilder
    private var content: some View {
        if selectedHomeID == nil {
            MealPlannerMessageCard(title: "Choose a Home", message: "Select a Home before planning meals.", systemImage: "house.fill")
        } else if !permissions.meals.canViewMealPlan {
            MealPlannerMessageCard(title: "Meal Plan Unavailable", message: "You do not have permission to view this Home's meal plan.", systemImage: "lock.fill")
        } else if viewModel.isLoading && viewModel.plannedMeals.isEmpty {
            MealPlannerLoadingGrid()
        } else {
            switch viewModel.displayMode {
            case .weekly:
                weeklyGrid
            case .monthly:
                monthlyView
            case .list:
                listView
            }
        }
    }

    private var weeklyGrid: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(viewModel.weekDays(), id: \.self) { day in
                    MealPlannerDayColumn(
                        date: day,
                        isToday: Calendar.autoupdatingCurrent.isDateInToday(day),
                        isSelected: Calendar.autoupdatingCurrent.isDate(day, inSameDayAs: viewModel.selectedDate),
                        slotTypes: defaultSlotTypes,
                        plannedMeals: { mealType in viewModel.plannedMeals(on: day, mealType: mealType) },
                        onSelectDay: { viewModel.selectDate(day) },
                        onAdd: { mealType in activeAddSlot = MealPlannerSlot(date: day, mealType: mealType) },
                        onOpen: { plannedMeal in onSelectMeal(plannedMeal.meal) },
                        onMove: { plannedMeal in moveTarget = MealPlannerMoveTarget(plannedMeal: plannedMeal, date: day, mealType: plannedMeal.mealType) },
                        onRemove: { plannedMeal in Task { await viewModel.removeMeal(plannedMeal, permissions: permissions) } },
                        onDropMeal: { plannedMeal, mealType in Task { await viewModel.moveMeal(plannedMeal, to: day, mealType: mealType, permissions: permissions) } },
                        draggedMeal: draggedMeal(with:),
                        categories: viewModel.categories
                    )
                    .frame(width: 210, alignment: .top)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Weekly meal planner")
    }

    private var monthlyView: some View {
        let grouped = viewModel.mealsForMonth()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
            ForEach(viewModel.weekDays(), id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.dayHeaderFormatter.string(from: day))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    ForEach((grouped[Calendar.autoupdatingCurrent.startOfDay(for: day)] ?? []).prefix(3)) { plannedMeal in
                        HStack(spacing: 6) {
                            Image(systemName: plannedMeal.mealType.systemImageName)
                            Text(plannedMeal.meal.name).lineLimit(1)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(minHeight: 110, alignment: .topLeading)
                .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
            }
        }
    }

    private var listView: some View {
        VStack(spacing: 12) {
            if viewModel.plannedMeals.isEmpty {
                MealPlannerMessageCard(title: "No Planned Meals", message: "Add recipes to breakfast, lunch, dinner, or snack slots to build the week.", systemImage: "calendar.badge.plus")
            } else {
                ForEach(viewModel.plannedMeals) { plannedMeal in
                    MealPlannerListRow(plannedMeal: plannedMeal, categories: viewModel.categories) {
                        onSelectMeal(plannedMeal.meal)
                    } onMove: {
                        moveTarget = MealPlannerMoveTarget(plannedMeal: plannedMeal, date: plannedMeal.startsAt, mealType: plannedMeal.mealType)
                    } onRemove: {
                        Task { await viewModel.removeMeal(plannedMeal, permissions: permissions) }
                    }
                }
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 14) {
            Label("\(viewModel.plannedMealCount) planned", systemImage: "calendar.badge.checkmark")
            Label("\(viewModel.uniqueRecipeCount) recipes", systemImage: "fork.knife")
            Spacer()
            Button("Generate Shopping List") { onComingSoon("Shopping lists are coming in the next phase.") }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
            Button("Nutrition Summary") { onComingSoon("Nutrition summary is coming soon.") }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .buttonStyle(.plain)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(HomeyDashboardTheme.primaryText)
        .padding(16)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private func draggedMeal(with id: String) -> PlannedMeal? {
        viewModel.plannedMeals.first { $0.id == id }
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter
    }()

    private var resetPlanConfirmationMessage: String {
        "Do you want to reset the plan for the week of \(viewModel.resetPlanWeekStartTitle)?"
    }
}

private struct ResetPlanProgressDialog: View {
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView(value: progress)
                    .tint(HomeyDashboardTheme.warmBrown)

                VStack(spacing: 4) {
                    Text("Resetting Meal Plan")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    Text(progressText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 12)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resetting meal plan")
        .accessibilityValue(progressText)
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(min(completedCount, totalCount)) / Double(totalCount)
    }

    private var progressText: String {
        guard totalCount > 0 else {
            return "Preparing reset..."
        }
        return "Removing \(min(completedCount, totalCount)) of \(totalCount) planned meals..."
    }
}

private enum AutoPlanSheetFlowState {
    case configuration
    case preview
}

private struct AutoPlanSheet: View {
    @ObservedObject var viewModel: MealPlannerViewModel
    let meals: [Meal]
    let favoriteMeals: [Meal]
    let collections: [MealCollection]
    let householdMembers: [HomeMemberDisplay]
    let permissions: HomePermissions
    let onDismiss: () -> Void

    @State private var configuration: AutoPlanConfiguration
    @State private var manualReplacementTarget: AutoPlanManualReplacementTarget?
    @State private var flowState: AutoPlanSheetFlowState = .configuration

    init(
        viewModel: MealPlannerViewModel,
        meals: [Meal],
        favoriteMeals: [Meal],
        collections: [MealCollection],
        householdMembers: [HomeMemberDisplay],
        permissions: HomePermissions,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.meals = meals
        self.favoriteMeals = favoriteMeals
        self.collections = collections
        self.householdMembers = householdMembers
        self.permissions = permissions
        self.onDismiss = onDismiss
        _configuration = State(initialValue: viewModel.defaultAutoPlanConfiguration())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch flowState {
                        case .configuration:
                            configurationContent
                        case .preview:
                            if let draft = viewModel.autoPlanDraft {
                                previewContent(draft)
                            } else {
                                configurationContent
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(flowState == .preview ? "Auto Plan Preview" : "Auto Plan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $manualReplacementTarget) { target in
                MealPlannerPickerView(
                    title: "Choose \(target.mealType.displayName)",
                    meals: meals,
                    favoriteMeals: favoriteMeals,
                    collections: collections,
                    preselectedMealType: target.mealType,
                    onCancel: { manualReplacementTarget = nil },
                    onSelectMeal: { meal in
                        viewModel.manuallySelectAutoPlanMeal(meal, for: target.slotId)
                        manualReplacementTarget = nil
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto Plan only fills empty meal slots. Existing plans will not be changed.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                Text("Week")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(viewModel.visibleWeekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Days")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                    ForEach(viewModel.autoPlanSelectableWeekDays(), id: \.self) { day in
                        autoPlanToggleChip(
                            title: Self.dayFormatter.string(from: day),
                            isSelected: configuration.selectedDates.contains(day)
                        ) {
                            toggle(day, in: \.selectedDates)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Meal Types")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                    ForEach([MealType.breakfast, .lunch, .dinner, .snack]) { mealType in
                        autoPlanToggleChip(
                            title: mealType.displayName,
                            systemImage: mealType.systemImageName,
                            isSelected: configuration.selectedMealTypes.contains(mealType)
                        ) {
                            toggle(mealType, in: \.selectedMealTypes)
                        }
                    }
                }
            }

            Picker("Recipe Pool", selection: $configuration.recipePool) {
                ForEach(AutoPlanRecipePoolMode.allCases) { pool in
                    Text(pool.title).tag(pool)
                }
            }
            .pickerStyle(.segmented)
            Text(configuration.recipePool.description)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)

            Toggle("Allow repeats when necessary", isOn: $configuration.allowsRepeats)
                .font(.subheadline.weight(.semibold))
                .tint(HomeyDashboardTheme.warmBrown)

            if viewModel.autoPlanDraft == nil, let message = viewModel.autoPlanResultMessage {
                MealPlannerMessageCard(
                    title: "Auto Plan Result",
                    message: message,
                    systemImage: "info.circle"
                )
            }

            if viewModel.autoPlanDraft == nil, let errorMessage = viewModel.errorMessage {
                MealPlannerMessageCard(
                    title: "Auto Plan Error",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
            }

            if let unavailableMessage = viewModel.autoPlanUnavailableMessage() {
                MealPlannerMessageCard(
                    title: "Auto Plan Unavailable",
                    message: unavailableMessage,
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else {
                if let disabledReason = generateDisabledReason {
                    Text(disabledReason)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }

                Button {
                    #if DEBUG
                    print("AutoPlan Generate button tapped")
                    #endif
                    Task {
                        await viewModel.generateAutoPlan(configuration: configuration, meals: meals, members: householdMembers, permissions: permissions)
                        if viewModel.autoPlanDraft != nil {
                            #if DEBUG
                            print("preview_navigation_requested")
                            #endif
                            flowState = .preview
                        }
                    }
                } label: {
                    if viewModel.isAutoPlanGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Generating...")
                        }
                    } else {
                        Text("Generate Plan")
                    }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(generateDisabledReason != nil || viewModel.isAutoPlanGenerating)
            }
        }
        .padding(18)
        .dashboardCard(cornerRadius: 24)
    }

    private func previewContent(_ draft: AutoPlanDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    flowState = .configuration
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Options")
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)

                Spacer()

                Button("Regenerate All Suggestions") {
                    viewModel.regenerateAutoPlanSuggestions()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
            }

            Text("Preview")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)

            fairnessSummary(for: draft)

            ForEach(groupedSlots(draft.slots), id: \.date) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.fullDayFormatter.string(from: group.date))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)

                    ForEach(group.slots) { slot in
                        AutoPlanPreviewRow(
                            slot: slot,
                            attributionText: attributionText(for: slot.suggestion, recipePool: draft.configuration.recipePool),
                            onReroll: { viewModel.rerollAutoPlanSlot(slot.id) },
                            onReplace: { manualReplacementTarget = AutoPlanManualReplacementTarget(slotId: slot.id, mealType: slot.mealType) },
                            onRemove: { viewModel.removeAutoPlanSuggestion(slot.id) }
                        )
                    }
                }
                .padding(14)
                .background(HomeyDashboardTheme.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if let message = viewModel.autoPlanResultMessage {
                MealPlannerMessageCard(
                    title: "Auto Plan Result",
                    message: message,
                    systemImage: draft.creatableSlots.isEmpty ? "info.circle" : "checkmark.circle"
                )
            }

            if let errorMessage = viewModel.errorMessage {
                MealPlannerMessageCard(
                    title: "Auto Plan Error",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
            }

            Button {
                Task {
                    await viewModel.applyAutoPlan(permissions: permissions)
                    onDismiss()
                }
            } label: {
                if viewModel.isAutoPlanApplying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Apply Plan")
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(viewModel.isAutoPlanApplying || draft.creatableSlots.isEmpty)
        }
        .padding(18)
        .dashboardCard(cornerRadius: 24)
        .onAppear {
            #if DEBUG
            print("AUTO PLAN PREVIEW APPEARED")
            print("preview_suggestion_count: \(draft.creatableSlots.count)")
            print("preview_existing_count: \(draft.slots.filter(\.isFilled).count)")
            print("preview_unfilled_count: \(draft.slots.filter { $0.suggestion?.status == .noSuggestion }.count)")
            #endif
        }
    }

    private var generateDisabledReason: String? {
        viewModel.autoPlanDisabledReason(configuration: configuration, permissions: permissions)
    }

    private func fairnessSummary(for draft: AutoPlanDraft) -> some View {
        let represented = draft.memberSuggestionCounts.filter { $0.value > 0 }
        let creatableSuggestions = draft.creatableSlots
        let favoriteSuggestionCount = creatableSuggestions.filter { $0.suggestion?.favoriteMemberIds.isEmpty == false }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(summaryTitle(for: draft, favoriteSuggestionCount: favoriteSuggestionCount, suggestionCount: creatableSuggestions.count, representedCount: represented.count))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            if draft.configuration.recipePool == .includeFavorites && !represented.isEmpty {
                Text(represented.map { "\(viewModel.memberName(for: $0.key)): \($0.value)" }.joined(separator: "  "))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
        }
    }

    private func summaryTitle(for draft: AutoPlanDraft, favoriteSuggestionCount: Int, suggestionCount: Int, representedCount: Int) -> String {
        if draft.configuration.recipePool == .allRecipes {
            return "Planning from all eligible recipes."
        }
        if favoriteSuggestionCount == 0 {
            return "No eligible favorites matched these meal types, so Auto Plan used other recipes."
        }
        if representedCount > 0 {
            return "Favorites from \(representedCount) household members are represented."
        }
        return "\(favoriteSuggestionCount) of \(suggestionCount) suggestions include member favorites."
    }

    private func autoPlanToggleChip(title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isSelected ? .white : HomeyDashboardTheme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.appBackground.opacity(0.58), in: Capsule())
            .overlay {
                Capsule().stroke(isSelected ? Color.clear : HomeyDashboardTheme.softBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<AutoPlanConfiguration, Set<T>>) {
        if configuration[keyPath: keyPath].contains(value) {
            configuration[keyPath: keyPath].remove(value)
        } else {
            configuration[keyPath: keyPath].insert(value)
        }
    }

    private func groupedSlots(_ slots: [AutoPlanSlot]) -> [(date: Date, slots: [AutoPlanSlot])] {
        Dictionary(grouping: slots, by: \.date)
            .map { (date: $0.key, slots: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func attributionText(for suggestion: AutoPlanSuggestion?, recipePool: AutoPlanRecipePoolMode) -> String {
        guard let suggestion else { return "" }
        guard !suggestion.favoriteMemberIds.isEmpty else {
            return suggestion.status == .manuallySelected ? "Manually selected" : "Recipe library"
        }
        let names = suggestion.favoriteMemberIds.map { viewModel.memberName(for: $0) }
        if recipePool == .allRecipes {
            if names.count == 1 {
                return "Favorited by \(names[0])"
            }
            return "Favorited by \(names.dropLast().joined(separator: ", ")) and \(names.last ?? "")"
        }
        if names.count == 1 {
            return "\(names[0])'s favorite"
        }
        return "Favorited by \(names.dropLast().joined(separator: ", ")) and \(names.last ?? "")"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter
    }()
}

private struct AutoPlanPreviewRow: View {
    let slot: AutoPlanSlot
    let attributionText: String
    let onReroll: () -> Void
    let onReplace: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: slot.mealType.systemImageName)
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 40, height: 40)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(slot.mealType.displayName)
                        .font(.subheadline.weight(.bold))
                    Text(slot.suggestion?.status.title ?? "No Suggestion")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }
                Text(slot.suggestion?.meal?.name ?? slot.existingPlannedMeals.first?.meal.name ?? "No eligible recipe")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                    .lineLimit(2)
                if !attributionText.isEmpty {
                    Text(attributionText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
            }

            Spacer()

            if slot.suggestion?.status == .suggested {
                Button("Reroll", action: onReroll)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .buttonStyle(.plain)
            }
            if slot.suggestion?.status != .existing {
                Button("Replace", action: onReplace)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .buttonStyle(.plain)
            }
            if slot.suggestion?.isCreatable == true {
                Button("Remove", action: onRemove)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(HomeyDashboardTheme.appBackground.opacity(0.46), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusColor: Color {
        switch slot.suggestion?.status {
        case .existing:
            return HomeyDashboardTheme.sageAccent
        case .suggested, .manuallySelected:
            return HomeyDashboardTheme.warmBrown
        case .noSuggestion, nil:
            return HomeyDashboardTheme.secondaryText
        }
    }
}

private struct AutoPlanManualReplacementTarget: Identifiable {
    let slotId: AutoPlanSlotID
    let mealType: MealType

    var id: String {
        slotId.description
    }
}

struct UpcomingMealsPreviewView: View {
    @ObservedObject var viewModel: MealPlannerViewModel
    let meals: [Meal]
    let favoriteMeals: [Meal]
    let collections: [MealCollection]
    let permissions: HomePermissions
    let selectedHomeID: UUID?
    let weekStartsOn: Int?
    let timezone: String?
    let onSelectMeal: (Meal) -> Void
    let onShowPlanner: () -> Void

    @State private var activeAddSlot: MealPlannerSlot?
    @State private var pendingSelection: MealPlannerPendingSelection?
    @State private var moveTarget: MealPlannerMoveTarget?

    private let previewMealTypes: [MealType] = [.breakfast, .lunch, .dinner]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if selectedHomeID == nil {
                compactMessage(title: "Choose a Home", message: "Select a Home before planning meals.", systemImage: "house.fill")
            } else if !permissions.meals.canView {
                compactMessage(title: "Meal Plan Unavailable", message: "You do not have permission to view this Home's meal plan.", systemImage: "lock.fill")
            } else if viewModel.isLoading && viewModel.plannedMeals.isEmpty {
                UpcomingMealsPreviewLoadingRows()
            } else {
                if let errorMessage = viewModel.errorMessage {
                    compactError(message: errorMessage)
                }

                let days = viewModel.upcomingPreviewDays(count: 3)
                ViewThatFits(in: .horizontal) {
                    upcomingMealColumns(days: days)
                        .frame(maxWidth: .infinity, alignment: .center)

                    ScrollView(.horizontal) {
                        upcomingMealColumns(days: days)
                    }
                    .scrollIndicators(.hidden)
                }

                if !hasPlannedMealsInPreview {
                    Text("Nothing planned yet. Add a meal to get started.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .padding(.top, 2)
                }
            }
        }
        .padding(18)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.10), radius: 12, x: 0, y: 8)
        .task(id: loadTaskID) {
            viewModel.loadPreview(homeId: selectedHomeID, weekStartsOn: weekStartsOn, timezone: timezone)
        }
        .sheet(item: $activeAddSlot) { slot in
            MealPlannerPickerView(
                title: "Add \(slot.mealType.displayName)",
                meals: meals,
                favoriteMeals: favoriteMeals,
                collections: collections,
                preselectedMealType: slot.mealType,
                onCancel: { activeAddSlot = nil },
                onSelectMeal: { meal in
                    activeAddSlot = nil
                    pendingSelection = MealPlannerPendingSelection(meal: meal, date: slot.date, mealType: slot.mealType)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingSelection) { selection in
            MealPlannerConfirmationView(selection: selection) { servings, notes in
                Task {
                    await viewModel.addMeal(selection.meal, to: selection.date, mealType: selection.mealType, servings: servings, notes: notes, permissions: permissions)
                    pendingSelection = nil
                }
            } onCancel: {
                pendingSelection = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $moveTarget) { target in
            MealPlannerMoveView(
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Upcoming Meals")
                .font(.title3.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button("View Full Planner", action: onShowPlanner)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
                .accessibilityLabel("View full meal planner")
        }
    }

    private var loadTaskID: String {
        "\(selectedHomeID?.uuidString ?? "no-home")-\(weekStartsOn ?? -1)-\(timezone ?? "")"
    }

    private var hasPlannedMealsInPreview: Bool {
        viewModel.upcomingPreviewDays(count: 3).contains { day in
            previewMealTypes.contains { mealType in
                !viewModel.plannedMeals(on: day, mealType: mealType).isEmpty
            }
        }
    }

    private func upcomingMealColumns(days: [Date]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                UpcomingMealsPreviewDayColumn(
                    date: day,
                    title: dayTitle(for: day, index: index),
                    mealTypes: previewMealTypes,
                    plannedMeals: { mealType in viewModel.plannedMeals(on: day, mealType: mealType) },
                    categories: viewModel.categories,
                    onAdd: { mealType in activeAddSlot = MealPlannerSlot(date: day, mealType: mealType) },
                    onOpen: { plannedMeal in onSelectMeal(plannedMeal.meal) },
                    onMove: { plannedMeal in
                        moveTarget = MealPlannerMoveTarget(plannedMeal: plannedMeal, date: plannedMeal.startsAt, mealType: plannedMeal.mealType)
                    },
                    onRemove: { plannedMeal in
                        Task { await viewModel.removeMeal(plannedMeal, permissions: permissions) }
                    }
                )
                .frame(width: 250, alignment: .top)
            }
        }
        .padding(.vertical, 2)
    }

    private func compactMessage(title: String, message: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 38, height: 38)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .background(HomeyDashboardTheme.appBackground.opacity(0.46), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactError(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HomeyDashboardTheme.orangeAccent)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                viewModel.loadPreview(homeId: selectedHomeID, weekStartsOn: weekStartsOn, timezone: timezone)
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(HomeyDashboardTheme.appBackground.opacity(0.46), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dayTitle(for day: Date, index: Int) -> String {
        switch index {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return Self.weekdayFormatter.string(from: day)
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()
}

private struct UpcomingMealsPreviewFilledRow: View {
    var showsMealTypeLabel = true
    let day: Date
    let mealType: MealType
    let plannedMeals: [PlannedMeal]
    let categories: [CalendarCategory]
    let onOpen: (PlannedMeal) -> Void
    let onMove: (PlannedMeal) -> Void
    let onRemove: (PlannedMeal) -> Void

    @State private var isShowingActions = false

    private var primaryMeal: PlannedMeal? {
        plannedMeals.first
    }

    var body: some View {
        if let primaryMeal {
            Button {
                isShowingActions = true
            } label: {
                HStack(spacing: 10) {
                    if showsMealTypeLabel {
                        mealTypeLabel
                    }
                    thumbnail(for: primaryMeal)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryMeal.meal.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.primaryText)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Text(Self.timeFormatter.string(from: primaryMeal.startsAt))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if plannedMeals.count > 1 {
                        Text("+\(plannedMeals.count - 1) more")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(HomeyDashboardTheme.selectedSidebarBackground, in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(HomeyDashboardTheme.appBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accentColor(for: primaryMeal).opacity(0.28), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .confirmationDialog(primaryMeal.meal.name, isPresented: $isShowingActions, titleVisibility: .visible) {
                Button("Open Recipe") { onOpen(primaryMeal) }
                Button("Open / Reschedule") { onMove(primaryMeal) }
                Button("Delete Planned Meal", role: .destructive) { onRemove(primaryMeal) }
                Button("Cancel", role: .cancel) { }
            }
            .accessibilityLabel("\(mealType.displayName), \(primaryMeal.meal.name), \(dayAccessibilityFormatter.string(from: day)) at \(Self.timeFormatter.string(from: primaryMeal.startsAt)). Double tap for actions.")
            .accessibilityAction(named: "Open Recipe") { onOpen(primaryMeal) }
            .accessibilityAction(named: "Open or Reschedule") { onMove(primaryMeal) }
            .accessibilityAction(named: "Delete Planned Meal") { onRemove(primaryMeal) }
        }
    }

    private var mealTypeLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: mealType.systemImageName)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 18)
            Text(mealType.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 98, alignment: .leading)
    }

    @ViewBuilder
    private func thumbnail(for plannedMeal: PlannedMeal) -> some View {
        if let url = plannedMeal.signedPhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ProgressView().controlSize(.small)
                case .failure:
                    fallbackThumbnail
                @unknown default:
                    fallbackThumbnail
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            fallbackThumbnail
        }
    }

    private var fallbackThumbnail: some View {
        Image(systemName: "fork.knife")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(width: 42, height: 42)
            .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func accentColor(for plannedMeal: PlannedMeal) -> Color {
        CalendarEventColorResolver.color(for: plannedMeal.calendarEvent, categories: categories, fallback: HomeyDashboardTheme.warmBrown)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private let dayAccessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

private struct UpcomingMealsPreviewDayColumn: View {
    let date: Date
    let title: String
    let mealTypes: [MealType]
    let plannedMeals: (MealType) -> [PlannedMeal]
    let categories: [CalendarCategory]
    let onAdd: (MealType) -> Void
    let onOpen: (PlannedMeal) -> Void
    let onMove: (PlannedMeal) -> Void
    let onRemove: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            dayHeader

            ForEach(mealTypes) { mealType in
                mealSlot(for: mealType)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1)
        }
    }

    private var dayHeader: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(Self.dateFormatter.string(from: date))
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HomeyDashboardTheme.softBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func mealSlot(for mealType: MealType) -> some View {
        let mealsForSlot = plannedMeals(mealType)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mealType.systemImageName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(mealType.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    onAdd(mealType)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 32, height: 32)
                        .background(HomeyDashboardTheme.cardBackground, in: Circle())
                        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(mealType.displayName)")
            }

            if mealsForSlot.isEmpty {
                Button {
                    onAdd(mealType)
                } label: {
                    Text("No meal planned")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mealType.displayName), \(Self.accessibilityDateFormatter.string(from: date)), no meal planned. Double tap to add a meal.")
            } else {
                UpcomingMealsPreviewFilledRow(
                    showsMealTypeLabel: false,
                    day: date,
                    mealType: mealType,
                    plannedMeals: mealsForSlot,
                    categories: categories,
                    onOpen: onOpen,
                    onMove: onMove,
                    onRemove: onRemove
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(HomeyDashboardTheme.cardBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

private struct UpcomingMealsPreviewEmptyRow: View {
    let day: Date
    let mealType: MealType
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: mealType.systemImageName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 18)
                    Text(mealType.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: 98, alignment: .leading)

                Spacer()

                Label("Add Meal", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(HomeyDashboardTheme.appBackground.opacity(0.34), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(HomeyDashboardTheme.softBorder.opacity(0.75), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mealType.displayName), \(Self.dayFormatter.string(from: day)), no meal planned. Double tap to add a meal.")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

private struct UpcomingMealsPreviewLoadingRows: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            loadingColumns
                .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.horizontal) {
                loadingColumns
            }
            .scrollIndicators(.hidden)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading upcoming meals")
    }

    private var loadingColumns: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 9) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(HomeyDashboardTheme.warmBeige.opacity(0.38))
                        .frame(height: 48)
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(HomeyDashboardTheme.warmBeige.opacity(0.45))
                                .frame(width: 96, height: 12)
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(HomeyDashboardTheme.warmBeige.opacity(0.34))
                                .frame(height: 58)
                        }
                        .padding(8)
                        .background(HomeyDashboardTheme.cardBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(10)
                .frame(width: 250, alignment: .top)
                .background(HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
}

private struct MealPlannerDayColumn: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let slotTypes: [MealType]
    let plannedMeals: (MealType) -> [PlannedMeal]
    let onSelectDay: () -> Void
    let onAdd: (MealType) -> Void
    let onOpen: (PlannedMeal) -> Void
    let onMove: (PlannedMeal) -> Void
    let onRemove: (PlannedMeal) -> Void
    let onDropMeal: (PlannedMeal, MealType) -> Void
    let draggedMeal: (String) -> PlannedMeal?
    let categories: [CalendarCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelectDay) {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(Self.weekdayFormatter.string(from: date))
                            .font(.caption.weight(.bold))
                        if isToday {
                            Text("Today")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(HomeyDashboardTheme.cardBackground, in: Capsule())
                                .overlay { Capsule().stroke(HomeyDashboardTheme.warmBrown.opacity(0.35), lineWidth: 1) }
                        }
                    }
                    Text(Self.dayFormatter.string(from: date))
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(isSelected || isToday ? HomeyDashboardTheme.warmBrown : HomeyDashboardTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(isSelected || isToday ? HomeyDashboardTheme.selectedSidebarBackground : HomeyDashboardTheme.appBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected || isToday ? HomeyDashboardTheme.warmBrown.opacity(0.42) : Color.clear, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Self.accessibilityDateFormatter.string(from: date)), \(slotTypes.flatMap { plannedMeals($0) }.count) planned meals")

            ForEach(slotTypes) { mealType in
                MealPlannerSlotView(
                    mealType: mealType,
                    plannedMeals: plannedMeals(mealType),
                    categories: categories,
                    onAdd: { onAdd(mealType) },
                    onOpen: onOpen,
                    onMove: onMove,
                    onRemove: onRemove
                )
                .dropDestination(for: String.self) { items, _ in
                    guard let item = items.first,
                          let plannedMeal = draggedMeal(item) else { return false }
                    onDropMeal(plannedMeal, mealType)
                    return true
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(HomeyDashboardTheme.softBorder.opacity(0.82), lineWidth: 1) }
        .shadow(color: HomeyDashboardTheme.shadow.opacity(0.08), radius: 7, x: 0, y: 4)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

private struct MealPlannerSlotView: View {
    let mealType: MealType
    let plannedMeals: [PlannedMeal]
    let categories: [CalendarCategory]
    let onAdd: () -> Void
    let onOpen: (PlannedMeal) -> Void
    let onMove: (PlannedMeal) -> Void
    let onRemove: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mealType.systemImageName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(mealType.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.warmBrown)
                        .frame(width: 32, height: 32)
                        .background(HomeyDashboardTheme.cardBackground, in: Circle())
                        .overlay { Circle().stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(mealType.displayName)")
            }

            if !plannedMeals.isEmpty {
                ForEach(plannedMeals) { plannedMeal in
                    MealPlannerMiniCard(plannedMeal: plannedMeal, categories: categories, onOpen: { onOpen(plannedMeal) }, onMove: { onMove(plannedMeal) }, onRemove: { onRemove(plannedMeal) })
                        .draggable(plannedMeal.id)
                }
            } else {
                Text("No meal planned")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText.opacity(0.72))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(HomeyDashboardTheme.appBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MealPlannerMiniCard: View {
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
            HStack(spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(plannedMeal.meal.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(Self.timeFormatter.string(from: plannedMeal.startsAt))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeyDashboardTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(HomeyDashboardTheme.sageAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(HomeyDashboardTheme.sageAccent.opacity(0.62), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .confirmationDialog(plannedMeal.meal.name, isPresented: $isShowingActions, titleVisibility: .visible) {
            Button("Open Recipe", action: onOpen)
            Button("Open / Reschedule", action: onMove)
            Button("Delete Planned Meal", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) { }
        }
        .accessibilityLabel("\(plannedMeal.meal.name), \(plannedMeal.mealType.displayName), \(Self.timeFormatter.string(from: plannedMeal.startsAt)). Double tap for actions.")
        .accessibilityAction(named: "Open Recipe", onOpen)
        .accessibilityAction(named: "Open or Reschedule", onMove)
        .accessibilityAction(named: "Delete Planned Meal", onRemove)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = plannedMeal.signedPhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    ProgressView().controlSize(.small)
                case .failure:
                    fallbackThumbnail
                @unknown default:
                    fallbackThumbnail
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            fallbackThumbnail
        }
    }

    private var fallbackThumbnail: some View {
        Image(systemName: "fork.knife")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(HomeyDashboardTheme.warmBrown)
            .frame(width: 40, height: 40)
            .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var accentColor: Color {
        CalendarEventColorResolver.color(for: plannedMeal.calendarEvent, categories: categories, fallback: HomeyDashboardTheme.warmBrown)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MealPlannerListRow: View {
    let plannedMeal: PlannedMeal
    let categories: [CalendarCategory]
    let onOpen: () -> Void
    let onMove: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plannedMeal.mealType.systemImageName)
                .foregroundStyle(accentColor)
                .frame(width: 44, height: 44)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(plannedMeal.meal.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                Text(Self.dayDateFormatter.string(from: plannedMeal.startsAt))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeyDashboardTheme.primaryText.opacity(0.82))
                Text("\(plannedMeal.mealType.displayName) · \(Self.timeFormatter.string(from: plannedMeal.startsAt))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
            }
            Spacer()
            Button("Open", action: onOpen)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .buttonStyle(.plain)
            Menu {
                Button("Move/Reschedule", action: onMove)
                Button("Remove from Meal Plan", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Planned meal actions")
        }
        .padding(16)
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(accentColor.opacity(0.30), lineWidth: 1) }
    }

    private var accentColor: Color {
        CalendarEventColorResolver.color(for: plannedMeal.calendarEvent, categories: categories, fallback: HomeyDashboardTheme.warmBrown)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter
    }()
}

private struct MealPlannerPickerView: View {
    let title: String
    let meals: [Meal]
    let favoriteMeals: [Meal]
    let collections: [MealCollection]
    let preselectedMealType: MealType
    let onCancel: () -> Void
    let onSelectMeal: (Meal) -> Void

    @State private var searchText = ""
    @State private var selectedMealType: MealType?

    private var filteredMeals: [Meal] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return meals.filter { meal in
            if let selectedMealType, !meal.mealTypes.contains(selectedMealType) { return false }
            guard !normalizedSearch.isEmpty else { return true }
            return meal.name.lowercased().contains(normalizedSearch)
                || meal.tags.contains { $0.lowercased().contains(normalizedSearch) }
                || (meal.cuisine?.lowercased().contains(normalizedSearch) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            TextField("Search recipes", text: $searchText)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Picker("Meal Type", selection: $selectedMealType) {
                            Text("All").tag(MealType?.none)
                            ForEach(MealType.allCases) { mealType in
                                Text(mealType.displayName).tag(Optional(mealType))
                            }
                        }
                        .pickerStyle(.segmented)

                        if !favoriteMeals.isEmpty {
                            mealSection(title: "Favorites", meals: favoriteMeals.filter { favorite in filteredMeals.contains(where: { $0.id == favorite.id }) })
                        }

                        mealSection(title: "Recently Updated", meals: filteredMeals.sorted { $0.updatedAt > $1.updatedAt })
                    }
                    .padding(24)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .onAppear {
            selectedMealType = preselectedMealType
        }
    }

    private func mealSection(title: String, meals: [Meal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomeyDashboardTheme.primaryText)
            if meals.isEmpty {
                MealPlannerMessageCard(title: "No Recipes", message: "No recipes match this slot yet.", systemImage: "fork.knife")
            } else {
                ForEach(meals) { meal in
                    Button { onSelectMeal(meal) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: meal.mealTypes.first?.systemImageName ?? "fork.knife")
                                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                                .frame(width: 44, height: 44)
                                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(HomeyDashboardTheme.primaryText)
                                Text(totalTimeText(for: meal))
                                    .font(.subheadline)
                                    .foregroundStyle(HomeyDashboardTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(HomeyDashboardTheme.secondaryText)
                        }
                        .padding(14)
                        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func totalTimeText(for meal: Meal) -> String {
        let total = (meal.prepTimeMinutes ?? 0) + (meal.cookTimeMinutes ?? 0)
        return total > 0 ? "\(total) min" : "Time not set"
    }
}

private struct MealPlannerConfirmationView: View {
    let selection: MealPlannerPendingSelection
    let onAdd: (Decimal?, String?) -> Void
    let onCancel: () -> Void

    @State private var servingsText = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    MealPlannerMessageCard(
                        title: selection.meal.name,
                        message: "\(Self.dateFormatter.string(from: selection.date)) · \(selection.mealType.displayName) · \(defaultTimeText(for: selection.mealType))",
                        systemImage: selection.mealType.systemImageName
                    )
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Planned servings", text: $servingsText)
                            .keyboardType(.decimalPad)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        TextField("Meal notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(14)
                            .frame(minHeight: 110, alignment: .topLeading)
                            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button("Cancel", action: onCancel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .buttonStyle(.plain)
                        Button("Add Meal") {
                            onAdd(Decimal(string: servingsText.trimmingCharacters(in: .whitespacesAndNewlines)), notes)
                        }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .frame(maxWidth: 620)
            }
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func defaultTimeText(for mealType: MealType) -> String {
        switch mealType {
        case .breakfast: "8:00 AM"
        case .lunch: "12:00 PM"
        case .dinner: "6:00 PM"
        case .snack: "3:00 PM"
        case .dessert: "7:00 PM"
        case .drink: "10:00 AM"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }()
}

private struct MealPlannerMoveView: View {
    let plannedMeal: PlannedMeal
    let weekDays: [Date]
    @State var selectedDate: Date
    @State var selectedMealType: MealType
    let onCancel: () -> Void
    let onMove: (Date, MealType) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyDashboardTheme.appBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text(plannedMeal.meal.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HomeyDashboardTheme.primaryText)
                    Picker("Day", selection: $selectedDate) {
                        ForEach(weekDays, id: \.self) { day in
                            Text(Self.dayFormatter.string(from: day)).tag(day)
                        }
                    }
                    .pickerStyle(.wheel)
                    Picker("Meal Type", selection: $selectedMealType) {
                        ForEach([MealType.breakfast, .lunch, .dinner, .snack, .dessert, .drink]) { mealType in
                            Text(mealType.displayName).tag(mealType)
                        }
                    }
                    .pickerStyle(.segmented)
                    Spacer()
                    HStack(spacing: 12) {
                        Button("Cancel", action: onCancel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(HomeyDashboardTheme.warmBrown)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .buttonStyle(.plain)
                        Button("Move Meal") { onMove(selectedDate, selectedMealType) }
                            .buttonStyle(DashboardPrimaryButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .frame(maxWidth: 620)
            }
            .navigationTitle("Move Meal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMM d")
        return formatter
    }()
}

private struct MealPlannerLoadingGrid: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
            ForEach(0..<7, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(HomeyDashboardTheme.warmBeige.opacity(0.28))
                    .frame(height: 420)
                    .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("Loading meal planner")
    }
}

private struct MealPlannerMessageCard: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(HomeyDashboardTheme.warmBrown)
                .frame(width: 44, height: 44)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
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
        .background(HomeyDashboardTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(HomeyDashboardTheme.softBorder, lineWidth: 1) }
    }
}

private struct MealPlannerSlot: Identifiable {
    let id = UUID()
    let date: Date
    let mealType: MealType
}

private struct MealPlannerPendingSelection: Identifiable {
    let id = UUID()
    let meal: Meal
    let date: Date
    let mealType: MealType
}

private struct MealPlannerMoveTarget: Identifiable {
    let id = UUID()
    let plannedMeal: PlannedMeal
    let date: Date
    let mealType: MealType
}
