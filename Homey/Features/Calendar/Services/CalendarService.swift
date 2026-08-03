import Combine
import Foundation
import PostgREST
import Supabase

@MainActor
final class CalendarService: ObservableObject {
    private let client = SupabaseManager.shared.client
    private let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func fetchEvents(homeId: UUID, rangeStart: Date, rangeEnd: Date) async throws -> [CalendarEvent] {
        try await fetchEvents(
            homeId: homeId,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            sourceOperation: "fetchEvents"
        )
    }

    private func fetchEvents(homeId: UUID, rangeStart: Date, rangeEnd: Date, sourceOperation: String) async throws -> [CalendarEvent] {
        guard rangeEnd > rangeStart else {
            throw CalendarServiceError.invalidDateRange
        }

        do {
            try await requireAuthenticatedSession()

            let events: [CalendarEvent] = try await client
                .rpc(
                    "get_calendar_events",
                    params: GetCalendarEventsParameters(
                        targetHomeId: homeId,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd
                    )
                )
                .execute()
                .value

            return deduplicatedEvents(events, sourceOperation: sourceOperation).sortedForCalendarDisplay()
        } catch {
            logCalendarError(error, rpcName: "get_calendar_events", homeId: homeId)
            throw CalendarServiceError.loadEventsFailed
        }
    }

    func fetchEventsForDay(homeId: UUID, date: Date) async throws -> [CalendarEvent] {
        let startOfDay = calendar.startOfDay(for: date)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw CalendarServiceError.invalidDateRange
        }

