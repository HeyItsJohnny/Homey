import Combine
import Foundation
import PostgREST
import Supabase

@MainActor
final class MealPlannerService: ObservableObject {
    private let client = SupabaseManager.shared.client
    private let calendarService: CalendarService
    private let mealService: MealServicing
    private var calendar: Calendar

    init(
        calendarService: CalendarService? = nil,
        mealService: MealServicing? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendarService = calendarService ?? CalendarService(calendar: calendar)
        self.mealService = mealService ?? MealService()
        self.calendar = calendar
    }

    func configureWeekStart(_ weekStartsOn: Int?) {
        calendar.firstWeekday = Self.firstWeekday(from: weekStartsOn)
    }

    func configureTimezone(_ timezone: String?) {
        if let timezone, let timeZone = TimeZone(identifier: timezone) {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = .autoupdatingCurrent
        }
    }

    func fetchCategories(homeId: UUID) async throws -> [CalendarCategory] {
        try await calendarService.fetchCategories(homeId: homeId)
    }

    func fetchHouseholdFavorites(homeId: UUID, memberUserIds: Set<UUID>) async throws -> [HouseholdMealFavorite] {
        try await mealService.fetchHouseholdFavorites(homeId: homeId, memberUserIds: memberUserIds)
    }

    func fetchRecentPlannedMeals(homeId: UUID, weekStart: Date, weekEnd: Date) async throws -> [PlannedMeal] {
        guard let historyStart = calendar.date(byAdding: .day, value: -7, to: weekStart) else {
            throw MealPlannerServiceError.invalidDateRange
        }
        return try await fetchPlannedMeals(homeId: homeId, startDate: historyStart, endDate: weekEnd)
    }

    func fetchPlannedMeals(homeId: UUID, startDate: Date, endDate: Date) async throws -> [PlannedMeal] {
        guard endDate > startDate else {
            throw MealPlannerServiceError.invalidDateRange
        }

        do {
            try await requireAuthenticatedSession()
            let events = try await calendarService.fetchEvents(homeId: homeId, rangeStart: startDate, rangeEnd: endDate)
            return try await fetchPlannedMeals(homeId: homeId, events: events)
        } catch let error as MealPlannerServiceError {
            throw error
        } catch {
            logPlannerError(error, operation: "fetchPlannedMeals", homeId: homeId)
            throw MealPlannerServiceError.loadFailed
        }
    }

    func fetchPlannedMeals(homeId: UUID, events: [CalendarEvent]) async throws -> [PlannedMeal] {
        do {
            try await requireAuthenticatedSession()
            let eventIds = Set(events.map(\.eventId))
            guard !eventIds.isEmpty else { return [] }

            let details: [MealEventDetail] = try await client
                .from("meal_event_details")
                .select()
                .execute()
                .value
            let matchingDetails = details.filter { eventIds.contains($0.calendarEventId) }
            guard !matchingDetails.isEmpty else { return [] }

            let meals = try await mealService.fetchMeals(homeId: homeId)
            let mealById = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
            var eventById: [UUID: CalendarEvent] = [:]
            for event in events {
                eventById[event.eventId] = event
            }

            var plannedMeals: [PlannedMeal] = []
            for detail in matchingDetails {
                guard let event = eventById[detail.calendarEventId],
                      let meal = mealById[detail.mealId] else {
                    continue
                }

                let photoURL: URL?
                if let path = meal.primaryPhotoPath {
                    photoURL = try? await mealService.createSignedMealPhotoURL(path: path)
                } else {
                    photoURL = nil
                }

                plannedMeals.append(
                    PlannedMeal(
                        calendarEvent: event,
                        mealEventDetail: detail,
                        meal: meal,
                        signedPhotoURL: photoURL
                    )
                )
            }

            return plannedMeals.sortedForMealPlanner()
        } catch let error as MealPlannerServiceError {
            throw error
        } catch {
            logPlannerError(error, operation: "fetchPlannedMeals", homeId: homeId)
            throw MealPlannerServiceError.loadFailed
        }
    }

