import PostgREST
import SwiftUI

private enum LeftoverWizardStep {
    case selection, destination, conflict, review
}

struct AssignLeftoversView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let home: HomeSummary
    let sourceDate: Date
    @ObservedObject var model: MealsViewModel
    let onSaved: (Date) -> Void

    @State private var step: LeftoverWizardStep = .selection
    @State private var sourceMeals: [PlannedMeal] = []
    @State private var selectedEventIDs: Set<UUID> = []
    @State private var destinationMeals: [PlannedMeal] = []
    @State private var destinationDate: Date
    @State private var conflictMode: LeftoverConflictMode?
    @State private var didExplicitlyChooseConflictMode = false
    @State private var idempotencyKey: UUID?
    @State private var isLoadingSource = false
    @State private var isCheckingDestination = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let visibleTypes: [MealType] = [.breakfast, .lunch, .dinner]
    private var calendar: Calendar { MealsViewModel.calendar(home) }
    private var sourceDay: Date { calendar.startOfDay(for: sourceDate) }
    private var minimumDestination: Date {
        calendar.date(byAdding: .day, value: 1, to: sourceDay) ?? sourceDay.addingTimeInterval(86_400)
    }
    private var selectedMeals: [PlannedMeal] {
        sourceMeals.filter { selectedEventIDs.contains($0.eventId) }
    }
    private var selectedMealTypes: Set<MealType> { Set(selectedMeals.map(\.mealType)) }
    private var conflictingMeals: [PlannedMeal] {
        destinationMeals.filter { selectedMealTypes.contains($0.mealType) }
    }
    private var conflictingTypes: [MealType] {
        visibleTypes.filter { type in conflictingMeals.contains { $0.mealType == type } }
    }
    private var hasConflicts: Bool { !conflictingMeals.isEmpty }

    init(
        home: HomeSummary,
        sourceDate: Date,
        model: MealsViewModel,
        onSaved: @escaping (Date) -> Void
    ) {
        self.home = home
        self.sourceDate = sourceDate
        self.model = model
        self.onSaved = onSaved
        let calendar = MealsViewModel.calendar(home)
        let sourceDay = calendar.startOfDay(for: sourceDate)
        _destinationDate = State(
            initialValue: calendar.date(byAdding: .day, value: 1, to: sourceDay)
                ?? sourceDay.addingTimeInterval(86_400)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomeyBackground()
                VStack(spacing: 0) {
                    progressHeader
                    ScrollView {
                        content
                            .padding(16)
                            .padding(.bottom, 12)
                    }
                    bottomBar
                }
            }
            .navigationTitle("Leftovers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { await loadSourceMeals() }
            .onChange(of: destinationDate) { _, _ in destinationDidChange() }
            .onChange(of: session.activeHome?.id) { _, homeID in
                if homeID != home.id, !isSaving { dismiss() }
            }
        }
        .presentationDetents([.large])
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(progressPosition) of \(progressTotal)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeyColors.secondaryText)
            ProgressView(value: Double(progressPosition), total: Double(progressTotal))
                .tint(HomeyColors.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white.opacity(0.78))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .selection: selectionStep
        case .destination: destinationStep
        case .conflict: conflictStep
        case .review: reviewStep
        }
    }

    private var selectionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            intro("Leftovers", "Choose the meals you want to save for another day.")
            Text(dateLabel(sourceDay))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeyColors.secondaryText)

            if isLoadingSource {
                loadingCard("Loading planned meals…")
            } else if sourceMeals.isEmpty {
                emptySourceCard
            } else {
                ForEach(visibleTypes) { type in
                    let meals = sourceMeals.filter { $0.mealType == type }
                    if !meals.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle(type.title)
                            ForEach(meals) { meal in selectionCard(meal) }
                        }
                    }
                }
            }
            if let errorMessage { HomeyErrorView(message: errorMessage) }
        }
    }

    private var destinationStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            intro("When should we have these?", "Choose a future day for the selected leftovers.")
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(
                    "Leftovers date",
                    selection: $destinationDate,
                    in: minimumDestination...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.timeZone, calendar.timeZone)
            }
            .homeyCard()
            selectedMealsSummary
            if let errorMessage { HomeyErrorView(message: errorMessage) }
        }
    }

    private var conflictStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            intro(
                "Meals already planned",
                "Some selected meal times already have meals planned for \(shortDateLabel(destinationDate)). What would you like to do?"
            )

            ForEach(conflictingTypes) { type in
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(type.title)
                    conflictList("Currently planned", meals: conflictingMeals.filter { $0.mealType == type })
                    Divider()
                    conflictList("Leftovers", meals: selectedMeals.filter { $0.mealType == type })
                }
                .homeyCard()
            }

            VStack(spacing: 12) {
                conflictChoice(
                    .add,
                    description: "Keep the meals already planned and add the selected leftovers alongside them."
                )
                conflictChoice(
                    .replace,
                    description: "Replace only the conflicting meal times. Unrelated meals on this day stay unchanged."
                )
            }
            if let errorMessage { HomeyErrorView(message: errorMessage) }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            intro("Review leftovers", "Confirm the meals and destination before saving.")
            reviewSection("Leftovers") {
                ForEach(selectedMeals) { meal in
                    Label(meal.meal.name, systemImage: meal.mealType.symbol)
                        .font(.subheadline.weight(.medium))
                }
            }
            reviewSection("Move to") {
                Label(dateLabel(destinationDate), systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
            }
            if hasConflicts, let conflictMode {
                reviewSection("Conflict behavior") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(conflictMode.title).font(.subheadline.weight(.semibold))
                        Text(conflictMode == .add
                            ? "Existing meals remain and leftovers are added."
                            : "Only conflicting meal times are replaced; unrelated meals remain.")
                            .font(.caption).foregroundStyle(HomeyColors.secondaryText)
                    }
                }
            }
            if let errorMessage { HomeyErrorView(message: errorMessage) }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if sourceMeals.isEmpty, !isLoadingSource {
            Button("Done") { dismiss() }
                .buttonStyle(HomeyButtonStyle())
                .padding(16)
                .background(.white.opacity(0.88))
        } else {
            HStack(spacing: 12) {
                if step != .selection {
                    Button("Back") { goBack() }
                        .buttonStyle(HomeyButtonStyle(secondary: true))
                        .disabled(isSaving || isCheckingDestination)
                }
                Button { primaryAction() } label: {
                    HStack {
                        if isSaving || isCheckingDestination { ProgressView().tint(.white) }
                        Text(primaryButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(HomeyButtonStyle())
                .disabled(!canContinue || isSaving || isCheckingDestination)
            }
            .padding(16)
            .background(.white.opacity(0.88))
        }
    }

    private var primaryButtonTitle: String {
        if isSaving { return "Adding leftovers..." }
        if isCheckingDestination { return "Checking meals..." }
        if step == .review { return idempotencyKey == nil ? "Save Leftovers" : "Retry Save" }
        return "Continue"
    }

    private var canContinue: Bool {
        switch step {
        case .selection: !selectedEventIDs.isEmpty
        case .destination: destinationDate >= minimumDestination
        case .conflict: conflictMode != nil
        case .review: !selectedEventIDs.isEmpty && (!hasConflicts || conflictMode != nil)
        }
    }

    private var progressTotal: Int { hasConflicts ? 4 : 3 }
    private var progressPosition: Int {
        switch step {
        case .selection: 1
        case .destination: 2
        case .conflict: 3
        case .review: hasConflicts ? 4 : 3
        }
    }

    private func selectionCard(_ meal: PlannedMeal) -> some View {
        let selected = selectedEventIDs.contains(meal.eventId)
        return Button { toggle(meal) } label: {
            HStack(spacing: 13) {
                HomeRecipeThumbnail(path: meal.meal.primaryPhotoPath)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.meal.name)
                        .font(.headline).foregroundStyle(HomeyColors.text).lineLimit(2)
                    Text(meal.mealType.title)
                        .font(.caption).foregroundStyle(HomeyColors.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected ? HomeyColors.primary : HomeyColors.secondaryText)
            }
            .padding(15)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(selected ? HomeyColors.primary.opacity(0.55) : HomeyColors.border.opacity(0.25), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(meal.meal.name), \(meal.mealType.title)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var selectedMealsSummary: some View {
        reviewSection("Selected meals") {
            ForEach(selectedMeals) { meal in
                Text("\(meal.mealType.title): \(meal.meal.name)")
                    .font(.subheadline)
            }
        }
    }

    private func conflictList(_ title: String, meals: [PlannedMeal]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(HomeyColors.secondaryText)
            ForEach(meals) { meal in Text(meal.meal.name).font(.subheadline.weight(.medium)) }
        }
    }

    private func conflictChoice(_ mode: LeftoverConflictMode, description: String) -> some View {
        Button {
            if conflictMode != mode {
                conflictMode = mode
                invalidateSaveAttempt()
            }
            didExplicitlyChooseConflictMode = true
        } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: conflictMode == mode ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(HomeyColors.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title.uppercased()).font(.headline).foregroundStyle(HomeyColors.text)
                    Text(description).font(.caption).foregroundStyle(HomeyColors.secondaryText)
                }
                Spacer()
            }
            .padding(17)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(conflictMode == mode ? HomeyColors.primary.opacity(0.55) : HomeyColors.border.opacity(0.25), lineWidth: conflictMode == mode ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func reviewSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeyCard()
    }

    private var emptySourceCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 42)).foregroundStyle(HomeyColors.primary)
            Text("No meals planned").font(HomeyTypography.title)
            Text("There aren't any meals on this day to use as leftovers.")
                .font(.subheadline).foregroundStyle(HomeyColors.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).homeyCard()
    }

    private func loadingCard(_ message: String) -> some View {
        HStack(spacing: 10) { ProgressView(); Text(message) }
            .foregroundStyle(HomeyColors.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 130)
            .homeyCard()
    }

    private func intro(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(HomeyTypography.title).foregroundStyle(HomeyColors.text)
            Text(subtitle).foregroundStyle(HomeyColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
    }

    private func toggle(_ meal: PlannedMeal) {
        if selectedEventIDs.contains(meal.eventId) { selectedEventIDs.remove(meal.eventId) }
        else { selectedEventIDs.insert(meal.eventId) }
        destinationMeals = []
        conflictMode = nil
        didExplicitlyChooseConflictMode = false
        invalidateSaveAttempt()
    }

    private func destinationDidChange() {
        destinationMeals = []
        conflictMode = nil
        didExplicitlyChooseConflictMode = false
        invalidateSaveAttempt()
    }

    private func invalidateSaveAttempt() {
        idempotencyKey = nil
        errorMessage = nil
    }

    private func primaryAction() {
        switch step {
        case .selection:
            step = .destination
        case .destination:
            Task { await resolveConflicts() }
        case .conflict:
            guard conflictMode != nil else { return }
            step = .review
        case .review:
            Task { await save() }
        }
    }

    private func goBack() {
        guard !isSaving else { return }
        errorMessage = nil
        switch step {
        case .selection: break
        case .destination: step = .selection
        case .conflict: step = .destination
        case .review: step = hasConflicts ? .conflict : .destination
        }
    }

    private func loadSourceMeals() async {
        isLoadingSource = true
        errorMessage = nil
        defer { isLoadingSource = false }
        do {
            let loaded = try await model.plannedMealsForDay(home: home, date: sourceDay)
            guard session.activeHome?.id == home.id else { dismiss(); return }
            sourceMeals = loaded.filter { visibleTypes.contains($0.mealType) }
            selectedEventIDs.formIntersection(Set(sourceMeals.map(\.eventId)))
        } catch {
            errorMessage = "Homey couldn't load the meals planned for this day."
        }
    }

    private func resolveConflicts() async {
        guard destinationDate >= minimumDestination else {
            errorMessage = "Choose a date after the source Meal Planner day."
            return
        }
        isCheckingDestination = true
        errorMessage = nil
        defer { isCheckingDestination = false }
        do {
            destinationMeals = try await model.plannedMealsForDay(home: home, date: destinationDate)
            guard session.activeHome?.id == home.id else { dismiss(); return }
            if hasConflicts {
                if !didExplicitlyChooseConflictMode { conflictMode = nil }
                step = .conflict
            } else {
                if conflictMode != nil, conflictMode != .add { invalidateSaveAttempt() }
                conflictMode = .add
                didExplicitlyChooseConflictMode = false
                step = .review
            }
        } catch {
            errorMessage = "Homey couldn't check the meals already planned for that date. Please try again."
        }
    }

    private func save() async {
        guard !isSaving, session.activeHome?.id == home.id else {
            errorMessage = "The active Home changed. Reopen Leftovers and try again."
            return
        }
        guard !selectedMeals.isEmpty else {
            errorMessage = "Choose at least one meal."
            return
        }
        let mode: LeftoverConflictMode = hasConflicts ? (conflictMode ?? .add) : .add
        let key = idempotencyKey ?? UUID()
        idempotencyKey = key
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let response = try await model.assignLeftovers(
                home: home,
                sourceCalendarEventIDs: selectedMeals.map(\.eventId),
                destinationDate: destinationDate,
                conflictMode: mode,
                idempotencyKey: key
            )
            guard response.createdCount == selectedMeals.count else {
                throw MealsError.message("Homey received an unexpected response. Retry to safely confirm the same request.")
            }
            await model.refreshPlan(home: home, containing: destinationDate)
            NotificationCenter.default.post(name: Notification.Name("homeyCalendarEventsDidChange"), object: home.id)
            onSaved(calendar.startOfDay(for: destinationDate))
            dismiss()
        } catch {
            errorMessage = saveErrorMessage(error)
        }
    }

    private func saveErrorMessage(_ error: Error) -> String {
        if let postgrest = error as? PostgrestError, !postgrest.message.isEmpty {
            return postgrest.message
        }
        return "Homey couldn't save these leftovers. Check your connection and tap Retry Save; the same safe request will be reused."
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter.string(from: date)
    }
}