        return try await fetchEvents(
            homeId: homeId,
            rangeStart: startOfDay,
            rangeEnd: startOfNextDay,
            sourceOperation: "fetchEventsForDay"
        )
    }

    func fetchEventsForVisibleMonth(homeId: UUID, month: Date) async throws -> [CalendarEvent] {
        let range = try visibleMonthRange(containing: month)
        return try await fetchEvents(
            homeId: homeId,
            rangeStart: range.start,
            rangeEnd: range.end,
            sourceOperation: "fetchEventsForVisibleMonth"
        )
    }

    func fetchUpcomingEvents(homeId: UUID, from date: Date = Date(), limit: Int) async throws -> [CalendarEvent] {
        guard limit > 0 else {
            return []
        }

        guard let rangeEnd = calendar.date(byAdding: .day, value: 90, to: date) else {
            throw CalendarServiceError.invalidDateRange
        }

        let events = try await fetchEvents(
            homeId: homeId,
            rangeStart: date,
            rangeEnd: rangeEnd,
            sourceOperation: "fetchUpcomingEvents"
        )
        return Array(
            events
                .filter { $0.occurrenceEndsAt > date }
                .sortedForCalendarDisplay()
                .prefix(limit)
        )
    }

    func createEvent(
        homeId: UUID,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String? = nil,
        categoryId: UUID? = nil,
        assignedUserIds: [UUID] = [],
        recurrence: CalendarRecurrenceInput = CalendarRecurrenceInput()
    ) async throws -> UUID {
        let normalizedInput = try normalizedEventInput(
            title: title,
            notes: notes,
            location: location,
            startsAt: startsAt,
            endsAt: endsAt,
            timezone: timezone,
            assignedUserIds: assignedUserIds,
            recurrence: recurrence
        )

        do {
            try await requireAuthenticatedSession()

            let eventId: UUID = try await client
                .rpc(
                    "create_calendar_event",
                    params: CreateCalendarEventParameters(
                        targetHomeId: homeId,
                        title: normalizedInput.title,
                        notes: normalizedInput.notes,
                        location: normalizedInput.location,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timezone: normalizedInput.timezone,
                        categoryId: categoryId,
                        assignedUserIds: normalizedInput.assignedUserIds,
                        recurrence: normalizedInput.recurrence
                    )
                )
                .execute()
                .value

            return eventId
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "create_calendar_event", homeId: homeId)
            throw CalendarServiceError.createEventFailed
        }
    }

    func updateEvent(
        eventId: UUID,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String? = nil,
        categoryId: UUID? = nil,
        assignedUserIds: [UUID] = [],
        recurrence: CalendarRecurrenceInput = CalendarRecurrenceInput()
    ) async throws {
        let normalizedInput = try normalizedEventInput(
            title: title,
            notes: notes,
            location: location,
            startsAt: startsAt,
            endsAt: endsAt,
            timezone: timezone,
            assignedUserIds: assignedUserIds,
            recurrence: recurrence
        )

        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "update_calendar_event",
                    params: UpdateCalendarEventParameters(
                        targetEventId: eventId,
                        title: normalizedInput.title,
                        notes: normalizedInput.notes,
                        location: normalizedInput.location,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timezone: normalizedInput.timezone,
                        categoryId: categoryId,
                        assignedUserIds: normalizedInput.assignedUserIds,
                        recurrence: normalizedInput.recurrence
                    )
                )
                .execute()
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "update_calendar_event", eventId: eventId)
            throw CalendarServiceError.updateEventFailed
        }
    }

    func deleteEvent(eventId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "delete_calendar_event",
                    params: CalendarEventIdParameters(targetEventId: eventId)
                )
                .execute()
        } catch {
            logCalendarError(error, rpcName: "delete_calendar_event", eventId: eventId)
            throw CalendarServiceError.deleteEventFailed
        }
    }

    func updateOccurrence(
        eventId: UUID,
        occurrenceStartsAt: Date,
        title: String,
        startsAt: Date,
        endsAt: Date,
        timezone: String? = nil,
        isAllDay: Bool,
        notes: String? = nil,
        location: String? = nil,
        categoryId: UUID? = nil
    ) async throws {
        let normalizedInput = try normalizedEventInput(
            title: title,
            notes: notes,
            location: location,
            startsAt: startsAt,
            endsAt: endsAt,
            timezone: timezone,
            assignedUserIds: [],
            recurrence: CalendarRecurrenceInput()
        )

        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "update_calendar_event_occurrence",
                    params: UpdateCalendarEventOccurrenceParameters(
                        targetEventId: eventId,
                        targetOccurrenceStartsAt: occurrenceStartsAt,
                        title: normalizedInput.title,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        timezone: normalizedInput.timezone,
                        isAllDay: isAllDay,
                        notes: normalizedInput.notes,
                        location: normalizedInput.location,
                        categoryId: categoryId
                    )
                )
                .execute()
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "update_calendar_event_occurrence", eventId: eventId)
            if isOccurrenceNotPartOfSeriesError(error) {
                throw CalendarServiceError.occurrenceNotPartOfSeries
            }
            if isPermissionError(error) {
                throw CalendarServiceError.permissionDenied
            }
            throw CalendarServiceError.updateEventFailed
        }
    }

    func deleteOccurrence(eventId: UUID, occurrenceStartsAt: Date) async throws {
        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "delete_calendar_event_occurrence",
                    params: DeleteCalendarEventOccurrenceParameters(
                        targetEventId: eventId,
                        targetOccurrenceStartsAt: occurrenceStartsAt
                    )
                )
                .execute()
        } catch {
            logCalendarError(error, rpcName: "delete_calendar_event_occurrence", eventId: eventId)
            if isOccurrenceNotPartOfSeriesError(error) {
                throw CalendarServiceError.occurrenceNotPartOfSeries
            }
            if isPermissionError(error) {
                throw CalendarServiceError.permissionDenied
            }
            throw CalendarServiceError.deleteEventFailed
        }
    }

    func fetchCategories(homeId: UUID) async throws -> [CalendarCategory] {
        do {
            try await requireAuthenticatedSession()

            let categories: [CalendarCategory] = try await client
                .from("calendar_categories")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .execute()
                .value

            return sortedCategories(categories)
        } catch {
            logCalendarError(error, rpcName: "calendar_categories.select", homeId: homeId)
            throw CalendarServiceError.loadCategoriesFailed
        }
    }

    func resolveMealCategory(homeId: UUID) async throws -> CalendarCategory {
        if let category = try await fetchMealSystemCategory(homeId: homeId) {
            logMealCategoryResolution(homeId: homeId, categoryId: category.id, repaired: false)
            return category
        }

        if let ensuredCategory = try await ensureMealSystemCategoryViaRPC(homeId: homeId) {
            logMealCategoryResolution(homeId: homeId, categoryId: ensuredCategory.id, repaired: true)
            return ensuredCategory
        }

        do {
            try await bootstrapMealSystemCategory(homeId: homeId)
        } catch {
            logCalendarError(error, rpcName: "calendar_categories.bootstrap_meal", homeId: homeId)
        }

        if let repairedCategory = try await fetchMealSystemCategory(homeId: homeId) {
            logMealCategoryResolution(homeId: homeId, categoryId: repairedCategory.id, repaired: true)
            return repairedCategory
        }

        throw CalendarServiceError.mealCategoryUnavailable
    }

    func ensureDefaultSystemCategories(homeId: UUID) async {
        do {
            try await requireAuthenticatedSession()
            let userId = try await authenticatedUserId()
            let existingCategories = try await fetchCategories(homeId: homeId)
            let existingSystemKeys = Set(existingCategories.compactMap(\.systemCategoryKey))
            let missingDefaults = CalendarSystemCategoryDefault.allCases.filter { !existingSystemKeys.contains($0.key) }

            guard !missingDefaults.isEmpty else {
                return
            }

            #if DEBUG
            print("Ensuring default calendar system categories")
            print("selected_home_id: \(homeId.uuidString)")
            print("missing_system_keys: \(missingDefaults.map { $0.key.rawValue }.joined(separator: ","))")
            #endif

            for categoryDefault in missingDefaults {
                let payload = CreateSystemCalendarCategoryPayload(
                    homeId: homeId,
                    name: categoryDefault.name,
                    colorHex: categoryDefault.colorHex,
                    iconName: categoryDefault.iconName,
                    sortOrder: categoryDefault.sortOrder,
                    systemKey: categoryDefault.key.rawValue,
                    isSystem: true,
                    createdBy: userId
                )

                do {
                    try await client
                        .from("calendar_categories")
                        .insert(payload)
                        .execute()
                } catch {
                    logCalendarError(error, rpcName: "calendar_categories.insert_system_category", homeId: homeId)
                }
            }
        } catch {
            logCalendarError(error, rpcName: "calendar_categories.ensure_default_system_categories", homeId: homeId)
        }
    }

    func createCategory(homeId: UUID, name: String, colorHex: String, iconName: String? = nil) async throws -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColorHex = try normalizedCategoryColorHex(colorHex)
        let trimmedIconName = normalizedOptionalString(iconName)

        guard !trimmedName.isEmpty else {
            throw CalendarServiceError.emptyCategoryName
        }

        do {
            try await requireAuthenticatedSession()

            let categoryId: UUID = try await client
                .rpc(
                    "create_calendar_category",
                    params: CreateCalendarCategoryParameters(
                        targetHomeId: homeId,
                        categoryName: trimmedName,
                        categoryColorHex: trimmedColorHex,
                        categoryIconName: trimmedIconName
                    )
                )
                .execute()
                .value

            return categoryId
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "create_calendar_category", homeId: homeId)
            if isCalendarCategoryPermissionError(error) {
                throw CalendarServiceError.categoryPermissionDenied
            }
            throw CalendarServiceError.createCategoryFailed
        }
    }

    func updateCategory(categoryId: UUID, name: String, colorHex: String, iconName: String? = nil) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColorHex = try normalizedCategoryColorHex(colorHex)
        let trimmedIconName = normalizedOptionalString(iconName)

        guard !trimmedName.isEmpty else {
            throw CalendarServiceError.emptyCategoryName
        }

        do {
            try await requireAuthenticatedSession()

            if let existingCategory = try await fetchCategory(categoryId: categoryId),
               existingCategory.capabilities.canChangeColor,
               !existingCategory.capabilities.canRename,
               !existingCategory.capabilities.canChangeIcon {
                guard trimmedName == existingCategory.name,
                      trimmedIconName == normalizedOptionalString(existingCategory.iconName) else {
                    throw CalendarServiceError.systemCategoryEditProtected
                }

                try await client
                    .from("calendar_categories")
                    .update(UpdateSystemCalendarCategoryPayload(colorHex: trimmedColorHex))
                    .eq("id", value: categoryId.uuidString)
                    .execute()
                #if DEBUG
                print("System calendar category color updated")
                print("category_id: \(categoryId.uuidString)")
                print("system_key: \(existingCategory.systemKey ?? "nil")")
                print("old_color_hex: \(existingCategory.colorHex)")
                print("new_color_hex: \(trimmedColorHex)")
                #endif
                return
            }

            try await client
                .rpc(
                    "update_calendar_category",
                    params: UpdateCalendarCategoryParameters(
                        targetCategoryId: categoryId,
                        categoryName: trimmedName,
                        categoryColorHex: trimmedColorHex,
                        categoryIconName: trimmedIconName
                    )
                )
                .execute()
            if let updatedCategory = try? await fetchCategory(categoryId: categoryId) {
                #if DEBUG
                print("Calendar category updated")
                print("category_id: \(categoryId.uuidString)")
                print("system_key: \(updatedCategory.systemKey ?? "nil")")
                print("new_color_hex: \(trimmedColorHex)")
                #endif
            }
        } catch let error as CalendarServiceError {
            throw error
        } catch {
            logCalendarError(error, rpcName: "update_calendar_category", categoryId: categoryId)
            if isCalendarCategoryPermissionError(error) {
                throw CalendarServiceError.categoryPermissionDenied
            }
            throw CalendarServiceError.updateCategoryFailed
        }
    }

    func deleteCategory(categoryId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()

            if let existingCategory = try await fetchCategory(categoryId: categoryId),
               !existingCategory.capabilities.canDelete {
                throw CalendarServiceError.systemCategoryProtected
            }

            try await client
                .rpc(
                    "delete_calendar_category",
                    params: CalendarCategoryIdParameters(targetCategoryId: categoryId)
                )
                .execute()
        } catch {
            logCalendarError(error, rpcName: "delete_calendar_category", categoryId: categoryId)
            if isCalendarCategoryPermissionError(error) {
                throw CalendarServiceError.categoryPermissionDenied
            }
            if let error = error as? CalendarServiceError {
                throw error
            }
            throw CalendarServiceError.deleteCategoryFailed
        }
    }

    func reorderCategories(homeId: UUID, orderedCategoryIds: [UUID]) async throws {
        do {
            try await requireAuthenticatedSession()

            try await client
                .rpc(
                    "reorder_calendar_categories",
                    params: ReorderCalendarCategoriesParameters(
                        targetHomeId: homeId,
                        orderedCategoryIds: orderedCategoryIds
                    )
                )
                .execute()
        } catch {
            logCalendarError(error, rpcName: "reorder_calendar_categories", homeId: homeId)
            if isCalendarCategoryPermissionError(error) {
                throw CalendarServiceError.categoryPermissionDenied
            }
            throw CalendarServiceError.reorderCategoriesFailed
        }
    }

    func subscribeToCalendarChanges(
        homeId: UUID,
        onChange: @escaping @MainActor () -> Void
    ) async throws -> CalendarRealtimeSubscription {
        do {
            try await requireAuthenticatedSession()

            let homeIdString = homeId.uuidString.lowercased()
            let channel = client.channel("calendar-home-\(homeIdString)")
            let events = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "calendar_events",
                filter: .eq("home_id", value: homeIdString)
            )
            let eventMembers = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "calendar_event_members"
            )
            let categories = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "calendar_categories",
                filter: .eq("home_id", value: homeIdString)
            )

            let listenerTasks = [events, eventMembers, categories].map { stream in
                Task { @MainActor in
                    for await _ in stream {
                        guard !Task.isCancelled else {
                            return
                        }

                        onChange()
                    }
                }
            }

            try await channel.subscribeWithError()
            return CalendarRealtimeSubscription(channel: channel, listenerTasks: listenerTasks)
        } catch {
            logCalendarError(error, rpcName: "calendar_realtime_subscribe", homeId: homeId)
            throw CalendarServiceError.realtimeSubscriptionFailed
        }
    }

    private func requireAuthenticatedSession() async throws {
        _ = try await client.auth.session
    }

    private func authenticatedUserId() async throws -> UUID {
        try await client.auth.session.user.id
    }

    private func normalizedEventInput(
        title: String,
        notes: String?,
        location: String?,
        startsAt: Date,
        endsAt: Date,
        timezone: String?,
        assignedUserIds: [UUID],
        recurrence: CalendarRecurrenceInput
    ) throws -> NormalizedCalendarEventInput {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            throw CalendarServiceError.emptyTitle
        }

        guard endsAt >= startsAt else {
            throw CalendarServiceError.invalidDateRange
        }

        let resolvedTimezone = normalizedTimezone(timezone)
        let uniqueAssignedUserIds = Array(Set(assignedUserIds)).sorted { $0.uuidString < $1.uuidString }
        let normalizedRecurrence = try normalizedRecurrenceInput(
            recurrence,
            startsAt: startsAt,
            timezone: resolvedTimezone
        )

        return NormalizedCalendarEventInput(
            title: trimmedTitle,
            notes: normalizedOptionalString(notes),
            location: normalizedOptionalString(location),
            timezone: resolvedTimezone,
            assignedUserIds: uniqueAssignedUserIds,
            recurrence: normalizedRecurrence
        )
    }

    private func normalizedRecurrenceInput(
        _ recurrence: CalendarRecurrenceInput,
        startsAt: Date,
        timezone: String
    ) throws -> CalendarRecurrenceInput {
        guard recurrence.interval > 0 else {
            throw CalendarServiceError.invalidRepeatInterval
        }

        if let count = recurrence.count, count <= 0 {
            throw CalendarServiceError.invalidRepeatInterval
        }

        guard recurrence.frequency != nil else {
            return CalendarRecurrenceInput()
        }

        if let endDate = recurrence.endDate {
            var recurrenceCalendar = Calendar(identifier: .gregorian)
            recurrenceCalendar.timeZone = TimeZone(identifier: timezone) ?? .autoupdatingCurrent
            let recurrenceEndDay = recurrenceCalendar.startOfDay(for: endDate)
            let eventStartDay = recurrenceCalendar.startOfDay(for: startsAt)

            guard recurrenceEndDay >= eventStartDay else {
                throw CalendarServiceError.recurrenceEndDateBeforeStart
            }
        }

        return CalendarRecurrenceInput(
            frequency: recurrence.frequency,
            interval: recurrence.interval,
            daysOfWeek: recurrence.daysOfWeek?.sorted { $0.rawValue < $1.rawValue },
            endDate: recurrence.endDate,
            count: recurrence.endDate == nil ? recurrence.count : nil
        )
    }

    private func normalizedTimezone(_ timezone: String?) -> String {
        let trimmedTimezone = timezone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedTimezone.isEmpty,
           TimeZone(identifier: trimmedTimezone) != nil {
            return trimmedTimezone
        }

        return TimeZone.autoupdatingCurrent.identifier
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func normalizedCategoryColorHex(_ value: String) throws -> String {
        var trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.hasPrefix("#") {
            trimmedValue.removeFirst()
        }

        guard trimmedValue.count == 6,
              Int(trimmedValue, radix: 16) != nil else {
            throw CalendarServiceError.invalidCategoryColor
        }

        return trimmedValue.uppercased()
    }

    private func sortedCategories(_ categories: [CalendarCategory]) -> [CalendarCategory] {
        categories.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func fetchCategory(categoryId: UUID) async throws -> CalendarCategory? {
        let categories: [CalendarCategory] = try await client
            .from("calendar_categories")
            .select()
            .eq("id", value: categoryId.uuidString)
            .limit(1)
            .execute()
            .value

        return categories.first
    }

    private func fetchMealSystemCategory(homeId: UUID) async throws -> CalendarCategory? {
        let categories: [CalendarCategory] = try await client
            .from("calendar_categories")
            .select()
            .eq("home_id", value: homeId.uuidString)
            .eq("system_key", value: CalendarSystemCategoryKey.meal.rawValue)
            .eq("is_system", value: true)
            .limit(2)
            .execute()
            .value

        if categories.count > 1 {
            #if DEBUG
            print("Duplicate meal system categories detected for Home \(homeId)")
            #endif
        }

        return categories.first
    }

    private func ensureMealSystemCategoryViaRPC(homeId: UUID) async throws -> CalendarCategory? {
        do {
            let categoryId: UUID = try await client
                .rpc(
                    "ensure_meal_calendar_category",
                    params: EnsureMealCalendarCategoryParameters(requestedHomeId: homeId)
                )
                .execute()
                .value

            return try await fetchCategory(categoryId: categoryId)
        } catch {
            logCalendarError(error, rpcName: "ensure_meal_calendar_category", homeId: homeId)
            return nil
        }
    }

    private func bootstrapMealSystemCategory(homeId: UUID) async throws {
        let userId = try await authenticatedUserId()
        let existingCategories = try await fetchCategories(homeId: homeId)
        let sortOrder = (existingCategories.map(\.sortOrder).max() ?? -1) + 1
        let payload = CreateSystemCalendarCategoryPayload(
            homeId: homeId,
            name: "Meal",
            colorHex: "A0643A",
            iconName: "fork.knife",
            sortOrder: sortOrder,
            systemKey: CalendarSystemCategoryKey.meal.rawValue,
            isSystem: true,
            createdBy: userId
        )

        do {
            try await client
                .from("calendar_categories")
                .insert(payload)
                .execute()
        } catch {
            logCalendarError(error, rpcName: "calendar_categories.insert_meal_system_category", homeId: homeId)
            throw error
        }
    }

    private func logMealCategoryResolution(homeId: UUID, categoryId: UUID, repaired: Bool) {
        #if DEBUG
        print("Meal calendar category resolved")
        print("selected_home_id: \(homeId.uuidString)")
        print("resolved_meal_category_id: \(categoryId.uuidString)")
        print("meal_category_repaired: \(repaired)")
        #endif
    }

    private func deduplicatedEvents(_ events: [CalendarEvent], sourceOperation: String) -> [CalendarEvent] {
        #if DEBUG
        let duplicateGroups = Dictionary(grouping: events, by: \.occurrenceId)
            .filter { $0.value.count > 1 }

        for (occurrenceId, duplicates) in duplicateGroups {
            for event in duplicates {
                print(
                    "Duplicate calendar occurrence received [\(sourceOperation)] occurrenceId=\(occurrenceId) eventId=\(event.eventId.uuidString) title=\(event.title) startsAt=\(event.occurrenceStartsAt)"
                )
            }
        }
        #endif

        var indexedEvents: [String: CalendarEvent] = [:]

        for event in events {
            guard let existingEvent = indexedEvents[event.occurrenceId] else {
                indexedEvents[event.occurrenceId] = event
                continue
            }

            if event.updatedAt > existingEvent.updatedAt {
                indexedEvents[event.occurrenceId] = event
            }
        }

        return Array(indexedEvents.values)
    }

    private func isCalendarCategoryPermissionError(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else {
            return false
        }

        let message = postgrestError.message.lowercased()
        return message.contains("only home owners and admins")
            && message.contains("calendar categor")
    }

    private func isOccurrenceNotPartOfSeriesError(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else {
            return false
        }

        let message = postgrestError.message.lowercased()
        return message.contains("occurrence") && message.contains("series")
    }

    private func isPermissionError(_ error: Error) -> Bool {
        guard let postgrestError = error as? PostgrestError else {
            return false
        }

        let message = postgrestError.message.lowercased()
        return message.contains("permission")
            || message.contains("not authorized")
            || message.contains("not allowed")
    }

    private func visibleMonthRange(containing month: Date) throws -> (start: Date, end: Date) {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let lastDayInMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            throw CalendarServiceError.invalidDateRange
        }

        let monthStart = calendar.startOfDay(for: monthInterval.start)
        let monthEndDay = calendar.startOfDay(for: lastDayInMonth)
        let leadingDays = daysFromStartOfWeek(to: monthStart)
        let trailingDays = daysToEndOfWeek(from: monthEndDay)

        guard let visibleStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart),
              let visibleEnd = calendar.date(byAdding: .day, value: trailingDays + 1, to: monthEndDay) else {
            throw CalendarServiceError.invalidDateRange
        }

        return (visibleStart, visibleEnd)
    }

    private func daysFromStartOfWeek(to date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func daysToEndOfWeek(from date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let endOfWeekday = ((calendar.firstWeekday + 5) % 7) + 1
        return (endOfWeekday - weekday + 7) % 7
    }

    private func logCalendarError(
        _ error: Error,
        rpcName: String,
        homeId: UUID? = nil,
        eventId: UUID? = nil,
        categoryId: UUID? = nil
    ) {
        #if DEBUG
        print("========== CALENDAR RPC FAILED ==========")
        print("rpc: \(rpcName)")
        if let homeId {
            print("home_id: \(homeId.uuidString)")
        }
        if let eventId {
            print("event_id: \(eventId.uuidString)")
        }
        if let categoryId {
            print("category_id: \(categoryId.uuidString)")
        }
        print(String(reflecting: error))

        if let postgrestError = error as? PostgrestError {
            print("PostgREST code: \(postgrestError.code ?? "")")
            print("PostgREST message: \(postgrestError.message)")
            print("PostgREST detail: \(postgrestError.detail ?? "")")
            print("PostgREST hint: \(postgrestError.hint ?? "")")
        }
        print("=========================================")
        #endif
    }
}