    func createPlannedMeal(
        homeId: UUID,
        meal: Meal,
        mealType: MealType,
        date: Date,
        plannedServings: Decimal?,
        mealNotes: String?,
        timezone: String?
    ) async throws -> PlannedMeal {
        do {
            let userId = try await authenticatedUserId()
            let startsAt = scheduledDate(for: date, mealType: mealType)
            guard let endsAt = calendar.date(byAdding: .hour, value: 1, to: startsAt) else {
                throw MealPlannerServiceError.invalidDateRange
            }
            let mealCategory = try await calendarService.resolveMealCategory(homeId: homeId)

            let eventId = try await calendarService.createEvent(
                homeId: homeId,
                title: meal.name,
                notes: normalizedOptionalString(mealNotes),
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: false,
                timezone: timezone,
                categoryId: mealCategory.id
            )

            #if DEBUG
            print("Meal Planner calendar event created")
            print("selected_home_id: \(homeId.uuidString)")
            print("calendar_event_id: \(eventId.uuidString)")
            print("assigned_category_id: \(mealCategory.id.uuidString)")
            #endif

            do {
                let payload = CreateMealEventDetailPayload(
                    calendarEventId: eventId,
                    mealId: meal.id,
                    mealType: mealType,
                    plannedServings: plannedServings,
                    mealNotes: normalizedOptionalString(mealNotes),
                    shoppingGenerated: false,
                    createdBy: userId,
                    updatedBy: userId
                )

                try await client
                    .from("meal_event_details")
                    .insert(payload)
                    .execute()
            } catch {
                logPlannerError(error, operation: "create meal_event_details", homeId: homeId, eventId: eventId, mealId: meal.id)
                try? await calendarService.deleteEvent(eventId: eventId)
                throw MealPlannerServiceError.detailCreateFailed
            }

            guard let plannedMeal = try await fetchPlannedMeal(calendarEventId: eventId, homeId: homeId, near: startsAt) else {
                throw MealPlannerServiceError.loadFailed
            }

            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return plannedMeal
        } catch let error as MealPlannerServiceError {
            throw error
        } catch CalendarServiceError.mealCategoryUnavailable {
            throw MealPlannerServiceError.mealCategoryUnavailable
        } catch {
            logPlannerError(error, operation: "createPlannedMeal", homeId: homeId, mealId: meal.id)
            throw MealPlannerServiceError.createFailed
        }
    }

    func updatePlannedMeal(_ plannedMeal: PlannedMeal, plannedServings: Decimal?, mealNotes: String?) async throws -> PlannedMeal {
        do {
            let userId = try await authenticatedUserId()
            let payload = UpdateMealEventDetailPayload(
                plannedServings: plannedServings,
                mealNotes: normalizedOptionalString(mealNotes),
                updatedBy: userId
            )
            try await client
                .from("meal_event_details")
                .update(payload)
                .eq("calendar_event_id", value: plannedMeal.calendarEventId.uuidString)
                .execute()

            guard let refreshed = try await fetchPlannedMeal(calendarEventId: plannedMeal.calendarEventId, homeId: plannedMeal.meal.homeId, near: plannedMeal.startsAt) else {
                throw MealPlannerServiceError.loadFailed
            }
            return refreshed
        } catch let error as MealPlannerServiceError {
            throw error
        } catch {
            logPlannerError(error, operation: "updatePlannedMeal", eventId: plannedMeal.calendarEventId, mealId: plannedMeal.meal.id)
            throw MealPlannerServiceError.updateFailed
        }
    }

    func movePlannedMeal(_ plannedMeal: PlannedMeal, to date: Date, mealType: MealType, timezone: String?) async throws -> PlannedMeal {
        do {
            let userId = try await authenticatedUserId()
            let newStart = scheduledDate(for: date, mealType: mealType)
            let duration = plannedMeal.calendarEvent.endsAt.timeIntervalSince(plannedMeal.calendarEvent.startsAt)
            let newEnd = newStart.addingTimeInterval(max(duration, 3600))

            try await calendarService.updateEvent(
                eventId: plannedMeal.calendarEventId,
                title: plannedMeal.meal.name,
                notes: plannedMeal.calendarEvent.notes,
                location: plannedMeal.calendarEvent.location,
                startsAt: newStart,
                endsAt: newEnd,
                isAllDay: plannedMeal.calendarEvent.isAllDay,
                timezone: timezone ?? plannedMeal.calendarEvent.timezone,
                categoryId: plannedMeal.calendarEvent.categoryId,
                assignedUserIds: plannedMeal.calendarEvent.assignedUserIds,
                recurrence: CalendarRecurrenceInput(
                    frequency: plannedMeal.calendarEvent.recurrenceFrequency,
                    interval: plannedMeal.calendarEvent.recurrenceInterval,
                    daysOfWeek: plannedMeal.calendarEvent.recurrenceDaysOfWeek,
                    endDate: plannedMeal.calendarEvent.recurrenceEndDate,
                    count: plannedMeal.calendarEvent.recurrenceCount
                )
            )

            let payload = UpdateMealEventDetailPayload(mealType: mealType, updatedBy: userId)
            try await client
                .from("meal_event_details")
                .update(payload)
                .eq("calendar_event_id", value: plannedMeal.calendarEventId.uuidString)
                .execute()

            guard let refreshed = try await fetchPlannedMeal(calendarEventId: plannedMeal.calendarEventId, homeId: plannedMeal.meal.homeId, near: newStart) else {
                throw MealPlannerServiceError.loadFailed
            }

            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
            return refreshed
        } catch let error as MealPlannerServiceError {
            throw error
        } catch {
            logPlannerError(error, operation: "movePlannedMeal", eventId: plannedMeal.calendarEventId, mealId: plannedMeal.meal.id)
            throw MealPlannerServiceError.moveFailed
        }
    }

