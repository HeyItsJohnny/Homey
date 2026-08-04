import Combine
import Foundation

@MainActor
final class MealPlannerViewModel: ObservableObject {
    @Published private(set) var plannedMeals: [PlannedMeal] = []
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var visibleWeekAnchor: Date
    @Published private(set) var selectedDate: Date
    @Published var displayMode: MealPlannerDisplayMode = .weekly
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isResettingPlan = false
    @Published private(set) var resetPlanCompletedCount = 0
    @Published private(set) var resetPlanTotalCount = 0
    @Published private(set) var isAutoPlanGenerating = false
    @Published private(set) var isAutoPlanApplying = false
    @Published var autoPlanDraft: AutoPlanDraft?
    @Published var autoPlanResultMessage: String?
    @Published var errorMessage: String?

    private let service: MealPlannerService
    private var calendar: Calendar
    private var activeHomeId: UUID?
    private var activeTimezone: String?
    private var activeLoadRange: (start: Date, end: Date)?
    private var autoPlanEligibleMeals: [Meal] = []
    private var autoPlanFavoritesByMember: [UUID: Set<UUID>] = [:]
    private var autoPlanMembers: [AutoPlanMember] = []
    private var autoPlanRecentMeals: [PlannedMeal] = []
    private var loadTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var needsReloadAfterReset = false