enum CalendarServiceError: LocalizedError, Equatable {
    case unauthenticated
    case emptyTitle
    case invalidDateRange
    case invalidRecurrenceFrequency
    case invalidRepeatInterval
    case recurrenceEndDateBeforeStart
    case occurrenceNotPartOfSeries
    case permissionDenied
    case emptyCategoryName
    case invalidCategoryColor
    case loadEventsFailed
    case loadCategoriesFailed
    case createEventFailed
    case updateEventFailed
    case deleteEventFailed
    case createCategoryFailed
    case updateCategoryFailed
    case deleteCategoryFailed
    case reorderCategoriesFailed
    case categoryPermissionDenied
    case systemCategoryEditProtected
    case systemCategoryProtected
    case mealCategoryUnavailable
    case realtimeSubscriptionFailed

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .emptyTitle:
            return "Enter an event title."
        case .invalidDateRange:
            return "The event end time must be after the start time."
        case .invalidRecurrenceFrequency:
            return "Choose a valid repeat option."
        case .invalidRepeatInterval:
            return "Choose a valid repeat interval."
        case .recurrenceEndDateBeforeStart:
            return "The repeat end date must be on or after the event start date."
        case .occurrenceNotPartOfSeries:
            return "This occurrence is no longer part of the event series."
        case .permissionDenied:
            return "You do not have permission to change this event."
        case .emptyCategoryName:
            return "Enter a category name."
        case .invalidCategoryColor:
            return "Choose a category color."
        case .loadEventsFailed:
            return "We could not load calendar events."
        case .loadCategoriesFailed:
            return "We could not load calendar categories."
        case .createEventFailed:
            return "We could not save this event."
        case .updateEventFailed:
            return "We could not update this event."
        case .deleteEventFailed:
            return "We could not delete this event."
        case .createCategoryFailed:
            return "We could not save this category."
        case .updateCategoryFailed:
            return "We could not update this category."
        case .deleteCategoryFailed:
            return "We could not delete this category."
        case .reorderCategoriesFailed:
            return "We could not reorder calendar categories."
        case .categoryPermissionDenied:
            return "You no longer have permission to manage Calendar Categories."
        case .systemCategoryEditProtected:
            return "This is a Homey system category. Its name and icon are fixed, but you can change its color."
        case .systemCategoryProtected:
            return "Homey system categories cannot be deleted."
        case .mealCategoryUnavailable:
            return "Homey could not prepare the Meal calendar category for this Home."
        case .realtimeSubscriptionFailed:
            return "We could not start live calendar updates."
        }
    }
}

