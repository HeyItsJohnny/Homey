import SwiftUI

struct MealPlanView: View {
    let home: HomeSummary
    @ObservedObject var model: MealsViewModel
    @State private var selectedDate: Date
    @State private var pickerSlot: MealPlanSlot?
    @State private var showsCalendar = false
    @State private var transitionDirection = 1
    private let visibleTypes: [MealType] = [.breakfast, .lunch, .dinner]

    private var calendar: Calendar { MealsViewModel.calendar(home) }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var selectedDay: Date { calendar.startOfDay(for: selectedDate) }
    private var isToday: Bool { calendar.isDate(selectedDay, inSameDayAs: today) }

    init(home: HomeSummary, model: MealsViewModel) {
        self.home = home
        self.model = model
        let calendar = MealsViewModel.calendar(home)
        _selectedDate = State(initialValue: calendar.startOfDay(for: Date()))
    }

    var body: some View {
        VStack(spacing: 12) {
            dateNavigation
            ScrollView {
                ZStack {
                    LazyVStack(spacing: 16) {
                        ForEach(visibleTypes) { type in
                            MealPlanSlotCard(type: type, item: plannedMeal(for: type),
                                add: { pickerSlot = MealPlanSlot(day: selectedDay, type: type) },
                                change: { pickerSlot = MealPlanSlot(day: selectedDay, type: type) },
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
                await model.schedule(meal, type: slot.type, day: slot.day, home: home)
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
    private func plannedMeal(for type: MealType) -> PlannedMeal? {
        model.planned.first { calendar.isDate($0.startsAt, inSameDayAs: selectedDay) && $0.mealType == type }
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
    var id: String { "\(day.timeIntervalSinceReferenceDate)-\(type.rawValue)" }
}

private struct MealPlanSlotCard<Detail: View>: View {
    let type: MealType
    let item: PlannedMeal?
    let add: () -> Void
    let change: () -> Void
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
                Text(type.title).font(HomeyTypography.headline).frame(maxWidth: .infinity, alignment: .leading)
                if item == nil {
                    Button(action: add) { Label("Add Recipe", systemImage: "plus").font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(HomeyColors.recipeGreenAccent)
                }
            }
            if let item {
                Divider().overlay(HomeyColors.border.opacity(0.2))
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
                        Button("Change Recipe", systemImage: "arrow.triangle.2.circlepath", action: change)
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
