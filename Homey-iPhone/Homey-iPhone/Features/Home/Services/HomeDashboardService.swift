import Foundation
import Supabase

struct HomeDashboardService {
    private let client = SupabaseManager.shared.client

    func load(home: HomeSummary, role: HomeMemberRole?) async -> HomeDashboardSnapshot {
        var snapshot = HomeDashboardSnapshot.empty
        let ranges = dateRanges(timezone: home.timezone, weekStartsOn: home.weekStartsOn)

        if role == .owner || role == .admin {
            do {
                let count = try await pendingApprovalCount(homeID: home.id)
                if count > 0 { snapshot.attentionItems.append(.init(id: "approvals", title: "\(count) Chore\(count == 1 ? "" : "s") Awaiting Approval", detail: "Review completed work", systemImage: "checkmark.seal.fill", destination: .chores)) }
            } catch { snapshot.failedSections.insert(.chores); log(error, section: "chore approvals") }

            do {
                let count = try await pendingRewardCount(homeID: home.id)
                if count > 0 { snapshot.attentionItems.append(.init(id: "rewards", title: "\(count) Reward Request\(count == 1 ? "" : "s")", detail: "Ready for fulfillment", systemImage: "gift.fill", destination: .chores)) }
            } catch { snapshot.failedSections.insert(.rewards); log(error, section: "reward requests") }
        }

        do {
            let occurrences: [ChoreOccurrenceRow] = try await client.from("chore_occurrences").select("id, due_at, status").eq("home_id", value: home.id.uuidString).gte("due_at", value: ranges.todayStart).lt("due_at", value: ranges.tomorrowStart).execute().value
            snapshot.choresDueToday = occurrences.filter { !["completed", "skipped", "cancelled"].contains($0.status) }.count
        } catch { snapshot.failedSections.insert(.chores); log(error, section: "today's chores") }

        var weekEvents: [DashboardEventRow] = []
        do {
            let upcoming = try await fetchEvents(homeID: home.id, start: ranges.now, end: ranges.weekEnd)
            weekEvents = try await fetchEvents(homeID: home.id, start: ranges.weekStart, end: ranges.weekEnd)
            snapshot.upcomingEventCount = upcoming.count
            snapshot.upcomingEvents = upcoming.prefix(5).map {
                HomeUpcomingItem(id: $0.occurrenceID, title: $0.title, detail: eventDetail($0, timezone: ranges.calendar.timeZone), colorHex: $0.categoryColorHex, destination: .calendar)
            }
        } catch { snapshot.failedSections.insert(.calendar); log(error, section: "calendar") }

        if snapshot.failedSections.contains(.calendar) {
            snapshot.failedSections.insert(.meals)
        } else {
            do {
                let details = try await mealDetails()
                let mealEventIDs = Set(details.map(\.calendarEventID))
                snapshot.upcomingEvents.removeAll { item in weekEvents.first(where: { $0.occurrenceID == item.id }).map { mealEventIDs.contains($0.eventID) } ?? false }
                let eventByID: [UUID: DashboardEventRow] = Dictionary(uniqueKeysWithValues: weekEvents.map { ($0.eventID, $0) })
                let dinners = details.filter { $0.mealType == "dinner" && eventByID[$0.calendarEventID] != nil }
                snapshot.dinnersPlanned = Set(dinners.map { $0.calendarEventID }).count
                snapshot.tonightMeal = dinners.compactMap { eventByID[$0.calendarEventID] }.first { ranges.calendar.isDate($0.occurrenceStartsAt, inSameDayAs: ranges.now) }?.title
                if let dinnersPlanned = snapshot.dinnersPlanned, dinnersPlanned < 7, role == .owner || role == .admin {
                    let remaining = 7 - dinnersPlanned
                    snapshot.attentionItems.append(.init(id: "meals", title: "\(remaining) Dinner\(remaining == 1 ? "" : "s") Still Need Planning", detail: "Complete this week's meal plan", systemImage: "fork.knife", destination: .meals))
                }
            } catch { snapshot.failedSections.insert(.meals); log(error, section: "meals") }
        }
        return snapshot
    }

    private func pendingApprovalCount(homeID: UUID) async throws -> Int {
        let occurrences: [OccurrenceIDRow] = try await client.from("chore_occurrences").select("id").eq("home_id", value: homeID.uuidString).execute().value
        let homeIDs = Set(occurrences.map(\.id))
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
        let rows: [DashboardEventRow] = try await client.rpc("get_calendar_events", params: CalendarRangeParameters(targetHomeID: homeID, rangeStart: start, rangeEnd: end)).execute().value
        return rows.filter { $0.occurrenceEndsAt > start }.sorted { $0.occurrenceStartsAt < $1.occurrenceStartsAt }
    }

    private func mealDetails() async throws -> [MealDetailRow] {
        try await client.from("meal_event_details").select("calendar_event_id, meal_type").execute().value
    }

    private func eventDetail(_ event: DashboardEventRow, timezone: TimeZone) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "EEE, h:mm a"
        return formatter.string(from: event.occurrenceStartsAt)
    }

    private func dateRanges(timezone: String?, weekStartsOn: Int) -> DashboardDateRanges {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        calendar.firstWeekday = weekStartsOn == 2 ? 2 : 1
        let now = Date(), today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        return DashboardDateRanges(now: now, todayStart: today, tomorrowStart: tomorrow, weekStart: week?.start ?? today, weekEnd: week?.end ?? tomorrow, calendar: calendar)
    }

    private func log(_ error: Error, section: String) {
        #if DEBUG
        print("[Home Dashboard] Failed to load \(section): \(String(reflecting: error))")
        #endif
    }
}

private struct DashboardDateRanges { let now, todayStart, tomorrowStart, weekStart, weekEnd: Date; let calendar: Calendar }
private struct IDRow: Decodable { let id: UUID }
private struct OccurrenceIDRow: Decodable { let id: UUID }
private struct SubmissionRow: Decodable { let occurrenceID: UUID; enum CodingKeys: String, CodingKey { case occurrenceID = "occurrence_id" } }
private struct AssigneeRow: Decodable { let occurrenceID: UUID; enum CodingKeys: String, CodingKey { case occurrenceID = "occurrence_id" } }
private struct ChoreOccurrenceRow: Decodable { let id: UUID; let dueAt: Date; let status: String; enum CodingKeys: String, CodingKey { case id, status; case dueAt = "due_at" } }
private struct MealDetailRow: Decodable { let calendarEventID: UUID; let mealType: String; enum CodingKeys: String, CodingKey { case calendarEventID = "calendar_event_id"; case mealType = "meal_type" } }
private struct CalendarRangeParameters: Encodable { let targetHomeID: UUID; let rangeStart, rangeEnd: Date; enum CodingKeys: String, CodingKey { case targetHomeID = "target_home_id"; case rangeStart = "range_start"; case rangeEnd = "range_end" } }
private struct DashboardEventRow: Decodable {
    let eventID: UUID; let occurrenceID: String; let occurrenceStartsAt, startsAt, endsAt: Date; let title: String; let isAllDay: Bool; let categoryColorHex: String?
    var occurrenceEndsAt: Date { occurrenceStartsAt.addingTimeInterval(endsAt.timeIntervalSince(startsAt)) }
    enum CodingKeys: String, CodingKey { case eventID = "event_id"; case occurrenceID = "occurrence_id"; case occurrenceStartsAt = "occurrence_starts_at"; case startsAt = "starts_at"; case endsAt = "ends_at"; case title; case isAllDay = "is_all_day"; case categoryColorHex = "category_color_hex" }
}