private struct NormalizedCalendarEventInput {
    let title: String
    let notes: String?
    let location: String?
    let timezone: String
    let assignedUserIds: [UUID]
    let recurrence: CalendarRecurrenceInput
}

private struct CalendarSystemCategoryDefault: CaseIterable {
    let key: CalendarSystemCategoryKey
    let name: String
    let colorHex: String
    let iconName: String
    let sortOrder: Int

    static let allCases: [CalendarSystemCategoryDefault] = [
        CalendarSystemCategoryDefault(key: .family, name: "Family", colorHex: "4F7CAC", iconName: "house.fill", sortOrder: 0),
        CalendarSystemCategoryDefault(key: .school, name: "School", colorHex: "F2C14E", iconName: "graduationcap.fill", sortOrder: 1),
        CalendarSystemCategoryDefault(key: .work, name: "Work", colorHex: "577590", iconName: "briefcase.fill", sortOrder: 2),
        CalendarSystemCategoryDefault(key: .sports, name: "Sports", colorHex: "5C946E", iconName: "figure.run", sortOrder: 3),
        CalendarSystemCategoryDefault(key: .appointment, name: "Appointment", colorHex: "43AA8B", iconName: "cross.case.fill", sortOrder: 4),
        CalendarSystemCategoryDefault(key: .meal, name: "Meal", colorHex: "A0643A", iconName: "fork.knife", sortOrder: 5),
        CalendarSystemCategoryDefault(key: .chore, name: "Chore", colorHex: "90BE6D", iconName: "checklist", sortOrder: 6),
        CalendarSystemCategoryDefault(key: .birthday, name: "Birthday", colorHex: "EC6F91", iconName: "gift.fill", sortOrder: 7),
        CalendarSystemCategoryDefault(key: .holiday, name: "Holiday", colorHex: "E76F51", iconName: "party.popper.fill", sortOrder: 8),
        CalendarSystemCategoryDefault(key: .other, name: "Other", colorHex: "9E9E9E", iconName: "tag.fill", sortOrder: 9)
    ]
}

