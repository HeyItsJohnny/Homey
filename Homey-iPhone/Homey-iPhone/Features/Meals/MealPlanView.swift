import SwiftUI

struct MealPlanView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @Binding var selectedDate: Date
    @State private var pickerSlot: MealPlanSlot?
    @State private var showsCalendar = false
    @State private var transitionDirection = 1
    private let visibleTypes: [MealType] = [.breakfast, .lunch, .dinner]

    private var calendar: Calendar { MealsViewModel.calendar(home) }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var selectedDay: Date { calendar.startOfDay(for: selectedDate) }
    private var isToday: Bool { calendar.isDate(selectedDay, inSameDayAs: today) }

    var body: some View {
        VStack(spacing: 12) {
            dateNavigation
            ScrollView {
                ZStack {
                    LazyVStack(spacing: 16) {
                        ForEach(visibleTypes) { type in
                            MealPlanSlotCard(type: type, items: plannedMeals(for: type),
                                add: { pickerSlot = MealPlanSlot(day: selectedDay, type: type) },
                                change: { item in pickerSlot = MealPlanSlot(day: selectedDay, type: type, replacing: item) },
                                moveDates: moveDates,
                                move: { item, date in Task { await move(item, to: date) } },
                                remove: { item in Task { await model.remove(item, home: home, containing: selectedDay) } },
                                detail: { meal in RecipeDetailView(meal: meal, home: home, model: model) })
                        }
                    }
                    .id(dayIdentifier)
                    .transition(.asymmetric(
                        insertion: .move(edge: transitionDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: transitionDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                    ))
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    guard abs(value.translation.width) > 64,
                          abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    changeDay(by: value.translation.width < 0 ? 1 : -1)
                }
            )
        }
        .sheet(isPresented: $showsCalendar) {
            MealPlanDatePicker(selectedDate: $selectedDate, calendar: calendar)
                .presentationDetents([.medium])
        }
        .sheet(item: $pickerSlot) { slot in
            RecipePickerView(recipes: model.homeRecipes, favorites: model.favoriteIDs,
                mealTypeFilter: slot.type, isLoading: model.isLoading) { meal in
                if let replacedMeal = slot.replacing {
                    return await model.replace(replacedMeal, with: meal, type: slot.type, day: slot.day, home: home)
                }
                return await model.schedule(meal, type: slot.type, day: slot.day, home: home)
            }
        }
        .task(id: dayIdentifier) { await model.refreshPlan(home: home, containing: selectedDay) }
        .onChange(of: home.id) {
            selectedDate = today
            Task { await model.refreshPlan(home: home, containing: today) }
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 8) {
            dayArrow("chevron.left", accessibilityLabel: "Previous day") { changeDay(by: -1) }
            Button { showsCalendar = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(dateLabel).lineLimit(1).minimumScaleFactor(0.75)
                    Image(systemName: "chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.text)
                .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 46)
                .background(HomeyColors.field.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain).accessibilityLabel("Choose date, \(dateLabel)")
            dayArrow("chevron.right", accessibilityLabel: "Next day") { changeDay(by: 1) }
            Button("Today") { goToToday() }
                .font(.subheadline.weight(.semibold)).foregroundStyle(HomeyColors.recipeGreenAccent)
                .padding(.horizontal, 10).frame(minHeight: 46)
                .background(HomeyColors.recipeGreenAccent.opacity(isToday ? 0.05 : 0.11), in: RoundedRectangle(cornerRadius: 16))
                .opacity(isToday ? 0.55 : 1).disabled(isToday)
        }.padding(.horizontal, 16).padding(.top, 2)
    }

    private func dayArrow(_ symbol: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.headline).foregroundStyle(HomeyColors.text)
                .frame(width: 44, height: 46).background(HomeyColors.field.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel(accessibilityLabel)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter.string(from: selectedDay)
    }
    private var dayIdentifier: String {
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDay)
        return "\(home.id)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
    private var moveDates: [Date] {
        let week = MealsViewModel.week(containing: selectedDay, home: home)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }
    private func plannedMeals(for type: MealType) -> [PlannedMeal] {
        model.planned.filter {
            calendar.isDate($0.startsAt, inSameDayAs: selectedDay) && $0.mealType == type
        }.sorted {
            if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
            return $0.id < $1.id
        }
    }
    private func changeDay(by days: Int) {
        guard let date = calendar.date(byAdding: .day, value: days, to: selectedDay) else { return }
        transitionDirection = days >= 0 ? 1 : -1
        withAnimation(.easeInOut(duration: 0.22)) { selectedDate = date }
    }
    private func goToToday() {
        transitionDirection = today >= selectedDay ? 1 : -1
        withAnimation(.easeInOut(duration: 0.22)) { selectedDate = today }
    }
    private func move(_ item: PlannedMeal, to date: Date) async {
        await model.remove(item, home: home, containing: selectedDay)
        await model.schedule(item.meal, type: item.mealType, day: date, home: home)
        selectedDate = date
    }
}

private struct MealPlanSlot: Identifiable {
    let day: Date
    let type: MealType
    var replacing: PlannedMeal? = nil
    var id: String { "\(day.timeIntervalSinceReferenceDate)-\(type.rawValue)" }
}

private struct MealPlanSlotCard<Detail: View>: View {
    let type: MealType
    let items: [PlannedMeal]
    let add: () -> Void
    let change: (PlannedMeal) -> Void
    let moveDates: [Date]
    let move: (PlannedMeal, Date) -> Void
    let remove: (PlannedMeal) -> Void
    @ViewBuilder let detail: (HomeyMeal) -> Detail

    private var accent: Color {
        switch type {
        case .breakfast: HomeyColors.recipeOrangeAccent
        case .lunch: HomeyColors.recipeGreenAccent
        case .dinner: HomeyColors.primary
        default: HomeyColors.secondaryText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RecipeDetailIcon(symbol: type.symbol, color: accent)
                Text(type.title).font(HomeyTypography.headline)
                Spacer()
                Button(action: add) { Label("Add Recipe", systemImage: "plus").font(.subheadline.weight(.semibold)) }
                    .buttonStyle(.plain).foregroundStyle(HomeyColors.recipeGreenAccent)
            }
            if !items.isEmpty {
                Divider().overlay(HomeyColors.border.opacity(0.2))
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(HomeyColors.border.opacity(0.16))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        NavigationLink(destination: detail(item.meal)) {
                            HStack(alignment: .top, spacing: 12) {
                                HomeRecipeThumbnail(path: item.meal.primaryPhotoPath).frame(width: 94, height: 94)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.meal.name).font(.headline).foregroundStyle(HomeyColors.text).lineLimit(2)
                                    RecipeBadgeFlow(spacing: 7) {
                                        let total = (item.meal.prepTimeMinutes ?? 0) + (item.meal.cookTimeMinutes ?? 0)
                                        if total > 0 { Label("\(total) min", systemImage: "clock") }
                                        if let servings = item.meal.servings, servings > 0 {
                                            Label("\(servings.formatted()) servings", systemImage: "person.2")
                                        }
                                    }.font(.caption).foregroundStyle(HomeyColors.secondaryText)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Menu {
                            NavigationLink(destination: detail(item.meal)) { Label("View Recipe", systemImage: "book") }
                            Button("Change Recipe", systemImage: "arrow.triangle.2.circlepath") { change(item) }
                            Menu("Move / Reschedule", systemImage: "calendar") {
                                ForEach(moveDates, id: \.self) { date in
                                    Button(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) { move(item, date) }
                                }
                            }
                            Divider()
                            Button("Remove from Meal Plan", systemImage: "trash", role: .destructive) { remove(item) }
                        } label: {
                            Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(HomeyColors.secondaryText)
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("Actions for \(item.meal.name)")
                        }
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).recipeDetailCard()
    }
}

private struct MealPlanDatePicker: View {
    @Binding var selectedDate: Date
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Choose a day", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical).padding().environment(\.timeZone, calendar.timeZone)
                .onChange(of: selectedDate) { dismiss() }
                .navigationTitle("Select Date").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct AssignLeftoversView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case move, replace
        var id: String { rawValue }
        var title: String { self == .move ? "Add meals" : "Replace meals" }
        var subtitle: String {
            self == .move
                ? "Add them to the Leftovers Day, keep existing plans, and leave the original day unchanged."
                : "Replace that meal type on the Leftovers Day and leave the original day unchanged."
        }
    }

    let home: HomeSummary
    let sourceDate: Date
    @ObservedObject var model: MealsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sourceMeals: [PlannedMeal] = []
    @State private var selectedTypes: Set<MealType> = []
    @State private var destinationDate: Date
    @State private var mode: Mode = .move
    @State private var showDatePicker = false
    @State private var isProcessing = false
    @State private var replaceConflicts: Set<MealType> = []
    @State private var showReplaceConfirmation = false
    @State private var errorMessage: String?

    private let mealTypes: [MealType] = [.breakfast, .lunch, .dinner]
    private var calendar: Calendar { MealsViewModel.calendar(home) }
    private var sourceDay: Date { calendar.startOfDay(for: sourceDate) }
    private var minimumDestination: Date {
        calendar.date(byAdding: .day, value: 1, to: sourceDay) ?? sourceDay.addingTimeInterval(86_400)
    }
    private var canAssign: Bool {
        !selectedTypes.isEmpty && calendar.startOfDay(for: destinationDate) >= minimumDestination && !isProcessing
    }

    init(home: HomeSummary, sourceDate: Date, model: MealsViewModel) {
        self.home = home
        self.sourceDate = sourceDate
        self.model = model
        let calendar = MealsViewModel.calendar(home)
        let sourceDay = calendar.startOfDay(for: sourceDate)
        _destinationDate = State(initialValue: calendar.date(byAdding: .day, value: 1, to: sourceDay) ?? sourceDay.addingTimeInterval(86_400))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Choose which meals you'd like to carry over.")
                        .font(.subheadline).foregroundStyle(HomeyColors.secondaryText)

                    sectionTitle("Meals")
                    VStack(spacing: 0) {
                        ForEach(Array(mealTypes.enumerated()), id: \.element.id) { index, type in
                            if index > 0 { Divider().padding(.leading, 50) }
                            mealTypeRow(type)
                        }
                    }
                    .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 20))

                    sectionTitle("Leftovers Day")
                    Button { showDatePicker = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar").font(.headline).foregroundStyle(HomeyColors.recipeGreenAccent)
                            Text(destinationLabel).font(.headline).foregroundStyle(HomeyColors.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
                        }
                        .padding(18).background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)

                    sectionTitle("When leftovers arrive")
                    VStack(spacing: 0) {
                        ForEach(Array(Mode.allCases.enumerated()), id: \.element.id) { index, option in
                            if index > 0 { Divider().padding(.leading, 50) }
                            modeRow(option)
                        }
                    }
                    .background(HomeyColors.recipeCardBackground, in: RoundedRectangle(cornerRadius: 20))

                    if let errorMessage { HomeyErrorView(message: errorMessage) }

                    Button { Task { await prepareAssignment() } } label: {
                        HStack {
                            if isProcessing { ProgressView().tint(.white) }
                            Text(isProcessing ? "Assigning…" : "Assign Leftovers")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(HomeyColors.recipeGreenAccent, in: RoundedRectangle(cornerRadius: HomeyCornerRadius.field))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAssign)
                    .opacity(canAssign ? 1 : 0.5)
                }
                .padding(20).padding(.bottom, 24)
            }
            .background(HomeyColors.recipeBackground.ignoresSafeArea())
            .navigationTitle("Assign Leftovers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isProcessing) } }
            .task { await loadSourceMeals() }
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker("Leftovers Day", selection: $destinationDate, in: minimumDestination..., displayedComponents: .date)
                        .datePickerStyle(.graphical).padding().environment(\.timeZone, calendar.timeZone)
                        .navigationTitle("Leftovers Day").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDatePicker = false } } }
                }
                .presentationDetents([.medium])
            }
            .alert("Replace planned meals?", isPresented: $showReplaceConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Replace Meals", role: .destructive) { Task { await performAssignment() } }
            } message: {
                Text(replaceConfirmationMessage)
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isProcessing)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(HomeyColors.secondaryText)
    }

    private func mealTypeRow(_ type: MealType) -> some View {
        let count = sourceMeals.count { $0.mealType == type }
        let available = count > 0
        return Button {
            if selectedTypes.contains(type) { selectedTypes.remove(type) } else { selectedTypes.insert(type) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selectedTypes.contains(type) ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundStyle(selectedTypes.contains(type) ? HomeyColors.recipeGreenAccent : HomeyColors.secondaryText)
                Image(systemName: type.symbol).foregroundStyle(HomeyColors.recipeOrangeAccent).frame(width: 20)
                Text(type.title).font(.headline).foregroundStyle(HomeyColors.text)
                Spacer()
                Text(available ? "\(count) meal\(count == 1 ? "" : "s")" : "Empty")
                    .font(.caption).foregroundStyle(HomeyColors.secondaryText)
            }.padding(16).contentShape(Rectangle()).opacity(available ? 1 : 0.45)
        }.buttonStyle(.plain).disabled(!available || isProcessing)
    }

    private func modeRow(_ option: Mode) -> some View {
        Button { mode = option } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(HomeyColors.recipeGreenAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(.headline).foregroundStyle(HomeyColors.text)
                    Text(option.subtitle).font(.caption).foregroundStyle(HomeyColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }.padding(16).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(isProcessing)
    }

    private var destinationLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter.string(from: destinationDate)
    }

    private func loadSourceMeals() async {
        do {
            sourceMeals = try await model.plannedMealsForDay(home: home, date: sourceDay)
            let availableTypes = Set(sourceMeals.map(\.mealType))
            selectedTypes.formIntersection(availableTypes)
        }
        catch { errorMessage = "Homey couldn't load this day's meals." }
    }

    private func prepareAssignment() async {
        guard canAssign else { return }
        errorMessage = nil
        if mode == .replace {
            do {
                let destinationMeals = try await model.plannedMealsForDay(home: home, date: destinationDate)
                replaceConflicts = Set(destinationMeals.filter { selectedTypes.contains($0.mealType) }.map(\.mealType))
                if !replaceConflicts.isEmpty {
                    showReplaceConfirmation = true
                    return
                }
            } catch {
                errorMessage = "Homey couldn't check the Leftovers Day. Please try again."
                return
            }
        }
        await performAssignment()
    }

    private func performAssignment() async {
        guard canAssign else { return }
        isProcessing = true
        errorMessage = nil
        do {
            try await model.assignLeftovers(
                home: home,
                sourceDate: sourceDay,
                destinationDate: destinationDate,
                mealTypes: selectedTypes,
                replaceDestination: mode == .replace
            )
            isProcessing = false
            dismiss()
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
            await loadSourceMeals()
        }
    }

    private var replaceConfirmationMessage: String {
        let names = mealTypes.filter { replaceConflicts.contains($0) }.map(\.title)
        let list = names.formatted(.list(type: .and))
        return "\(destinationLabel) already has meals planned for \(list). Replacing will remove those meals and add the selected leftovers in their place."
    }
}
