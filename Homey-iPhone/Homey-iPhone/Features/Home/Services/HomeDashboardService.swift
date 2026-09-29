import Foundation
import Supabase

struct HomeDashboardService {
    private let client = SupabaseManager.shared.client

    func load(home: HomeSummary, currentUserID: UUID?, role: HomeMemberRole?) async throws -> HomeDashboardSnapshot {
        var snapshot = HomeDashboardSnapshot.empty
        let ranges = dateRanges(timezone: home.timezone, weekStartsOn: home.weekStartsOn)

        if role == .owner || role == .admin {
            do {
                let count = try await pendingApprovalCount(homeID: home.id)
                if count > 0 {
                    snapshot.attentionItems.append(.init(
                        id: "approvals",
                        title: "\(count) Chore\(count == 1 ? "" : "s") Awaiting Approval",
                        detail: "Review completed work",
                        systemImage: "checkmark.seal.fill",
                        destination: .chores
                    ))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                snapshot.failedSections.insert(.approvals)
                log(error, section: "chore approvals")
            }

            do {
                let count = try await pendingRewardCount(homeID: home.id)
                if count > 0 {
                    snapshot.attentionItems.append(.init(
                        id: "rewards",
                        title: "\(count) Reward Request\(count == 1 ? "" : "s")",
                        detail: "Ready for fulfillment",
                        systemImage: "gift.fill",
                        destination: .chores
                    ))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                snapshot.failedSections.insert(.rewards)
                log(error, section: "reward requests")
            }
        }

        if let role, (role != .member || currentUserID != nil) {
            snapshot.choreRoleResolved = true
            do {
                snapshot.todayChores = try await todayChores(
                    homeID: home.id,
                    localDate: localDateString(ranges.todayStart, calendar: ranges.calendar),
                    currentUserID: currentUserID,
                    role: role
                )
                snapshot.choreDataLoaded = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                snapshot.failedSections.insert(.chores)
                log(error, section: "today's chores")
            }
        } else {
            snapshot.failedSections.insert(.chores)
        }

        do {
            let weekEvents = try await fetchEvents(homeID: home.id, start: ranges.weekStart, end: ranges.weekEnd)
            let integrationMetadata = try await PhoneCalendarService().fetchIntegrationMetadata(
                homeID: home.id,
                eventIDs: Set(weekEvents.map(\.eventID))
            )
            let details = try await mealDetails(eventIDs: Set(weekEvents.map(\.eventID)))
            let detailsByEventID = Dictionary(uniqueKeysWithValues: details.map { ($0.calendarEventID, $0) })
            let integrationCategoryIDs = PhoneCalendarVisibility.excludedIntegrationCategoryIDs(from: integrationMetadata.categories)
            let todayEvents = weekEvents.filter {
                $0.occurrenceStartsAt < ranges.tomorrowStart && $0.occurrenceEndsAt > ranges.todayStart
            }

            snapshot.todayEvents = todayEvents
                .filter {
                    !integrationMetadata.linkedEventIDs.contains($0.eventID)
                        && !($0.categoryID.map(integrationCategoryIDs.contains) ?? false)
                }
                .map {
                    DashboardTodayEvent(
                        id: $0.occurrenceID,
                        title: $0.title,
                        startsAt: $0.occurrenceStartsAt,
                        isAllDay: $0.isAllDay,
                        location: $0.location?.trimmedNonEmpty,
                        colorHex: $0.categoryColorHex
                    )
                }

            let todayMealEvents = todayEvents.compactMap { event -> (DashboardEventRow, DashboardMealDetailRow)? in
                guard let detail = detailsByEventID[event.eventID], [.breakfast, .lunch, .dinner].contains(detail.mealType) else { return nil }
                return (event, detail)
            }
            let meals = try await meals(homeID: home.id, ids: Set(todayMealEvents.map { $0.1.mealID }))
            let mealsByID = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
            snapshot.todayMeals = todayMealEvents.map { event, detail in
                let meal = mealsByID[detail.mealID]
                return DashboardTodayMeal(
                    id: event.occurrenceID,
                    mealID: detail.mealID,
                    title: meal?.name ?? event.title,
                    mealType: detail.mealType,
                    photoPath: meal?.primaryPhotoPath
                )
            }.sorted { lhs, rhs in
                let order: [MealType: Int] = [.breakfast: 0, .lunch: 1, .dinner: 2]
                let lhsOrder = order[lhs.mealType] ?? 3
                let rhsOrder = order[rhs.mealType] ?? 3
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            snapshot.mealCounts = DashboardMealCounts(
                breakfast: snapshot.todayMeals.filter { $0.mealType == .breakfast }.count,
                lunch: snapshot.todayMeals.filter { $0.mealType == .lunch }.count,
                dinner: snapshot.todayMeals.filter { $0.mealType == .dinner }.count
            )
            snapshot.calendarDataLoaded = true
            snapshot.mealDataLoaded = true

            if role == .owner || role == .admin {
                let dinnerCount = weekEvents.filter { detailsByEventID[$0.eventID]?.mealType == .dinner }.count
                if dinnerCount < 7 {
                    let remaining = 7 - dinnerCount
                    snapshot.attentionItems.append(.init(
                        id: "meals",
                        title: "\(remaining) Dinner\(remaining == 1 ? "" : "s") Still Need Planning",
                        detail: "Complete this week's meal plan",
                        systemImage: "fork.knife",
                        destination: .meals
                    ))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            snapshot.failedSections.insert(.calendar)
            snapshot.failedSections.insert(.meals)
            log(error, section: "calendar and meals")
        }

        return snapshot
    }

    private func todayChores(
        homeID: UUID,
        localDate: String,
        currentUserID: UUID?,
        role: HomeMemberRole
    ) async throws -> [DashboardTodayChore] {
        let occurrences: [PhoneChoreOccurrence] = try await client
            .from("chore_occurrences")
            .select("id, template_id, assignment_mode, points_value_snapshot, requires_approval_snapshot, due_local_date, status, claimed_by")
            .eq("home_id", value: homeID.uuidString)
            .eq("due_local_date", value: localDate)
            .execute().value
        let activeOccurrences = occurrences.filter { ![.skipped, .cancelled].contains($0.status) }
        guard !activeOccurrences.isEmpty else { return [] }

        let occurrenceIDs = Set(activeOccurrences.map(\.id))
        let templateIDs = Set(activeOccurrences.map(\.templateID))
        let members: [DashboardChoreMemberRow] = try await client
            .rpc("get_home_members", params: DashboardHomeMembersParameters(homeID: homeID))
            .execute().value

        async let templatesRequest: [PhoneChoreTemplate] = client
            .from("chore_templates")
            .select("id, room_id, title, description, instructions, points_value")
            .eq("home_id", value: homeID.uuidString)
            .in("id", values: templateIDs.map(\.uuidString))
            .execute().value
        async let assigneesRequest: [PhoneOccurrenceAssignee] = client
            .from("chore_occurrence_assignees")
            .select("occurrence_id, user_id, status")
            .in("occurrence_id", values: occurrenceIDs.map(\.uuidString))
            .execute().value
        async let roomsRequest: [DashboardChoreRoomRow] = client
            .from("chore_rooms")
            .select("id, name")
            .eq("home_id", value: homeID.uuidString)
            .execute().value

        let (templates, assignees, rooms) = try await (templatesRequest, assigneesRequest, roomsRequest)
        let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        let roomsByID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.name) })
        let memberNamesByID = Dictionary(uniqueKeysWithValues: members.map { ($0.userID, $0.displayName) })
        let assigneesByOccurrence = Dictionary(grouping: assignees, by: \.occurrenceID)

        return activeOccurrences.compactMap { occurrence in
            let assignedRows = assigneesByOccurrence[occurrence.id] ?? []
            if role == .member {
                guard let currentUserID,
                      occurrence.claimedBy == currentUserID || assignedRows.contains(where: { $0.userID == currentUserID })
                else { return nil }
            }
            guard let template = templatesByID[occurrence.templateID] else { return nil }
            let assigneeIDs = Set(assignedRows.map(\.userID) + [occurrence.claimedBy].compactMap { $0 })
            let assigneeNames = assigneeIDs.compactMap { memberNamesByID[$0] }.sorted()
            let roomName = template.roomID.flatMap { roomsByID[$0] }?.trimmedNonEmpty
            return DashboardTodayChore(
                id: occurrence.id,
                title: template.title,
                roomName: roomName,
                assigneeNames: assigneeNames,
                status: occurrence.status
            )
        }.sorted { lhs, rhs in
            if choreStatusOrder(lhs.status) != choreStatusOrder(rhs.status) {
                return choreStatusOrder(lhs.status) < choreStatusOrder(rhs.status)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func pendingApprovalCount(homeID: UUID) async throws -> Int {
        let occurrences: [OccurrenceIDRow] = try await client.from("chore_occurrences").select("id").eq("home_id", value: homeID.uuidString).execute().value
        let homeIDs = Set(occurrences.map(\.id))
        guard !homeIDs.isEmpty else { return 0 }
        let submissions: [SubmissionRow] = try await client.from("chore_submissions").select("occurrence_id").eq("status", value: "pending").execute().value
        let pendingIDs = Set(submissions.map(\.occurrenceID)).intersection(homeIDs)
        guard !pendingIDs.isEmpty else { return 0 }
        let assignees: [AssigneeRow] = try await client.from("chore_occurrence_assignees").select("occurrence_id").eq("status", value: "awaiting_approval").execute().value
        return Set(assignees.map(\.occurrenceID)).intersection(pendingIDs).count
    }

    private func pendingRewardCount(homeID: UUID) async throws -> Int {
        let rows: [IDRow] = try await client.from("chore_reward_redemptions").select("id").eq("home_id", value: homeID.uuidString).eq("status", value: "pending").execute().value
        return rows.count
    }

    private func fetchEvents(homeID: UUID, start: Date, end: Date) async throws -> [DashboardEventRow] {
        let rows: [DashboardEventRow] = try await client.rpc(
            "get_calendar_events",
            params: CalendarRangeParameters(targetHomeID: homeID, rangeStart: start, rangeEnd: end)
        ).execute().value
        return rows.filter { $0.occurrenceEndsAt > start }.sorted { $0.occurrenceStartsAt < $1.occurrenceStartsAt }
    }

    private func mealDetails(eventIDs: Set<UUID>) async throws -> [DashboardMealDetailRow] {
        guard !eventIDs.isEmpty else { return [] }
        return try await client.from("meal_event_details")
            .select("calendar_event_id, meal_id, meal_type")
            .in("calendar_event_id", values: eventIDs.map(\.uuidString))
            .execute().value
    }

    private func meals(homeID: UUID, ids: Set<UUID>) async throws -> [DashboardMealRow] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("meals")
            .select("id, name, primary_photo_path")
            .eq("home_id", value: homeID.uuidString)
            .in("id", values: ids.map(\.uuidString))
            .execute().value
    }

    private func choreStatusOrder(_ status: PhoneChoreOccurrenceStatus) -> Int {
        switch status {
        case .needsRedo: 0
        case .inProgress: 1
        case .notStarted: 2
        case .awaitingApproval: 3
        case .completed: 4
        case .skipped, .cancelled: 5
        }
    }

    private func localDateString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func dateRanges(timezone: String?, weekStartsOn: Int) -> DashboardDateRanges {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        calendar.firstWeekday = weekStartsOn == 2 ? 2 : 1
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        return DashboardDateRanges(
            todayStart: today,
            tomorrowStart: tomorrow,
            weekStart: week?.start ?? today,
            weekEnd: week?.end ?? tomorrow,
            calendar: calendar
        )
    }

    private func log(_ error: Error, section: String) {
        #if DEBUG
        print("[Home Dashboard] Failed to load \(section): \(String(reflecting: error))")
        #endif
    }
}

private struct DashboardDateRanges {
    let todayStart, tomorrowStart, weekStart, weekEnd: Date
    let calendar: Calendar
}

private struct IDRow: Decodable { let id: UUID }
private struct OccurrenceIDRow: Decodable { let id: UUID }
private struct SubmissionRow: Decodable {
    let occurrenceID: UUID
    enum CodingKeys: String, CodingKey { case occurrenceID = "occurrence_id" }
}
private struct AssigneeRow: Decodable {
    let occurrenceID: UUID
    enum CodingKeys: String, CodingKey { case occurrenceID = "occurrence_id" }
}
private struct DashboardMealDetailRow: Decodable {
    let calendarEventID: UUID
    let mealID: UUID
    let mealType: MealType
    enum CodingKeys: String, CodingKey {
        case calendarEventID = "calendar_event_id"
        case mealID = "meal_id"
        case mealType = "meal_type"
    }
}
private struct DashboardMealRow: Decodable {
    let id: UUID
    let name: String
    let primaryPhotoPath: String?
    enum CodingKeys: String, CodingKey { case id, name; case primaryPhotoPath = "primary_photo_path" }
}
private struct DashboardChoreRoomRow: Decodable { let id: UUID; let name: String }
private struct DashboardChoreMemberRow: Decodable {
    let userID: UUID
    let firstName: String?
    let lastName: String?
    let profileDisplayName: String?
    let email: String?
    var displayName: String {
        let preferred = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }
        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return email?.split(separator: "@").first.map(String.init) ?? "Home Member"
    }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case profileDisplayName = "display_name"
        case email
    }
}
private struct DashboardHomeMembersParameters: Encodable {
    let homeID: UUID
    enum CodingKeys: String, CodingKey { case homeID = "target_home_id" }
}
private struct CalendarRangeParameters: Encodable {
    let targetHomeID: UUID
    let rangeStart, rangeEnd: Date
    enum CodingKeys: String, CodingKey {
        case targetHomeID = "target_home_id"
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
    }
}
private struct DashboardEventRow: Decodable {
    let eventID: UUID
    let occurrenceID: String
    let occurrenceStartsAt, startsAt, endsAt: Date
    let title: String
    let categoryID: UUID?
    let isAllDay: Bool
    let location: String?
    let categoryColorHex: String?
    var occurrenceEndsAt: Date { occurrenceStartsAt.addingTimeInterval(endsAt.timeIntervalSince(startsAt)) }
    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case occurrenceID = "occurrence_id"
        case occurrenceStartsAt = "occurrence_starts_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case title, location
        case categoryID = "category_id"
        case isAllDay = "is_all_day"
        case categoryColorHex = "category_color_hex"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