private struct CreateCalendarEventParameters: Encodable {
    let targetHomeId: UUID
    let eventTitle: String
    let eventNotes: String?
    let eventLocation: String?
    let eventStartsAt: String
    let eventEndsAt: String
    let eventIsAllDay: Bool
    let eventTimezone: String
    let eventCategoryId: UUID?
    let assignedUserIds: [UUID]
    let eventRecurrenceFrequency: CalendarRecurrenceFrequency?
    let eventRecurrenceInterval: Int
    let eventRecurrenceDaysOfWeek: [Int]?
    let eventRecurrenceEndDate: String?
    let eventRecurrenceCount: Int?

    init(
        targetHomeId: UUID,
        title: String,
        notes: String?,
        location: String?,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?,
        assignedUserIds: [UUID],
        recurrence: CalendarRecurrenceInput
    ) {
        self.targetHomeId = targetHomeId
        self.eventTitle = title
        self.eventNotes = notes
        self.eventLocation = location
        self.eventStartsAt = CalendarRPCDateFormatter.string(from: startsAt)
        self.eventEndsAt = CalendarRPCDateFormatter.string(from: endsAt)
        self.eventIsAllDay = isAllDay
        self.eventTimezone = timezone
        self.eventCategoryId = categoryId
        self.assignedUserIds = assignedUserIds
        self.eventRecurrenceFrequency = recurrence.frequency
        self.eventRecurrenceInterval = recurrence.frequency == nil ? 1 : recurrence.interval
        self.eventRecurrenceDaysOfWeek = recurrence.frequency == nil ? nil : recurrence.daysOfWeek?.map(\.rawValue)
        self.eventRecurrenceEndDate = recurrence.frequency == nil ? nil : recurrence.endDate.map {
            CalendarDateOnlyFormatter.string(from: $0, timezone: timezone)
        }
        self.eventRecurrenceCount = recurrence.frequency == nil ? nil : recurrence.count
    }

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case eventTitle = "event_title"
        case eventNotes = "event_notes"
        case eventLocation = "event_location"
        case eventStartsAt = "event_starts_at"
        case eventEndsAt = "event_ends_at"
        case eventIsAllDay = "event_is_all_day"
        case eventTimezone = "event_timezone"
        case eventCategoryId = "event_category_id"
        case assignedUserIds = "assigned_user_ids"
        case eventRecurrenceFrequency = "event_recurrence_frequency"
        case eventRecurrenceInterval = "event_recurrence_interval"
        case eventRecurrenceDaysOfWeek = "event_recurrence_days_of_week"
        case eventRecurrenceEndDate = "event_recurrence_end_date"
        case eventRecurrenceCount = "event_recurrence_count"
    }
}