    init(service: MealPlannerService? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.service = service ?? MealPlannerService(calendar: calendar)
        self.calendar = calendar
        let today = calendar.startOfDay(for: Date())
        visibleWeekAnchor = today
        selectedDate = today
        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .homeyCalendarEventsDidChange) {
                await self?.handleCalendarEventsDidChange()
            }
        }
    }

    deinit {
        loadTask?.cancel()
        notificationTask?.cancel()
    }

    func load(homeId: UUID?, weekStartsOn: Int?, timezone: String?) {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)
        activeTimezone = timezone
        activeLoadRange = nil

        guard let homeId else {
            clear()
            return
        }

        let today = calendar.startOfDay(for: Date())
        visibleWeekAnchor = today
        selectedDate = today

        if activeHomeId != homeId {
            activeHomeId = homeId
            plannedMeals = []
        }

        scheduleLoad(homeId: homeId)
    }

    func loadPreview(homeId: UUID?, weekStartsOn: Int?, timezone: String?) {
        configureWeekStart(weekStartsOn)
        configureTimezone(timezone)
        activeTimezone = timezone
        activeLoadRange = upcomingPreviewRange

        guard let homeId else {
            clear()
            return
        }

        if activeHomeId != homeId {
            activeHomeId = homeId
            plannedMeals = []
            let today = calendar.startOfDay(for: Date())
            visibleWeekAnchor = today
            selectedDate = today
        }

        scheduleLoad(homeId: homeId)
    }

    func reload() async {
        guard let activeHomeId else {
            clear()
            return
        }
        if activeLoadRange != nil {
            activeLoadRange = upcomingPreviewRange
        }
        await loadPlannedMeals(homeId: activeHomeId)
    }

    func moveToPreviousWeek() {
        moveWeek(by: -1)
    }

    func moveToNextWeek() {
        moveWeek(by: 1)
    }

    func moveToToday() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        visibleWeekAnchor = today
        if let activeHomeId {
            scheduleLoad(homeId: activeHomeId)
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }

    func weekDays() -> [Date] {
        guard let range = visibleWeekRange else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: range.start)
        }
    }

    func autoPlanSelectableWeekDays() -> [Date] {
        let today = calendar.startOfDay(for: Date())
        return weekDays().filter { calendar.startOfDay(for: $0) >= today }
    }

    func autoPlanUnavailableMessage() -> String? {
        autoPlanSelectableWeekDays().isEmpty ? "This week has already passed." : nil
    }

    func upcomingPreviewDays(count: Int = 3) -> [Date] {
        let start = calendar.startOfDay(for: Date())
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    var visibleWeekRange: (start: Date, end: Date)? {
        let start = startOfWeek(containing: visibleWeekAnchor)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return nil
        }
        return (start, end)
    }

    var visibleWeekTitle: String {
        guard let range = visibleWeekRange,
              let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end) else {
            return "This Week"
        }

        if calendar.isDate(range.start, equalTo: inclusiveEnd, toGranularity: .month) {
            let startDay = Self.dayFormatter.string(from: range.start)
            let endDay = Self.dayFormatter.string(from: inclusiveEnd)
            let monthYear = Self.monthYearFormatter.string(from: range.start)
            return "\(monthYear) \(startDay)-\(endDay)"
        }

        if calendar.component(.year, from: range.start) == calendar.component(.year, from: inclusiveEnd) {
            return "\(Self.monthDayFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
        }

        return "\(Self.monthDayYearFormatter.string(from: range.start)) - \(Self.monthDayYearFormatter.string(from: inclusiveEnd))"
    }

    var plannedMealCount: Int {
        Set(plannedMeals.map(\.id)).count
    }

    var resetPlanWeekStartTitle: String {
        guard let weekStart = visibleWeekRange?.start else {
            return "this week"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d/yy"
        return formatter.string(from: weekStart)
    }

    var uniqueRecipeCount: Int {
        Set(plannedMeals.map { $0.meal.id }).count
    }

    func plannedMeals(on day: Date, mealType: MealType? = nil) -> [PlannedMeal] {
        plannedMeals
            .filter { plannedMeal in
                calendar.isDate(plannedMeal.startsAt, inSameDayAs: day)
                    && (mealType == nil || plannedMeal.mealType == mealType)
            }
            .sortedForMealPlanner()
    }

    func mealsForMonth() -> [Date: [PlannedMeal]] {
        Dictionary(grouping: plannedMeals) { calendar.startOfDay(for: $0.startsAt) }
    }

    func addMeal(_ meal: Meal, to date: Date, mealType: MealType, servings: Decimal?, notes: String?, permissions: HomePermissions) async {
        guard permissions.meals.canPlanMeals else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard let activeHomeId else { return }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let plannedMeal = try await service.createPlannedMeal(
                homeId: activeHomeId,
                meal: meal,
                mealType: mealType,
                date: date,
                plannedServings: servings,
                mealNotes: notes,
                timezone: activeTimezone
            )
            replacePlannedMeal(plannedMeal)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveMeal(_ plannedMeal: PlannedMeal, to date: Date, mealType: MealType, permissions: HomePermissions) async {
        guard permissions.meals.canPlanMeals else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        let previous = plannedMeals
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        defer { isSaving = false }

        do {
            let moved = try await service.movePlannedMeal(plannedMeal, to: date, mealType: mealType, timezone: activeTimezone)
            replacePlannedMeal(moved)
        } catch {
            plannedMeals = previous
            errorMessage = error.localizedDescription
        }
    }

    func removeMeal(_ plannedMeal: PlannedMeal, permissions: HomePermissions) async {
        guard permissions.meals.canRemovePlannedMeals else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil
        let previous = plannedMeals
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        defer { isSaving = false }

        do {
            try await service.removePlannedMeal(calendarEventId: plannedMeal.calendarEventId)
        } catch {
            plannedMeals = previous
            errorMessage = error.localizedDescription
        }
    }

    func resetVisibleWeekPlan(permissions: HomePermissions) async {
        guard permissions.meals.canClearMealPlan else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard let range = visibleWeekRange else {
            errorMessage = MealPlannerServiceError.invalidDateRange.localizedDescription
            return
        }
        guard !isSaving else { return }

        let mealsInWeek = plannedMeals.filter { plannedMeal in
            plannedMeal.startsAt < range.end && plannedMeal.endsAt > range.start
        }
        guard !mealsInWeek.isEmpty else { return }

        isSaving = true
        isResettingPlan = true
        resetPlanCompletedCount = 0
        resetPlanTotalCount = Set(mealsInWeek.map(\.calendarEventId)).count
        needsReloadAfterReset = false
        errorMessage = nil
        let eventIds = Array(Set(mealsInWeek.map(\.calendarEventId)))
        defer {
            isSaving = false
            isResettingPlan = false
            resetPlanCompletedCount = 0
            resetPlanTotalCount = 0
            needsReloadAfterReset = false
        }

        do {
            for eventId in eventIds {
                try await service.removePlannedMeal(calendarEventId: eventId)
                resetPlanCompletedCount += 1
            }
            plannedMeals.removeAll { eventIds.contains($0.calendarEventId) }
            if needsReloadAfterReset {
                await reload()
            }
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    func defaultAutoPlanConfiguration() -> AutoPlanConfiguration {
        AutoPlanConfiguration.defaultConfiguration(weekDays: autoPlanSelectableWeekDays())
    }

    func autoPlanDisabledReason(configuration: AutoPlanConfiguration, permissions: HomePermissions) -> String? {
        guard permissions.meals.canRunAutoPlan else {
            return "You do not have permission to run Auto Plan."
        }
        guard activeHomeId != nil else {
            return "Loading your Home..."
        }
        guard !isAutoPlanGenerating else {
            return nil
        }
        guard autoPlanUnavailableMessage() == nil else {
            return "This week has already passed."
        }
        let configuration = normalizedAutoPlanConfiguration(configuration)
        guard !configuration.selectedDates.isEmpty else {
            return "Select at least one day."
        }
        guard !configuration.selectedMealTypes.isEmpty else {
            return "Select at least one meal type."
        }
        guard !isLoading else {
            return "Loading your meal plan..."
        }
        return nil
    }

    func generateAutoPlan(configuration: AutoPlanConfiguration, meals: [Meal], members: [HomeMemberDisplay], permissions: HomePermissions) async {
        #if DEBUG
        print("AutoPlan Generate tapped")
        #endif
        guard !isAutoPlanGenerating else {
            #if DEBUG
            print("AutoPlan Generate stopped: already generating")
            #endif
            return
        }

        isAutoPlanGenerating = true
        errorMessage = nil
        autoPlanResultMessage = nil
        defer { isAutoPlanGenerating = false }

        guard permissions.meals.canRunAutoPlan else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            #if DEBUG
            print("AutoPlan Generate stopped: permission denied")
            #endif
            return
        }
        guard let activeHomeId, let range = visibleWeekRange else {
            errorMessage = MealPlannerServiceError.invalidDateRange.localizedDescription
            #if DEBUG
            print("AutoPlan Generate stopped: missing selected Home or week range")
            #endif
            return
        }
        let configuration = normalizedAutoPlanConfiguration(configuration)
        guard !configuration.selectedDates.isEmpty else {
            autoPlanDraft = nil
            autoPlanResultMessage = "This week has already passed."
            #if DEBUG
            print("AutoPlan Generate stopped: no eligible selected dates")
            #endif
            return
        }
        guard !configuration.selectedMealTypes.isEmpty else {
            autoPlanDraft = nil
            autoPlanResultMessage = "Select at least one meal type."
            #if DEBUG
            print("AutoPlan Generate stopped: no selected meal types")
            #endif
            return
        }

        do {
            #if DEBUG
            print("AutoPlan configuration validated")
            print("AutoPlan generation task started")
            #endif
            let currentMembers = members.filter { $0.homeId == activeHomeId }
            let autoMembers = currentMembers.map { AutoPlanMember(id: $0.userId, displayName: $0.displayName) }
            let memberIds = Set(autoMembers.map(\.id))
            async let householdFavorites = service.fetchHouseholdFavorites(homeId: activeHomeId, memberUserIds: memberIds)
            async let recentMeals = service.fetchRecentPlannedMeals(homeId: activeHomeId, weekStart: range.start, weekEnd: range.end)
            let loadedFavorites = try await householdFavorites
            let loadedRecentMeals = try await recentMeals
            let favoritesByMember = Dictionary(grouping: loadedFavorites, by: \.userId)
                .mapValues { Set($0.map(\.mealId)) }
            let eligibleMeals = meals.filter { meal in
                meal.homeId == activeHomeId
                    && !meal.isArchived
                    && configuration.selectedMealTypes.contains { meal.mealTypes.contains($0) }
            }

            #if DEBUG
            print("========== AUTO PLAN GENERATION ==========")
            print("selected_home_id: \(activeHomeId.uuidString)")
            print("displayed_week_start: \(range.start)")
            print("displayed_week_end: \(range.end)")
            print("today_home_local_date: \(calendar.startOfDay(for: Date()))")
            print("selected_dates: \(configuration.selectedDates.count)")
            print("selected_meal_types: \(configuration.selectedMealTypes.map(\.rawValue).sorted())")
            print("past_slots_skipped: \(autoPlanPastSlotCount(for: configuration))")
            print("eligible_slots: \(autoPlanEligibleSlotCount(for: configuration))")
            print("member_count: \(autoMembers.count)")
            print("household_favorite_row_count: \(loadedFavorites.count)")
            print("existing_filled_slot_count: \(autoPlanExistingSlotCount(for: configuration))")
            print("eligible_recipe_count: \(eligibleMeals.count)")
            for day in weekDays() where configuration.selectedDates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
                print("selected_day: \(calendar.startOfDay(for: day)) eligible: \(!isPastAutoPlanDate(day))")
            }
            print("engine_started")
            #endif

            let engine = AutoPlanEngine(calendar: calendar, seed: range.start.hashValue)
            let draft = engine.generateDraft(
                homeId: activeHomeId,
                weekRange: range,
                weekDays: weekDays(),
                eligibleMeals: eligibleMeals,
                favoritesByMember: favoritesByMember,
                members: autoMembers,
                existingPlannedMeals: plannedMeals,
                recentPlannedMeals: loadedRecentMeals,
                configuration: configuration
            )
            autoPlanEligibleMeals = eligibleMeals
            autoPlanFavoritesByMember = favoritesByMember
            autoPlanMembers = autoMembers
            autoPlanRecentMeals = loadedRecentMeals
            autoPlanDraft = draft
            autoPlanResultMessage = autoPlanGenerationMessage(for: draft, eligibleMealCount: eligibleMeals.count)
            #if DEBUG
            let suggestionCount = draft.creatableSlots.count
            let unfilledCount = draft.slots.filter { $0.suggestion?.status == .noSuggestion }.count
            print("engine_completed")
            print("suggestions_generated: \(suggestionCount)")
            print("unfilled_slots: \(unfilledCount)")
            print("preview_state_assigned")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("AutoPlan Generate failed")
            print(error.localizedDescription)
            print(String(reflecting: error))
            #endif
        }
    }

    func rerollAutoPlanSlot(_ slotId: AutoPlanSlotID) {
        guard let draft = autoPlanDraft else { return }
        let engine = AutoPlanEngine(calendar: calendar, seed: Date().hashValue)
        autoPlanDraft = engine.reroll(
            slotId: slotId,
            draft: draft,
            eligibleMeals: autoPlanEligibleMeals,
            favoritesByMember: autoPlanFavoritesByMember,
            members: autoPlanMembers,
            existingPlannedMeals: plannedMeals,
            recentPlannedMeals: autoPlanRecentMeals
        )
    }

    func regenerateAutoPlanSuggestions() {
        guard let draft = autoPlanDraft, let activeHomeId, let range = visibleWeekRange else { return }
        let configuration = normalizedAutoPlanConfiguration(draft.configuration)
        guard !configuration.selectedDates.isEmpty else {
            autoPlanDraft = nil
            autoPlanResultMessage = "This week has already passed."
            return
        }
        let engine = AutoPlanEngine(calendar: calendar, seed: Date().hashValue)
        autoPlanDraft = engine.generateDraft(
            homeId: activeHomeId,
            weekRange: range,
            weekDays: weekDays(),
            eligibleMeals: autoPlanEligibleMeals,
            favoritesByMember: autoPlanFavoritesByMember,
            members: autoPlanMembers,
            existingPlannedMeals: plannedMeals,
            recentPlannedMeals: autoPlanRecentMeals,
            configuration: configuration
        )
    }

    func removeAutoPlanSuggestion(_ slotId: AutoPlanSlotID) {
        guard var draft = autoPlanDraft,
              let index = draft.slots.firstIndex(where: { $0.id == slotId }),
              !draft.slots[index].isFilled else { return }
        draft.slots[index].suggestion = AutoPlanSuggestion(
            meal: nil,
            status: .noSuggestion,
            attributedMemberId: nil,
            favoriteMemberIds: [],
            score: 0,
            explanation: "Removed from draft"
        )
        autoPlanDraft = draft
    }

    func manuallySelectAutoPlanMeal(_ meal: Meal, for slotId: AutoPlanSlotID) {
        guard var draft = autoPlanDraft,
              let index = draft.slots.firstIndex(where: { $0.id == slotId }),
              !draft.slots[index].isFilled else { return }
        let favoriteMemberIds = autoPlanMembers.map(\.id).filter { autoPlanFavoritesByMember[$0, default: []].contains(meal.id) }
        draft.slots[index].suggestion = AutoPlanSuggestion(
            meal: meal,
            status: .manuallySelected,
            attributedMemberId: nil,
            favoriteMemberIds: favoriteMemberIds,
            score: 0,
            explanation: "Manually selected"
        )
        autoPlanDraft = draft
    }

    func applyAutoPlan(permissions: HomePermissions) async {
        guard permissions.meals.canApplyAutoPlan else {
            errorMessage = MealPlannerServiceError.permissionDenied.localizedDescription
            return
        }
        guard let activeHomeId, let draft = autoPlanDraft else { return }
        guard !isAutoPlanApplying else { return }

        isAutoPlanApplying = true
        errorMessage = nil
        var plannedCount = 0
        var skippedCount = 0
        var failedCount = 0
        defer { isAutoPlanApplying = false }

        for slot in draft.creatableSlots {
            guard let meal = slot.suggestion?.meal else { continue }
            guard !isPastAutoPlanDate(slot.date) else {
                skippedCount += 1
                #if DEBUG
                print("Auto Plan skipped past slot during apply: \(slot.id.description)")
                #endif
                continue
            }
            do {
                guard try await isAutoPlanSlotStillEmpty(slot, homeId: activeHomeId) else {
                    skippedCount += 1
                    continue
                }
                let plannedMeal = try await service.createPlannedMeal(
                    homeId: activeHomeId,
                    meal: meal,
                    mealType: slot.mealType,
                    date: slot.date,
                    plannedServings: meal.servings,
                    mealNotes: nil,
                    timezone: activeTimezone
                )
                replacePlannedMeal(plannedMeal)
                plannedCount += 1
                #if DEBUG
                print("Auto Plan created calendar event: \(plannedMeal.calendarEventId.uuidString)")
                #endif
            } catch {
                failedCount += 1
                #if DEBUG
                print("Auto Plan apply failed")
                print("slot: \(slot.id.description)")
                print("meal_id: \(meal.id.uuidString)")
                print(String(reflecting: error))
                #endif
            }
        }

        autoPlanResultMessage = AutoPlanResultSummary(plannedCount: plannedCount, skippedCount: skippedCount, failedCount: failedCount).message
        await reload()
    }

    func memberName(for userId: UUID) -> String {
        autoPlanMembers.first { $0.id == userId }?.displayName ?? "a household member"
    }

    func dismissAutoPlanDraft() {
        autoPlanDraft = nil
        autoPlanResultMessage = nil
    }

    private func configureWeekStart(_ weekStartsOn: Int?) {
        let firstWeekday = weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
        guard calendar.firstWeekday != firstWeekday else { return }
        calendar.firstWeekday = firstWeekday
        service.configureWeekStart(weekStartsOn)
        visibleWeekAnchor = selectedDate
    }

    private func configureTimezone(_ timezone: String?) {
        if let timezone, let timeZone = TimeZone(identifier: timezone) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .autoupdatingCurrent
        }
        service.configureTimezone(timezone)
    }

    private func clear() {
        loadTask?.cancel()
        activeHomeId = nil
        activeLoadRange = nil
        isResettingPlan = false
        resetPlanCompletedCount = 0
        resetPlanTotalCount = 0
        needsReloadAfterReset = false
        autoPlanDraft = nil
        autoPlanResultMessage = nil
        autoPlanEligibleMeals = []
        autoPlanFavoritesByMember = [:]
        autoPlanMembers = []
        autoPlanRecentMeals = []
        plannedMeals = []
        categories = []
        isLoading = false
        errorMessage = nil
    }

    private func handleCalendarEventsDidChange() async {
        if isResettingPlan {
            needsReloadAfterReset = true
            return
        }
        await reload()
    }

    private func scheduleLoad(homeId: UUID) {
        loadTask?.cancel()
        if activeLoadRange != nil {
            activeLoadRange = upcomingPreviewRange
        }
        loadTask = Task { [weak self] in
            await self?.loadPlannedMeals(homeId: homeId)
        }
    }

    private func loadPlannedMeals(homeId: UUID) async {
        guard let range = activeLoadRange ?? visibleWeekRange else {
            errorMessage = MealPlannerServiceError.invalidDateRange.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let loadedMeals = service.fetchPlannedMeals(homeId: homeId, startDate: range.start, endDate: range.end)
            async let loadedCategories = service.fetchCategories(homeId: homeId)
            let loaded = try await loadedMeals
            let resolvedCategories = try await loadedCategories
            guard !Task.isCancelled, activeHomeId == homeId else { return }
            plannedMeals = loaded
            categories = resolvedCategories
        } catch {
            guard !Task.isCancelled, activeHomeId == homeId else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func moveWeek(by value: Int) {
        let selectedWeekdayOffset = daysFromStartOfWeek(to: selectedDate)
        let currentWeekStart = startOfWeek(containing: visibleWeekAnchor)
        guard let newWeekStart = calendar.date(byAdding: .weekOfYear, value: value, to: currentWeekStart),
              let newSelectedDate = calendar.date(byAdding: .day, value: selectedWeekdayOffset, to: newWeekStart) else {
            return
        }

        visibleWeekAnchor = newWeekStart
        selectedDate = calendar.startOfDay(for: newSelectedDate)
        if let activeHomeId {
            scheduleLoad(homeId: activeHomeId)
        }
    }

    private func replacePlannedMeal(_ plannedMeal: PlannedMeal) {
        plannedMeals.removeAll { $0.calendarEventId == plannedMeal.calendarEventId }
        if let range = activeLoadRange ?? visibleWeekRange,
           plannedMeal.startsAt < range.end,
           plannedMeal.endsAt > range.start {
            plannedMeals.append(plannedMeal)
        }
        plannedMeals = plannedMeals.sortedForMealPlanner()
    }

    private var upcomingPreviewRange: (start: Date, end: Date)? {
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 3, to: start) else {
            return nil
        }
        return (start, end)
    }

    private func normalizedAutoPlanConfiguration(_ configuration: AutoPlanConfiguration) -> AutoPlanConfiguration {
        let selectableDays = autoPlanSelectableWeekDays()
        let selectedDates = Set(selectableDays.filter { selectableDay in
            configuration.selectedDates.contains { calendar.isDate($0, inSameDayAs: selectableDay) }
        })
        return AutoPlanConfiguration(
            selectedDates: selectedDates,
            selectedMealTypes: configuration.selectedMealTypes,
            recipePool: configuration.recipePool,
            allowsRepeats: configuration.allowsRepeats
        )
    }

    private func isPastAutoPlanDate(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }

    private func autoPlanPastSlotCount(for configuration: AutoPlanConfiguration) -> Int {
        let today = calendar.startOfDay(for: Date())
        let pastDayCount = weekDays().filter { day in
            configuration.selectedDates.contains { calendar.isDate($0, inSameDayAs: day) }
                && calendar.startOfDay(for: day) < today
        }.count
        return pastDayCount * configuration.selectedMealTypes.count
    }

    private func autoPlanEligibleSlotCount(for configuration: AutoPlanConfiguration) -> Int {
        normalizedAutoPlanConfiguration(configuration).selectedDates.count * configuration.selectedMealTypes.count
    }

    private func autoPlanExistingSlotCount(for configuration: AutoPlanConfiguration) -> Int {
        let normalizedConfiguration = normalizedAutoPlanConfiguration(configuration)
        let filledSlotIds = Set(plannedMeals.compactMap { plannedMeal -> AutoPlanSlotID? in
            guard normalizedConfiguration.selectedDates.contains(where: { calendar.isDate($0, inSameDayAs: plannedMeal.startsAt) }),
                  normalizedConfiguration.selectedMealTypes.contains(plannedMeal.mealType) else {
                return nil
            }
            return AutoPlanSlotID(dayKey: autoPlanDayKey(for: plannedMeal.startsAt), mealType: plannedMeal.mealType)
        })
        return filledSlotIds.count
    }

    private func autoPlanGenerationMessage(for draft: AutoPlanDraft, eligibleMealCount: Int) -> String? {
        guard !draft.slots.isEmpty else {
            return "This week has already passed."
        }

        let missingSlots = draft.slots.filter { !$0.isFilled }
        guard !missingSlots.isEmpty else {
            return "Your selected meal slots are already planned."
        }

        if draft.creatableSlots.isEmpty {
            if eligibleMealCount == 0 {
                return "Auto Plan could not find eligible recipes for the selected meal types. Add more recipes, update meal types, switch recipe pool options, or allow repeats if appropriate."
            }
            return "Auto Plan could not find suggestions for the selected meal slots."
        }

        let unfilledCount = draft.slots.filter { $0.suggestion?.status == .noSuggestion }.count
        if unfilledCount > 0 {
            return "Auto Plan filled \(draft.creatableSlots.count) of \(missingSlots.count) missing meal slots. \(unfilledCount) slots need more eligible recipes."
        }
        return "Auto Plan filled \(draft.creatableSlots.count) of \(missingSlots.count) missing meal slots."
    }

    private func autoPlanDayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func isAutoPlanSlotStillEmpty(_ slot: AutoPlanSlot, homeId: UUID) async throws -> Bool {
        let dayStart = calendar.startOfDay(for: slot.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            throw MealPlannerServiceError.invalidDateRange
        }
        let currentMeals = try await service.fetchPlannedMeals(homeId: homeId, startDate: dayStart, endDate: dayEnd)
        return !currentMeals.contains { plannedMeal in
            calendar.isDate(plannedMeal.startsAt, inSameDayAs: slot.date) && plannedMeal.mealType == slot.mealType
        }
    }

    private func startOfWeek(containing date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let leadingDays = daysFromStartOfWeek(to: startOfDay)
        return calendar.date(byAdding: .day, value: -leadingDays, to: startOfDay) ?? startOfDay
    }

    private func daysFromStartOfWeek(to date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()
}

enum MealPlannerDisplayMode: String, CaseIterable, Identifiable {
    case weekly
    case monthly
    case list

    static let visibleModes: [MealPlannerDisplayMode] = [.weekly, .list]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .list: "List"
        }
    }
}
