import Foundation

@MainActor
final class CalendarLinkedEventEnrichmentService {
    private let mealPlannerService: MealPlannerService
    private let choresRepository: ChoresRepository

    init(
        mealPlannerService: MealPlannerService? = nil,
        choresRepository: ChoresRepository? = nil
    ) {
        self.mealPlannerService = mealPlannerService ?? MealPlannerService()
        self.choresRepository = choresRepository ?? ChoresRepository()
    }

    func presentations(
        for events: [CalendarEvent],
        homeId: UUID
    ) async -> [String: CalendarLinkedEventPresentation] {
        guard !events.isEmpty else {
            return [:]
        }

        var presentations: [String: CalendarLinkedEventPresentation] = [:]
        var eventsByEventId: [UUID: CalendarEvent] = [:]
        for event in events {
            eventsByEventId[event.eventId] = event
        }
        let eventLookup = eventsByEventId
        let eventIds = Array(eventLookup.keys)

        async let mealPresentations = loadMealPresentations(homeId: homeId, events: events)
        async let chorePresentations = loadChorePresentations(eventIds: eventIds, eventsByEventId: eventLookup)

        let resolvedMealPresentations = await mealPresentations
        let resolvedChorePresentations = await chorePresentations

        for presentation in resolvedMealPresentations {
            presentations[presentation.id] = presentation
        }

        for presentation in resolvedChorePresentations {
            presentations[presentation.id] = presentation
        }

        return presentations
    }

    private func loadMealPresentations(homeId: UUID, events: [CalendarEvent]) async -> [CalendarLinkedEventPresentation] {
        do {
            let plannedMeals = try await mealPlannerService.fetchPlannedMeals(homeId: homeId, events: events)
            return plannedMeals.map { plannedMeal in
                CalendarLinkedEventPresentation(
                    event: plannedMeal.calendarEvent,
                    content: .meal(plannedMeal)
                )
            }
        } catch {
            #if DEBUG
            print("Unable to enrich meal calendar events: \(String(reflecting: error))")
            #endif
            return []
        }
    }

    private func loadChorePresentations(
        eventIds: [UUID],
        eventsByEventId: [UUID: CalendarEvent]
    ) async -> [CalendarLinkedEventPresentation] {
        do {
            let occurrences = try await choresRepository.fetchOccurrences(calendarEventIds: eventIds)

            return occurrences.compactMap { occurrence in
                guard let calendarEventId = occurrence.calendarEventId,
                      let event = eventsByEventId[calendarEventId] else {
                    return nil
                }

                return CalendarLinkedEventPresentation(
                    event: event,
                    content: .chore(
                        ChoreCalendarEventPresentation(
                            occurrence: occurrence
                        )
                    )
                )
            }
        } catch {
            #if DEBUG
            print("Unable to enrich chore calendar events: \(String(reflecting: error))")
            #endif
            return []
        }
    }
}