private struct UpdateCalendarEventParameters: Encodable {
    let targetEventId: UUID
    let eventTitle: String
    let eventNotes: String?
    let eventLocation: String?
    let eventStartsAt: String
    let eventEndsAt: String
    let eventIsAllDay: Bool
    let eventTimezone: String
    let eventCategoryId: UUID?
    let assignedUserIds: [UUID]
    let eventRecurrenceFrequency: CalendarRecurrenceFrequency?
    let eventRecurrenceInterval: Int
    let eventRecurrenceDaysOfWeek: [Int]?
    let eventRecurrenceEndDate: String?
    let eventRecurrenceCount: Int?

    init(
        targetEventId: UUID,
        title: String,
        notes: String?,
        location: String?,
        startsAt: Date,
        endsAt: Date,
        isAllDay: Bool,
        timezone: String,
        categoryId: UUID?,
        assignedUserIds: [UUID],
        recurrence: CalendarRecurrenceInput
    ) {
        self.targetEventId = targetEventId
        self.eventTitle = title
        self.eventNotes = notes
        self.eventLocation = location
        self.eventStartsAt = CalendarRPCDateFormatter.string(from: startsAt)
        self.eventEndsAt = CalendarRPCDateFormatter.string(from: endsAt)
        self.eventIsAllDay = isAllDay
        self.eventTimezone = timezone
        self.eventCategoryId = categoryId
        self.assignedUserIds = assignedUserIds
        self.eventRecurrenceFrequency = recurrence.frequency
        self.eventRecurrenceInterval = recurrence.frequency == nil ? 1 : recurrence.interval
        self.eventRecurrenceDaysOfWeek = recurrence.frequency == nil ? nil : recurrence.daysOfWeek?.map(\.rawValue)
        self.eventRecurrenceEndDate = recurrence.frequency == nil ? nil : recurrence.endDate.map {
            CalendarDateOnlyFormatter.string(from: $0, timezone: timezone)
        }
        self.eventRecurrenceCount = recurrence.frequency == nil ? nil : recurrence.count
    }

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
        case eventTitle = "event_title"
        case eventNotes = "event_notes"
        case eventLocation = "event_location"
        case eventStartsAt = "event_starts_at"
        case eventEndsAt = "event_ends_at"
        case eventIsAllDay = "event_is_all_day"
        case eventTimezone = "event_timezone"
        case eventCategoryId = "event_category_id"
        case assignedUserIds = "assigned_user_ids"
        case eventRecurrenceFrequency = "event_recurrence_frequency"
        case eventRecurrenceInterval = "event_recurrence_interval"
        case eventRecurrenceDaysOfWeek = "event_recurrence_days_of_week"
        case eventRecurrenceEndDate = "event_recurrence_end_date"
        case eventRecurrenceCount = "event_recurrence_count"
    }
}