    func removePlannedMeal(calendarEventId: UUID) async throws {
        do {
            try await calendarService.deleteEvent(eventId: calendarEventId)
            NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
        } catch {
            logPlannerError(error, operation: "removePlannedMeal", eventId: calendarEventId)
            throw MealPlannerServiceError.removeFailed
        }
    }

    func updatePlannedMealServings(calendarEventId: UUID, plannedServings: Decimal?) async throws {
        do {
            let userId = try await authenticatedUserId()
            try await client
                .from("meal_event_details")
                .update(UpdateMealEventDetailPayload(plannedServings: plannedServings, updatedBy: userId))
                .eq("calendar_event_id", value: calendarEventId.uuidString)
                .execute()
        } catch {
            logPlannerError(error, operation: "updatePlannedMealServings", eventId: calendarEventId)
            throw MealPlannerServiceError.updateFailed
        }
    }

    func updatePlannedMealNotes(calendarEventId: UUID, mealNotes: String?) async throws {
        do {
            let userId = try await authenticatedUserId()
            try await client
                .from("meal_event_details")
                .update(UpdateMealEventDetailPayload(mealNotes: normalizedOptionalString(mealNotes), updatedBy: userId))
                .eq("calendar_event_id", value: calendarEventId.uuidString)
                .execute()
        } catch {
            logPlannerError(error, operation: "updatePlannedMealNotes", eventId: calendarEventId)
            throw MealPlannerServiceError.updateFailed
        }
    }

    func fetchPlannedMeal(calendarEventId: UUID, homeId: UUID, near date: Date = Date()) async throws -> PlannedMeal? {
        guard let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)),
              let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: date)) else {
            throw MealPlannerServiceError.invalidDateRange
        }
        return try await fetchPlannedMeals(homeId: homeId, startDate: start, endDate: end)
            .first { $0.calendarEventId == calendarEventId }
    }

    private func scheduledDate(for date: Date, mealType: MealType) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let hour: Int
        switch mealType {
        case .breakfast:
            hour = 8
        case .lunch:
            hour = 12
        case .dinner:
            hour = 18
        case .snack:
            hour = 15
        case .dessert:
            hour = 19
        case .drink:
            hour = 10
        }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfDay) ?? startOfDay
    }

    private func authenticatedUserId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            logPlannerError(error, operation: "authenticatedUserId")
            throw MealPlannerServiceError.unauthenticated
        }
    }

    private func requireAuthenticatedSession() async throws {
        _ = try await authenticatedUserId()
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstWeekday(from weekStartsOn: Int?) -> Int {
        weekStartsOn == 2 ? 2 : (weekStartsOn == 1 ? 1 : Calendar.autoupdatingCurrent.firstWeekday)
    }

    private func logPlannerError(_ error: Error, operation: String, homeId: UUID? = nil, eventId: UUID? = nil, mealId: UUID? = nil) {
        #if DEBUG
        print("========== MEAL PLANNER OPERATION FAILED ==========")
        print("operation: \(operation)")
        if let homeId { print("home_id: \(homeId.uuidString)") }
        if let eventId { print("calendar_event_id: \(eventId.uuidString)") }
        if let mealId { print("meal_id: \(mealId.uuidString)") }
        print("localizedDescription: \(error.localizedDescription)")
        print(String(reflecting: error))
        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        print("===================================================")
        #endif
    }
}

enum MealPlannerServiceError: LocalizedError, Equatable {
    case unauthenticated
    case invalidDateRange
    case loadFailed
    case createFailed
    case detailCreateFailed
    case updateFailed
    case moveFailed
    case removeFailed
    case mealCategoryUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .invalidDateRange:
            return "Choose a valid meal planning date."
        case .loadFailed:
            return "We could not load your meal plan."
        case .createFailed:
            return "We could not add this meal to the plan."
        case .detailCreateFailed:
            return "We could not connect this recipe to the calendar event."
        case .updateFailed:
            return "We could not update this planned meal."
        case .moveFailed:
            return "We could not move this planned meal."
        case .removeFailed:
            return "We could not remove this planned meal."
        case .mealCategoryUnavailable:
            return "Homey could not prepare the Meal calendar category for this Home."
        case .permissionDenied:
            return "You do not have permission to update the meal plan."
        }
    }
}

extension Array where Element == PlannedMeal {
    func sortedForMealPlanner() -> [PlannedMeal] {
        sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt {
                return lhs.startsAt < rhs.startsAt
            }
            if lhs.mealType.sortOrder != rhs.mealType.sortOrder {
                return lhs.mealType.sortOrder < rhs.mealType.sortOrder
            }
            return lhs.meal.name.localizedCaseInsensitiveCompare(rhs.meal.name) == .orderedAscending
        }
    }
}

private extension MealType {
    var sortOrder: Int {
        switch self {
        case .breakfast: 0
        case .lunch: 1
        case .dinner: 2
        case .snack: 3
        case .dessert: 4
        case .drink: 5
        }
    }
}
