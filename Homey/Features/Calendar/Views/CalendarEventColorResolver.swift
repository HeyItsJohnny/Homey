import SwiftUI

enum CalendarEventColorResolver {
    static func color(
        for event: CalendarEvent,
        categories: [CalendarCategory],
        fallback: Color = HomeyDashboardTheme.warmBrown
    ) -> Color {
        guard let category = category(for: event, categories: categories),
              let color = Color(hex: category.colorHex) else {
            #if DEBUG
            print("Calendar event color fallback used")
            print("calendar_event_id: \(event.eventId.uuidString)")
            print("category_id: \(event.categoryId?.uuidString ?? "nil")")
            print("color_source: fallback")
            #endif
            return fallback
        }

        #if DEBUG
        print("Calendar event color resolved from category")
        print("calendar_event_id: \(event.eventId.uuidString)")
        print("category_id: \(category.id.uuidString)")
        print("color_hex: \(category.colorHex)")
        #endif
        return color
    }

    static func category(for event: CalendarEvent, categories: [CalendarCategory]) -> CalendarCategory? {
        guard let categoryId = event.categoryId else {
            return nil
        }

        return categories.first { $0.id == categoryId }
    }
}