private struct UpdateCalendarEventOccurrenceParameters: Encodable {
    let targetEventId: UUID
    let targetOccurrenceStartsAt: String
    let eventTitle: String
    let eventStartsAt: String
    let eventEndsAt: String
    let eventTimezone: String
    let eventIsAllDay: Bool
    let eventNotes: String?
    let eventLocation: String?
    let eventCategoryId: UUID?

    init(
        targetEventId: UUID,
        targetOccurrenceStartsAt: Date,
        title: String,
        startsAt: Date,
        endsAt: Date,
        timezone: String,
        isAllDay: Bool,
        notes: String?,
        location: String?,
        categoryId: UUID?
    ) {
        self.targetEventId = targetEventId
        self.targetOccurrenceStartsAt = CalendarRPCDateFormatter.string(from: targetOccurrenceStartsAt)
        self.eventTitle = title
        self.eventStartsAt = CalendarRPCDateFormatter.string(from: startsAt)
        self.eventEndsAt = CalendarRPCDateFormatter.string(from: endsAt)
        self.eventTimezone = timezone
        self.eventIsAllDay = isAllDay
        self.eventNotes = notes
        self.eventLocation = location
        self.eventCategoryId = categoryId
    }

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
        case targetOccurrenceStartsAt = "target_occurrence_starts_at"
        case eventTitle = "event_title"
        case eventStartsAt = "event_starts_at"
        case eventEndsAt = "event_ends_at"
        case eventTimezone = "event_timezone"
        case eventIsAllDay = "event_is_all_day"
        case eventNotes = "event_notes"
        case eventLocation = "event_location"
        case eventCategoryId = "event_category_id"
    }
}

