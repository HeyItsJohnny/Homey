import Foundation

struct CalendarLinkedEventPresentation: Identifiable {
    let event: CalendarEvent
    let content: CalendarLinkedEventContent

    var id: String { event.id }

    var plannedMeal: PlannedMeal? {
        if case .meal(let plannedMeal) = content {
            return plannedMeal
        }
        return nil
    }

    var chore: ChoreCalendarEventPresentation? {
        if case .chore(let chore) = content {
            return chore
        }
        return nil
    }
}

enum CalendarLinkedEventContent {
    case meal(PlannedMeal)
    case chore(ChoreCalendarEventPresentation)
}

struct ChoreCalendarEventPresentation: Identifiable {
    let occurrence: ChoreOccurrence

    var id: UUID { occurrence.id }

    var title: String {
        occurrence.titleSnapshot
    }

    var pointsText: String {
        "\(occurrence.pointsValue) \(occurrence.pointsValue == 1 ? "point" : "points")"
    }

    var statusStyle: ChoreOccurrenceStatusStyle {
        ChoreOccurrenceStatusStyle(occurrence: occurrence)
    }
}
