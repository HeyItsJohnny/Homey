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
            let result = try await PhoneCalendarService().fetchUserEvents(
                homeID: home.id,
                start: ranges.todayStart,
                end: ranges.tomorrowStart
            )
            snapshot.todayEvents = result.events.map {
                    DashboardTodayEvent(
                        id: $0.occurrenceID,
                        title: $0.title,
                        startsAt: $0.occurrenceStartsAt,
                        isAllDay: $0.isAllDay,
                        location: $0.location?.trimmedNonEmpty,
                        colorHex: $0.categoryColorHex
                    )
                }
            snapshot.calendarDataLoaded = true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            snapshot.failedSections.insert(.calendar)
            log(error, section: "today's events")
        }

        do {
            let localToday = MealsViewModel.localDate(ranges.todayStart, home: home)
            let mealsService = MealsService()
            let entries = try await mealsService.mealPlanEntries(
                homeID: home.id,
                startDate: localToday,
                endDate: localToday
            )
            let todayEntries = entries.filter {
                $0.plannedDate == localToday && [.breakfast, .lunch, .dinner].contains($0.mealType)
            }.sorted(by: mealEntryPrecedes)
            let recipes = todayEntries.isEmpty ? [] : try await mealsService.homeRecipes(homeId: home.id)
            let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

            snapshot.todayMeals = todayEntries.map { entry in
                let meal = recipesByID[entry.mealID]
                return DashboardTodayMeal(
                    id: entry.id.uuidString,
                    mealID: entry.mealID,
                    title: meal?.name ?? "Recipe unavailable",
                    mealType: entry.mealType,
                    photoPath: meal?.primaryPhotoPath
                )
            }

            snapshot.mealDataLoaded = true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            snapshot.failedSections.insert(.meals)
            log(error, section: "today's meals")
        }

        do {
            let weekEnd = ranges.calendar.date(byAdding: .day, value: -1, to: ranges.weekEnd) ?? ranges.weekStart
            let entries = try await MealsService().mealPlanEntries(
                homeID: home.id,
                startDate: MealsViewModel.localDate(ranges.weekStart, home: home),
                endDate: MealsViewModel.localDate(weekEnd, home: home)
            )
            snapshot.mealCounts = DashboardMealCounts(
                breakfast: entries.filter { $0.mealType == .breakfast }.count,
                lunch: entries.filter { $0.mealType == .lunch }.count,
                dinner: entries.filter { $0.mealType == .dinner }.count
            )
            snapshot.mealCountsDataLoaded = true

            if role == .owner || role == .admin {
                let dinnerCount = entries.filter { $0.mealType == .dinner }.count
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
            snapshot.failedSections.insert(.mealSummary)
            log(error, section: "weekly meal summary")
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

    private func mealEntryPrecedes(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool {
        let order: [MealType: Int] = [.breakfast: 0, .lunch: 1, .dinner: 2]
        let lhsOrder = order[lhs.mealType] ?? 3
        let rhsOrder = order[rhs.mealType] ?? 3
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.id.uuidString < rhs.id.uuidString
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
private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