private struct DeleteCalendarEventOccurrenceParameters: Encodable {
    let targetEventId: UUID
    let targetOccurrenceStartsAt: String

    init(targetEventId: UUID, targetOccurrenceStartsAt: Date) {
        self.targetEventId = targetEventId
        self.targetOccurrenceStartsAt = CalendarRPCDateFormatter.string(from: targetOccurrenceStartsAt)
    }

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
        case targetOccurrenceStartsAt = "target_occurrence_starts_at"
    }
}

private struct CalendarEventIdParameters: Encodable {
    let targetEventId: UUID

    enum CodingKeys: String, CodingKey {
        case targetEventId = "target_event_id"
    }
}

private struct GetCalendarEventsParameters: Encodable {
    let targetHomeId: UUID
    let rangeStart: String
    let rangeEnd: String

    init(targetHomeId: UUID, rangeStart: Date, rangeEnd: Date) {
        self.targetHomeId = targetHomeId
        self.rangeStart = CalendarRPCDateFormatter.string(from: rangeStart)
        self.rangeEnd = CalendarRPCDateFormatter.string(from: rangeEnd)
    }

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
    }
}

private struct CreateCalendarCategoryParameters: Encodable {
    let targetHomeId: UUID
    let categoryName: String
    let categoryColorHex: String
    let categoryIconName: String?

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case categoryName = "category_name"
        case categoryColorHex = "category_color_hex"
        case categoryIconName = "category_icon_name"
    }
}

private struct CreateSystemCalendarCategoryPayload: Encodable {
    let homeId: UUID
    let name: String
    let colorHex: String
    let iconName: String
    let sortOrder: Int
    let systemKey: String
    let isSystem: Bool
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case systemKey = "system_key"
        case isSystem = "is_system"
        case createdBy = "created_by"
    }
}

private struct UpdateSystemCalendarCategoryPayload: Encodable {
    let colorHex: String

    enum CodingKeys: String, CodingKey {
        case colorHex = "color_hex"
    }
}

private struct GetCalendarCategoriesParameters: Encodable {
    let targetHomeId: UUID

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
    }
}

private struct EnsureMealCalendarCategoryParameters: Encodable {
    let requestedHomeId: UUID

    enum CodingKeys: String, CodingKey {
        case requestedHomeId = "requested_home_id"
    }
}

private struct UpdateCalendarCategoryParameters: Encodable {
    let targetCategoryId: UUID
    let categoryName: String
    let categoryColorHex: String
    let categoryIconName: String?

    enum CodingKeys: String, CodingKey {
        case targetCategoryId = "target_category_id"
        case categoryName = "category_name"
        case categoryColorHex = "category_color_hex"
        case categoryIconName = "category_icon_name"
    }
}

private struct CalendarCategoryIdParameters: Encodable {
    let targetCategoryId: UUID

    enum CodingKeys: String, CodingKey {
        case targetCategoryId = "target_category_id"
    }
}

private struct ReorderCalendarCategoriesParameters: Encodable {
    let targetHomeId: UUID
    let orderedCategoryIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case targetHomeId = "target_home_id"
        case orderedCategoryIds = "ordered_category_ids"
    }
}

private enum CalendarRPCDateFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
