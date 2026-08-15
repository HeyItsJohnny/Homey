import Foundation
import PostgREST
import Supabase

struct ChoresBadgeCountResult: Sendable {
    let count: Int
    let occurrenceIds: [UUID]
}

struct ChorePendingApprovalQueueItem: Sendable {
    let occurrence: ChoreOccurrence
    let submission: ChoreSubmission
}

@MainActor
final class ChoresRepository {
    static let defaultGenerationWindowDays = 90

    private let client: SupabaseClient

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseManager.shared.client
    }

    // MARK: - Lookups

    func fetchCategories(homeId: UUID) async throws -> [ChoreCategory] {
        do {
            try await requireAuthenticatedSession()
            let categories: [ChoreCategory] = try await client
                .from("chore_categories")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            return categories
        } catch {
            logChoreError(error, operation: "chore_categories.select", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchRooms(homeId: UUID) async throws -> [ChoreRoom] {
        do {
            try await requireAuthenticatedSession()
            let rooms: [ChoreRoom] = try await client
                .from("chore_rooms")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            return rooms
        } catch {
            logChoreError(error, operation: "chore_rooms.select", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func createCategory(homeId: UUID, name: String, colorHex: String? = nil, iconName: String? = nil, sortOrder: Int = 0) async throws -> UUID {
        let payload = ChoreCategoryMutationPayload(
            homeId: homeId,
            name: normalizedRequiredString(name),
            colorHex: normalizedOptionalString(colorHex),
            iconName: normalizedOptionalString(iconName),
            sortOrder: sortOrder,
            archivedAt: nil
        )
        guard !payload.name.isEmpty else { throw ChoreRepositoryError.saveFailed }

        do {
            try await requireAuthenticatedSession()
            let created: ChoreMutationIdResponse = try await client
                .from("chore_categories")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value
            return created.id
        } catch {
            logChoreError(error, operation: "chore_categories.insert", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func updateCategory(categoryId: UUID, name: String, colorHex: String? = nil, iconName: String? = nil, sortOrder: Int) async throws {
        let payload = ChoreCategoryUpdatePayload(
            name: normalizedRequiredString(name),
            colorHex: normalizedOptionalString(colorHex),
            iconName: normalizedOptionalString(iconName),
            sortOrder: sortOrder
        )
        guard !payload.name.isEmpty else { throw ChoreRepositoryError.saveFailed }

        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_categories")
                .update(payload)
                .eq("id", value: categoryId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_categories.update", categoryId: categoryId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func archiveCategory(categoryId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_categories")
                .update(ArchivePayload(archivedAt: Date()))
                .eq("id", value: categoryId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_categories.archive", categoryId: categoryId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func createRoom(homeId: UUID, name: String, sortOrder: Int = 0) async throws -> UUID {
        let payload = ChoreRoomMutationPayload(homeId: homeId, name: normalizedRequiredString(name), sortOrder: sortOrder, archivedAt: nil)
        guard !payload.name.isEmpty else { throw ChoreRepositoryError.saveFailed }

        do {
            try await requireAuthenticatedSession()
            let created: ChoreMutationIdResponse = try await client
                .from("chore_rooms")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value
            return created.id
        } catch {
            logChoreError(error, operation: "chore_rooms.insert", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func updateRoom(roomId: UUID, name: String, sortOrder: Int) async throws {
        let payload = ChoreRoomUpdatePayload(name: normalizedRequiredString(name), sortOrder: sortOrder)
        guard !payload.name.isEmpty else { throw ChoreRepositoryError.saveFailed }

        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_rooms")
                .update(payload)
                .eq("id", value: roomId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_rooms.update", categoryId: roomId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func archiveRoom(roomId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_rooms")
                .update(ArchivePayload(archivedAt: Date()))
                .eq("id", value: roomId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_rooms.archive", categoryId: roomId)
            throw ChoreRepositoryError.map(error)
        }
    }

    // MARK: - Rewards

    func fetchRewards(homeId: UUID, currentRole: HomeMemberRole?) async throws -> [ChoreReward] {
        do {
            try await requireAuthenticatedSession()

            if currentRole == .owner || currentRole == .admin {
                let rewards: [ChoreReward] = try await client
                    .from("chore_rewards")
                    .select()
                    .eq("home_id", value: homeId.uuidString)
                    .eq("is_archived", value: false)
                    .order("name", ascending: true)
                    .execute()
                    .value
                return rewards
            }

            let rewards: [ChoreReward] = try await client
                .from("chore_rewards")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("is_archived", value: false)
                .eq("is_active", value: true)
                .order("name", ascending: true)
                .execute()
                .value
            return rewards
        } catch {
            logChoreError(error, operation: "chore_rewards.select", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func createReward(
        homeId: UUID,
        name: String,
        description: String?,
        pointCost: Int,
        isActive: Bool,
        currentRole: HomeMemberRole?
    ) async throws -> UUID {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        let userId = try await authenticatedUserId()
        let payload = ChoreRewardMutationPayload(
            homeId: homeId,
            name: normalizedRequiredString(name),
            description: normalizedOptionalString(description),
            pointCost: pointCost,
            isActive: isActive,
            isArchived: false,
            createdBy: userId
        )
        guard !payload.name.isEmpty, payload.pointCost > 0 else {
            throw ChoreRepositoryError.saveFailed
        }

        do {
            try await requireAuthenticatedSession()
            let created: ChoreMutationIdResponse = try await client
                .from("chore_rewards")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value
            return created.id
        } catch {
            logChoreError(error, operation: "chore_rewards.insert", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func updateReward(
        rewardId: UUID,
        name: String,
        description: String?,
        pointCost: Int,
        isActive: Bool,
        currentRole: HomeMemberRole?
    ) async throws {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        let payload = ChoreRewardUpdatePayload(
            name: normalizedRequiredString(name),
            description: normalizedOptionalString(description),
            pointCost: pointCost,
            isActive: isActive
        )
        guard !payload.name.isEmpty, payload.pointCost > 0 else {
            throw ChoreRepositoryError.saveFailed
        }

        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_rewards")
                .update(payload)
                .eq("id", value: rewardId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_rewards.update", categoryId: rewardId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func archiveReward(rewardId: UUID, currentRole: HomeMemberRole?) async throws {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_rewards")
                .update(ArchiveRewardPayload())
                .eq("id", value: rewardId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_rewards.archive", categoryId: rewardId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func redeemReward(homeId: UUID, rewardId: UUID) async throws -> UUID {
        do {
            try await requireAuthenticatedSession()
            let redemptionId: UUID = try await client
                .rpc(
                    "redeem_chore_reward",
                    params: RedeemChoreRewardRPCParameters(homeId: homeId, rewardId: rewardId)
                )
                .execute()
                .value
            return redemptionId
        } catch {
            logChoreError(error, operation: "redeem_chore_reward", homeId: homeId, categoryId: rewardId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchPendingRewardRedemptions(homeId: UUID, currentRole: HomeMemberRole?) async throws -> [ChoreRewardRedemption] {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let redemptions: [ChoreRewardRedemption] = try await client
                .from("chore_reward_redemptions")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("status", value: ChoreRewardRedemptionStatus.pending.rawValue)
                .order("requested_at", ascending: true)
                .execute()
                .value
            return redemptions
        } catch {
            logChoreError(error, operation: "chore_reward_redemptions.select_pending", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchMyPendingRewardRedemptions(homeId: UUID) async throws -> [ChoreRewardRedemption] {
        let userId = try await authenticatedUserId()

        do {
            try await requireAuthenticatedSession()
            let redemptions: [ChoreRewardRedemption] = try await client
                .from("chore_reward_redemptions")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: ChoreRewardRedemptionStatus.pending.rawValue)
                .order("requested_at", ascending: false)
                .execute()
                .value
            return redemptions
        } catch {
            logChoreError(error, operation: "chore_reward_redemptions.select_my_pending", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchMyPendingRewardCount(homeId: UUID) async throws -> Int {
        try await fetchMyPendingRewardRedemptions(homeId: homeId).count
    }

    func fetchPendingRewardRedemptionCount(homeId: UUID) async throws -> Int {
        try await fetchPendingRewardRedemptions(homeId: homeId, currentRole: .admin).count
    }

    func fetchMyRewardRedemptions(homeId: UUID, limit: Int, offset: Int) async throws -> [ChoreRewardRedemption] {
        let userId = try await authenticatedUserId()
        return try await fetchRewardRedemptions(homeId: homeId, userId: userId, limit: limit, offset: offset, currentRole: .member)
    }

    func fetchRewardRedemptions(
        homeId: UUID,
        userId: UUID,
        limit: Int,
        offset: Int,
        currentRole: HomeMemberRole?
    ) async throws -> [ChoreRewardRedemption] {
        let authenticatedUserId = try await authenticatedUserId()
        guard authenticatedUserId == userId || currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let redemptions: [ChoreRewardRedemption] = try await client
                .from("chore_reward_redemptions")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .order("requested_at", ascending: false)
                .order("id", ascending: false)
                .range(from: offset, to: offset + max(limit, 1) - 1)
                .execute()
                .value
            return redemptions
        } catch {
            logChoreError(error, operation: "chore_reward_redemptions.select_for_user", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchRewardRedemptionHistory(
        homeId: UUID,
        userId: UUID?,
        status: ChoreRewardRedemptionStatus?,
        limit: Int,
        offset: Int,
        currentRole: HomeMemberRole?
    ) async throws -> [ChoreRewardRedemption] {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        let statuses: [ChoreRewardRedemptionStatus]
        if let status {
            statuses = [status]
        } else {
            statuses = [.redeemed, .cancelled]
        }

        let fetchLimit = max(limit + offset, limit, 1)

        do {
            try await requireAuthenticatedSession()

            var combined: [ChoreRewardRedemption] = []
            for status in statuses {
                var query = client
                    .from("chore_reward_redemptions")
                    .select()
                    .eq("home_id", value: homeId.uuidString)
                    .eq("status", value: status.rawValue)

                if let userId {
                    query = query.eq("user_id", value: userId.uuidString)
                }

                let rows: [ChoreRewardRedemption] = try await query
                    .order("updated_at", ascending: false)
                    .order("id", ascending: false)
                    .range(from: 0, to: fetchLimit - 1)
                    .execute()
                    .value
                combined.append(contentsOf: rows)
            }

            return combined
                .sorted { lhs, rhs in
                    let lhsDate = rewardRedemptionHistoryDate(lhs)
                    let rhsDate = rewardRedemptionHistoryDate(rhs)
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                .dropFirst(offset)
                .prefix(limit)
                .map { $0 }
        } catch {
            logChoreError(error, operation: "chore_reward_redemptions.history_select", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func markRewardRedeemed(redemptionId: UUID, currentRole: HomeMemberRole?) async throws -> UUID {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let updatedRedemptionId: UUID = try await client
                .rpc(
                    "mark_chore_reward_redeemed",
                    params: RequestedRedemptionRPCParameters(redemptionId: redemptionId)
                )
                .execute()
                .value
            return updatedRedemptionId
        } catch {
            logChoreError(error, operation: "mark_chore_reward_redeemed", categoryId: redemptionId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func cancelRewardRedemption(redemptionId: UUID, cancellationReason: String?, currentRole: HomeMemberRole?) async throws -> UUID {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let cancelledRedemptionId: UUID = try await client
                .rpc(
                    "cancel_chore_reward_redemption",
                    params: CancelRewardRedemptionRPCParameters(
                        redemptionId: redemptionId,
                        cancellationReason: normalizedOptionalString(cancellationReason)
                    )
                )
                .execute()
                .value
            return cancelledRedemptionId
        } catch {
            logChoreError(error, operation: "cancel_chore_reward_redemption", categoryId: redemptionId)
            throw ChoreRepositoryError.map(error)
        }
    }

    // MARK: - Templates

    func fetchTemplates(homeId: UUID, includeArchived: Bool = false) async throws -> [ChoreTemplate] {
        do {
            try await requireAuthenticatedSession()
            let templates: [ChoreTemplate] = try await client
                .from("chore_templates")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .order("title", ascending: true)
                .execute()
                .value
            return includeArchived ? templates : templates.filter { $0.archivedAt == nil }
        } catch {
            logChoreError(error, operation: "chore_templates.select", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchTemplate(id: UUID) async throws -> ChoreTemplate? {
        do {
            try await requireAuthenticatedSession()
            let templates: [ChoreTemplate] = try await client
                .from("chore_templates")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return templates.first
        } catch {
            logChoreError(error, operation: "chore_templates.select_one", categoryId: id)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchTemplateAssignees(templateId: UUID) async throws -> [ChoreTemplateAssignee] {
        do {
            try await requireAuthenticatedSession()
            let assignees: [ChoreTemplateAssignee] = try await client
                .from("chore_template_assignees")
                .select()
                .eq("template_id", value: templateId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            return assignees
        } catch {
            logChoreError(error, operation: "chore_template_assignees.select", categoryId: templateId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchRecurrenceRule(templateId: UUID) async throws -> ChoreRecurrenceRule? {
        do {
            try await requireAuthenticatedSession()
            let rules: [ChoreRecurrenceRule] = try await client
                .from("chore_recurrence_rules")
                .select()
                .eq("template_id", value: templateId.uuidString)
                .limit(1)
                .execute()
                .value
            return rules.first
        } catch {
            logChoreError(error, operation: "chore_recurrence_rules.select", categoryId: templateId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func saveTemplate(draft: ChoreTemplateDraft) async throws -> UUID {
        do {
            try await requireAuthenticatedSession()
            let validatedDraft = try draft.validated()
            let parameters = SaveChoreTemplateRPCParameters(draft: validatedDraft)
            logSaveChoreTemplateRequest(parameters)
            let templateId: UUID = try await client
                .rpc("save_chore_template", params: parameters)
                .execute()
                .value
            return templateId
        } catch {
            logChoreError(error, operation: "save_chore_template", homeId: draft.homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func retireChore(templateId: UUID, effectiveFrom: Date) async throws -> RetiredChoreResult {
        do {
            try await requireAuthenticatedSession()
            let parameters = RetireChoreTemplateRPCParameters(templateId: templateId, effectiveFrom: effectiveFrom)
            logRetireChoreRequest(templateId: templateId, effectiveFrom: effectiveFrom)
            let rows: [RetiredChoreOccurrenceRow] = try await client
                .rpc("retire_chore_template", params: parameters)
                .execute()
                .value
            let result = RetiredChoreResult(
                affectedOccurrenceIds: rows.map(\.occurrenceId),
                calendarEventIds: rows.compactMap(\.calendarEventId)
            )
            logRetireChoreResult(result)
            return result
        } catch {
            logChoreError(error, operation: "retire_chore_template", categoryId: templateId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func refreshFutureOccurrenceAssignees(templateId: UUID, effectiveFrom: Date) async throws -> ChoreAssignmentRefreshResult {
        do {
            try await requireAuthenticatedSession()
            let parameters = RefreshChoreOccurrenceAssigneesRPCParameters(templateId: templateId, effectiveFrom: effectiveFrom)
            let rows: [RefreshChoreOccurrenceAssigneesResponse] = try await client
                .rpc("refresh_future_chore_occurrence_assignees", params: parameters)
                .execute()
                .value
            let result = rows.first.map {
                ChoreAssignmentRefreshResult(
                    futureOccurrencesUpdated: $0.futureOccurrencesUpdated,
                    newAssigneeCount: $0.newAssigneeCount
                )
            } ?? ChoreAssignmentRefreshResult(futureOccurrencesUpdated: 0, newAssigneeCount: 0)
            logChoreAssignmentRefresh(templateId: templateId, result: result)
            return result
        } catch {
            logChoreError(error, operation: "refresh_future_chore_occurrence_assignees", categoryId: templateId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func replaceFutureOccurrences(templateId: UUID, effectiveFrom: Date, generateThrough: Date, timezone: String) async throws -> ChoreOccurrenceReplacementResult {
        do {
            try await requireAuthenticatedSession()
            let parameters = ReplaceFutureChoreOccurrencesRPCParameters(
                templateId: templateId,
                effectiveFrom: effectiveFrom,
                generateThrough: generateThrough,
                timezone: timezone
            )
            logFutureScheduleReplacementRequest(parameters)
            let rows: [ReplacedChoreOccurrenceRow] = try await client
                .rpc("replace_future_chore_occurrences", params: parameters)
                .execute()
                .value
            let result = ChoreOccurrenceReplacementResult(
                removedOccurrenceIds: rows.map(\.occurrenceId),
                calendarEventIds: rows.compactMap(\.calendarEventId)
            )
            logFutureScheduleReplacementResult(result)
            return result
        } catch {
            logChoreError(error, operation: "replace_future_chore_occurrences", categoryId: templateId)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func logSaveChoreTemplateRequest(_ parameters: SaveChoreTemplateRPCParameters) {
        #if DEBUG
        print("========== SAVE CHORE RPC ==========")
        print("operation: save_chore_template")
        print("home_id: \(parameters.requestedHomeId.uuidString)")
        print("chore_id: \(parameters.requestedChoreId?.uuidString ?? "nil")")
        print("assignment_mode: \(parameters.requestedAssignmentMode)")
        print("completion_mode: \(parameters.requestedCompletionMode)")
        print("frequency: \(parameters.requestedFrequency)")
        print("interval: \(parameters.requestedIntervalValue)")
        print("start_date: \(parameters.requestedStartDate)")
        print("is_all_day: \(parameters.requestedIsAllDay)")
        print("assignee_count: \(parameters.requestedAssigneeIds.count)")
        print("=============================================")
        #endif
    }

    private func logRetireChoreRequest(templateId: UUID, effectiveFrom: Date) {
        #if DEBUG
        print("========== CHORE OPERATION ==========")
        print("operation: retire_chore_template")
        print("chore_id: \(templateId.uuidString)")
        print("effective_from: \(ChoreTimestampFormatter.string(from: effectiveFrom))")
        print("=====================================")
        #endif
    }

    private func logRetireChoreResult(_ result: RetiredChoreResult) {
        #if DEBUG
        print("========== CHORE OPERATION ==========")
        print("operation: retire_chore_template")
        print("affected_occurrence_count: \(result.affectedOccurrenceIds.count)")
        print("calendar_events_to_delete: \(result.calendarEventIds.count)")
        print("=====================================")
        #endif
    }

    private func logChoreAssignmentRefresh(templateId: UUID, result: ChoreAssignmentRefreshResult) {
        #if DEBUG
        print("========== CHORE ASSIGNMENT REFRESH ==========")
        print("chore_id: \(templateId.uuidString)")
        print("future_occurrences_updated: \(result.futureOccurrencesUpdated)")
        print("new_assignee_count: \(result.newAssigneeCount)")
        print("==============================================")
        #endif
    }

    private func logFutureScheduleReplacementRequest(_ parameters: ReplaceFutureChoreOccurrencesRPCParameters) {
        #if DEBUG
        print("========== CHORE OPERATION ==========")
        print("operation: replace_future_chore_occurrences")
        print("chore_id: \(parameters.requestedTemplateId.uuidString)")
        print("effective_from: \(parameters.effectiveFrom)")
        print("generate_through: \(parameters.generateThrough)")
        print("=====================================")
        #endif
    }

    private func logFutureScheduleReplacementResult(_ result: ChoreOccurrenceReplacementResult) {
        #if DEBUG
        print("========== CHORE OPERATION ==========")
        print("operation: replace_future_chore_occurrences")
        print("removed_occurrence_count: \(result.removedOccurrenceIds.count)")
        print("calendar_events_to_delete: \(result.calendarEventIds.count)")
        print("=====================================")
        #endif
    }

    // MARK: - Occurrences

    func generateOccurrences(templateId: UUID, through endDate: Date, timezone: String = TimeZone.autoupdatingCurrent.identifier) async throws -> [ChoreOccurrence] {
        do {
            try await requireAuthenticatedSession()
            let parameters = GenerateChoreOccurrencesRPCParameters(templateId: templateId, through: endDate, timezone: timezone)
            logGenerateChoreOccurrencesRequest(parameters)
            let occurrenceIds: [UUID] = try await client
                .rpc("generate_chore_occurrences", params: parameters)
                .execute()
                .value
            return try await fetchOccurrences(ids: occurrenceIds)
        } catch {
            logChoreError(error, operation: "generate_chore_occurrences", categoryId: templateId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func generateHomeOccurrences(homeId: UUID, through endDate: Date, timezone: String = TimeZone.autoupdatingCurrent.identifier) async throws -> [ChoreOccurrence] {
        do {
            try await requireAuthenticatedSession()
            let parameters = GenerateHomeChoreOccurrencesRPCParameters(homeId: homeId, through: endDate, timezone: timezone)
            let occurrenceIds: [UUID] = try await client
                .rpc("generate_home_chore_occurrences", params: parameters)
                .execute()
                .value
            return try await fetchOccurrences(ids: occurrenceIds)
        } catch {
            logChoreError(error, operation: "generate_home_chore_occurrences", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func logGenerateChoreOccurrencesRequest(_ parameters: GenerateChoreOccurrencesRPCParameters) {
        #if DEBUG
        print("========== CHORE OPERATION ==========")
        print("operation: generate_chore_occurrences")
        print("chore_id: \(parameters.requestedChoreId.uuidString)")
        print("generate_through: \(parameters.generateThrough)")
        print("=====================================")
        #endif
    }

    func fetchOccurrences(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        guard endDate >= startDate else { throw ChoreRepositoryError.invalidDateRange }
        do {
            try await requireAuthenticatedSession()
            let occurrences: [ChoreOccurrence] = try await client
                .from("chore_occurrences")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .gte("due_at", value: ChoreTimestampFormatter.string(from: startDate))
                .lt("due_at", value: ChoreTimestampFormatter.string(from: endDate))
                .order("due_at", ascending: true)
                .execute()
                .value
            logFetchedOccurrences(occurrences)
            return occurrences
        } catch {
            logChoreError(error, operation: "chore_occurrences.select_range", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func logFetchedOccurrences(_ occurrences: [ChoreOccurrence]) {
        #if DEBUG
        print("========== CHORE OCCURRENCES LOADED ==========")
        print("occurrence_count: \(occurrences.count)")
        if let firstOccurrence = occurrences.first {
            print("first_occurrence_id: \(firstOccurrence.id.uuidString)")
            print("first_occurrence_status: \(firstOccurrence.status.rawValue)")
            print("first_occurrence_points_snapshot: \(firstOccurrence.pointsValueSnapshot)")
            print("first_occurrence_has_calendar_event: \(firstOccurrence.calendarEventId != nil)")
        }
        print("==============================================")
        #endif
    }

    func fetchMyOccurrences(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        let userId = try await authenticatedUserId()
        let occurrences = try await fetchOccurrences(homeId: homeId, from: startDate, through: endDate)
        var visible: [ChoreOccurrence] = []
        for occurrence in occurrences {
            if occurrence.assignmentMode == .open, occurrence.claimedBy == nil || occurrence.claimedBy == userId {
                visible.append(occurrence)
                continue
            }
            let assignees = try await fetchOccurrenceAssignees(occurrenceId: occurrence.id)
            if assignees.contains(where: { $0.userId == userId }) {
                visible.append(occurrence)
            }
        }
        return visible
    }

    func fetchOccurrence(id: UUID) async throws -> ChoreOccurrence? {
        do {
            try await requireAuthenticatedSession()
            let occurrences: [ChoreOccurrence] = try await client
                .from("chore_occurrences")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return occurrences.first
        } catch {
            logChoreError(error, operation: "chore_occurrences.select_one", categoryId: id)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func fetchOccurrences(ids: [UUID]) async throws -> [ChoreOccurrence] {
        guard !ids.isEmpty else {
            return []
        }

        var occurrences: [ChoreOccurrence] = []
        for id in ids {
            if let occurrence = try await fetchOccurrence(id: id) {
                occurrences.append(occurrence)
            }
        }
        return occurrences.sorted { $0.dueAt < $1.dueAt }
    }

    private func fetchOccurrences(homeId: UUID, status: ChoreOccurrenceStatus) async throws -> [ChoreOccurrence] {
        do {
            try await requireAuthenticatedSession()
            let occurrences: [ChoreOccurrence] = try await client
                .from("chore_occurrences")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("status", value: status.rawValue)
                .order("due_at", ascending: true)
                .execute()
                .value
            return occurrences
        } catch {
            logChoreError(error, operation: "chore_occurrences.select_status", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func fetchPendingSubmissionsForAttention() async throws -> [ChoreSubmission] {
        do {
            try await requireAuthenticatedSession()
            let submissions: [ChoreSubmission] = try await client
                .from("chore_submissions")
                .select()
                .eq("status", value: ChoreSubmissionStatus.pending.rawValue)
                .order("submitted_at", ascending: true)
                .execute()
                .value
            return submissions
        } catch {
            logChoreError(error, operation: "chore_submissions.select_pending_attention")
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchPendingChoreApprovals(homeId: UUID) async throws -> [ChorePendingApprovalQueueItem] {
        let submissions = try await fetchPendingSubmissionsForAttention()
        var queueItems: [ChorePendingApprovalQueueItem] = []

        for submission in submissions {
            guard submission.status == .pending else {
                logApprovalQueueDecision(homeId: homeId, submission: submission, occurrence: nil, included: false, exclusionReason: "submission_status_not_pending")
                continue
            }

            guard let occurrence = try await fetchOccurrence(id: submission.occurrenceId) else {
                logApprovalQueueDecision(homeId: homeId, submission: submission, occurrence: nil, included: false, exclusionReason: "occurrence_not_found")
                continue
            }

            guard occurrence.homeId == homeId else {
                logApprovalQueueDecision(homeId: homeId, submission: submission, occurrence: occurrence, included: false, exclusionReason: "different_home")
                continue
            }

            guard occurrence.status == .awaitingApproval else {
                logApprovalQueueDecision(homeId: homeId, submission: submission, occurrence: occurrence, included: false, exclusionReason: "occurrence_not_awaiting_approval")
                continue
            }

            logApprovalQueueDecision(homeId: homeId, submission: submission, occurrence: occurrence, included: true, exclusionReason: nil)
            queueItems.append(ChorePendingApprovalQueueItem(occurrence: occurrence, submission: submission))
        }

        logApprovalQueueSummary(homeId: homeId, pendingSubmissionCount: queueItems.count)
        return queueItems.sorted { first, second in
            first.submission.submittedAt < second.submission.submittedAt
        }
    }

    func fetchOccurrence(calendarEventId: UUID) async throws -> ChoreOccurrence? {
        do {
            try await requireAuthenticatedSession()
            let occurrences: [ChoreOccurrence] = try await client
                .from("chore_occurrences")
                .select()
                .eq("calendar_event_id", value: calendarEventId.uuidString)
                .limit(1)
                .execute()
                .value
            return occurrences.first
        } catch {
            logChoreError(error, operation: "chore_occurrences.select_calendar_event", categoryId: calendarEventId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchOccurrenceAssignees(occurrenceId: UUID) async throws -> [ChoreOccurrenceAssignee] {
        do {
            try await requireAuthenticatedSession()
            let assignees: [ChoreOccurrenceAssignee] = try await client
                .from("chore_occurrence_assignees")
                .select()
                .eq("occurrence_id", value: occurrenceId.uuidString)
                .order("assigned_at", ascending: true)
                .execute()
                .value
            logFetchedOccurrenceAssignees(assignees, occurrenceId: occurrenceId)
            return assignees
        } catch {
            logChoreError(error, operation: "chore_occurrence_assignees.select", categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func logFetchedOccurrenceAssignees(_ assignees: [ChoreOccurrenceAssignee], occurrenceId: UUID) {
        #if DEBUG
        print("========== CHORE ASSIGNEES LOADED ==========")
        print("occurrence_id: \(occurrenceId.uuidString)")
        print("assignee_count: \(assignees.count)")
        if let firstAssignee = assignees.first {
            print("first_assignee_user_id: \(firstAssignee.userId.uuidString)")
            print("first_assignee_status: \(firstAssignee.status.rawValue)")
        }
        print("=============================================")
        #endif
    }

    func linkCalendarEvent(occurrenceId: UUID, calendarEventId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_occurrences")
                .update(LinkCalendarEventPayload(calendarEventId: calendarEventId))
                .eq("id", value: occurrenceId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_occurrences.link_calendar_event", categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func refreshChoreSchedule(
        homeId: UUID,
        from startDate: Date,
        through endDate: Date,
        currentRole: HomeMemberRole?,
        calendarSyncService: ChoreCalendarSyncService
    ) async throws -> [ChoreOccurrence] {
        guard endDate >= startDate else { throw ChoreRepositoryError.invalidDateRange }

        if currentRole?.canManageChores == true {
            _ = try await generateHomeOccurrences(homeId: homeId, through: endDate)
            let generatedOccurrences = try await fetchOccurrences(homeId: homeId, from: startDate, through: endDate)
            return try await calendarSyncService.syncMissingCalendarEvents(homeId: homeId, occurrences: generatedOccurrences)
        }

        return try await fetchOccurrences(homeId: homeId, from: startDate, through: endDate)
    }

    func updateOccurrenceSchedule(
        occurrenceId: UUID,
        dueAt: Date,
        endAt: Date,
        dueLocalDate: Date,
        dueTime: ChoreLocalTime?,
        isAllDay: Bool,
        timezone: String
    ) async throws {
        guard endAt >= dueAt else { throw ChoreRepositoryError.invalidDateRange }
        do {
            try await requireAuthenticatedSession()
            try await client
                .from("chore_occurrences")
                .update(UpdateOccurrenceSchedulePayload(
                    dueAt: dueAt,
                    endAt: endAt,
                    dueLocalDate: dueLocalDate,
                    dueTime: dueTime,
                    isAllDay: isAllDay,
                    timezone: timezone
                ))
                .eq("id", value: occurrenceId.uuidString)
                .execute()
        } catch {
            logChoreError(error, operation: "chore_occurrences.update_schedule", categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    // MARK: - State Transitions

    func claimOpenChore(occurrenceId: UUID) async throws {
        try await callOccurrenceRPC("claim_open_chore", occurrenceId: occurrenceId)
    }

    @discardableResult
    func startChore(occurrenceId: UUID) async throws -> ChoreOccurrence {
        do {
            try await requireAuthenticatedSession()
            let updatedOccurrence: ChoreOccurrence = try await client
                .rpc("start_chore", params: StartChoreRPCParameters(requestedOccurrenceId: occurrenceId))
                .execute()
                .value
            logChoreOperation("start_chore", entityId: occurrenceId, updatedStatus: updatedOccurrence.status)
            return updatedOccurrence
        } catch {
            logChoreError(error, operation: "start_chore", categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func submitChore(occurrenceId: UUID, note: String?, photoPath: String?) async throws -> UUID {
        do {
            try await requireAuthenticatedSession()
            let submissionId: UUID = try await client
                .rpc(
                    "submit_chore",
                    params: SubmitChoreRPCParameters(
                        requestedOccurrenceId: occurrenceId,
                        requestedCompletionNote: normalizedOptionalString(note),
                        requestedPhotoPath: normalizedOptionalString(photoPath)
                    )
                )
                .execute()
                .value
            return submissionId
        } catch {
            logChoreError(error, operation: "submit_chore", categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func reviewSubmission(submissionId: UUID, decision: ChoreApprovalDecision, adminNote: String?, pointsAwarded: Int?) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .rpc(
                    "review_chore_submission",
                    params: ReviewChoreSubmissionRPCParameters(
                        requestedSubmissionId: submissionId,
                        requestedDecision: decision.rawValue,
                        requestedAdminNote: normalizedOptionalString(adminNote),
                        requestedPointsAwarded: pointsAwarded
                    )
                )
                .execute()
        } catch {
            logChoreError(error, operation: "review_chore_submission", categoryId: submissionId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchPendingSubmission(occurrenceId: UUID) async throws -> ChoreSubmission? {
        do {
            try await requireAuthenticatedSession()
            let submissions: [ChoreSubmission] = try await client
                .from("chore_submissions")
                .select()
                .eq("occurrence_id", value: occurrenceId.uuidString)
                .eq("status", value: ChoreSubmissionStatus.pending.rawValue)
                .order("submitted_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return submissions.first
        } catch {
            logChoreError(error, operation: "chore_submissions.select_pending", categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchMyPointBalance(homeId: UUID) async throws -> Int {
        let userId = try await authenticatedUserId()
        return try await fetchPointBalance(homeId: homeId, userId: userId, currentRole: .member)
    }

    func fetchPointBalance(homeId: UUID, userId: UUID, currentRole: HomeMemberRole?) async throws -> Int {
        let authenticatedUserId = try await authenticatedUserId()
        guard authenticatedUserId == userId || currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let transactions: [ChorePointTransaction] = try await client
                .from("chore_point_transactions")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            return transactions.reduce(0) { $0 + $1.pointsDelta }
        } catch {
            logChoreError(error, operation: "chore_point_transactions.balance_select", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchMyPointTransactions(homeId: UUID, limit: Int, offset: Int) async throws -> [ChorePointTransaction] {
        let userId = try await authenticatedUserId()
        return try await fetchPointTransactions(homeId: homeId, userId: userId, limit: limit, offset: offset, currentRole: .member)
    }

    func fetchPointTransactions(
        homeId: UUID,
        userId: UUID,
        limit: Int,
        offset: Int,
        currentRole: HomeMemberRole?
    ) async throws -> [ChorePointTransaction] {
        let authenticatedUserId = try await authenticatedUserId()
        guard authenticatedUserId == userId || currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let transactions: [ChorePointTransaction] = try await client
                .from("chore_point_transactions")
                .select()
                .eq("home_id", value: homeId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .range(from: offset, to: offset + max(limit, 1) - 1)
                .execute()
                .value
            return transactions
        } catch {
            logChoreError(error, operation: "chore_point_transactions.select_for_user", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchPointTransactionDisplayTitles(for transactions: [ChorePointTransaction]) async -> [UUID: String] {
        var titlesByTransactionId: [UUID: String] = [:]
        var occurrenceTitlesById: [UUID: String] = [:]
        var rewardTitlesById: [UUID: String] = [:]

        for transaction in transactions {
            if let occurrenceId = transaction.occurrenceId {
                if let cachedTitle = occurrenceTitlesById[occurrenceId] {
                    titlesByTransactionId[transaction.id] = cachedTitle
                    continue
                }

                if let occurrence = try? await fetchOccurrence(id: occurrenceId) {
                    occurrenceTitlesById[occurrenceId] = occurrence.titleSnapshot
                    titlesByTransactionId[transaction.id] = occurrence.titleSnapshot
                    continue
                }
            }

            if let rewardId = transaction.rewardId {
                if let cachedTitle = rewardTitlesById[rewardId] {
                    titlesByTransactionId[transaction.id] = cachedTitle
                    continue
                }

                if let rewardTitle = try? await fetchRewardTitle(rewardId: rewardId) {
                    rewardTitlesById[rewardId] = rewardTitle
                    titlesByTransactionId[transaction.id] = rewardTitle
                }
            }
        }

        return titlesByTransactionId
    }

    func adjustChorePoints(
        homeId: UUID,
        userId: UUID,
        points: Int,
        description: String,
        transactionAt: Date,
        currentRole: HomeMemberRole?
    ) async throws -> UUID {
        guard currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        let trimmedDescription = normalizedRequiredString(description)
        guard points != 0, !trimmedDescription.isEmpty else {
            throw ChoreRepositoryError.invalidPointAdjustment
        }

        do {
            try await requireAuthenticatedSession()
            let parameters = AdjustChorePointsRPCParameters(
                homeId: homeId,
                userId: userId,
                points: points,
                description: trimmedDescription,
                transactionAt: transactionAt
            )
            let transactionId: UUID = try await client
                .rpc("adjust_chore_points", params: parameters)
                .execute()
                .value
            return transactionId
        } catch {
            logChoreError(error, operation: "adjust_chore_points", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func clearHomeChores(homeId: UUID, currentRole: HomeMemberRole?) async throws -> ClearHomeChoresResult {
        guard currentRole == .owner else {
            throw ChoreRepositoryError.ownerRequired
        }

        do {
            try await requireAuthenticatedSession()
            logClearHomeChoresRequest(homeId: homeId)
            let results: [ClearHomeChoresResult] = try await client
                .rpc("clear_home_chores", params: HomeIdParameters(homeId: homeId))
                .execute()
                .value
            guard let result = results.first else {
                throw ChoreRepositoryError.mutationFailed
            }
            logClearHomeChoresResult(result)
            return result
        } catch {
            logChoreError(error, operation: "clear_home_chores", homeId: homeId)
            throw ChoreRepositoryError.map(error)
        }
    }

    func fetchChoreHistoryActivities(
        homeId: UUID,
        userId: UUID,
        limit: Int,
        offset: Int,
        currentRole: HomeMemberRole?
    ) async throws -> [ChoreHistoryActivity] {
        let authenticatedUserId = try await authenticatedUserId()
        guard authenticatedUserId == userId || currentRole == .owner || currentRole == .admin else {
            throw ChoreRepositoryError.ownerOrAdminRequired
        }

        do {
            try await requireAuthenticatedSession()
            let activities: [ChoreHistoryActivity] = try await client
                .rpc(
                    "get_chore_history",
                    params: ChoreHistoryRPCParameters(
                        homeId: homeId,
                        userId: userId,
                        limit: max(limit, 1),
                        offset: max(offset, 0)
                    )
                )
                .execute()
                .value
            return activities
        } catch {
            logChoreError(error, operation: "get_chore_history", homeId: homeId, categoryId: userId)
            throw ChoreRepositoryError.map(error)
        }
    }

    // MARK: - Prepared Queries

    func fetchMyActionableOccurrences(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        try await fetchMyOccurrences(homeId: homeId, from: startDate, through: endDate)
            .filter { [.notStarted, .inProgress, .needsRedo].contains($0.status) }
    }

    func fetchCurrentWeekNotStartedChoreBadgeCount(
        homeId: UUID,
        weekStart: Date,
        nextWeekStart: Date
    ) async throws -> ChoresBadgeCountResult {
        let occurrences = try await fetchMyOccurrences(homeId: homeId, from: weekStart, through: nextWeekStart)
        var occurrenceIds: Set<UUID> = []

        for occurrence in occurrences {
            guard occurrence.status == .notStarted,
                  occurrence.dueAt >= weekStart,
                  occurrence.dueAt < nextWeekStart else {
                continue
            }

            occurrenceIds.insert(occurrence.id)
        }

        let sortedIds = occurrenceIds.sorted { $0.uuidString < $1.uuidString }
        return ChoresBadgeCountResult(count: sortedIds.count, occurrenceIds: sortedIds)
    }

    func fetchMyCompletedHistory(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        try await fetchMyOccurrences(homeId: homeId, from: startDate, through: endDate)
            .filter { [.completed, .skipped, .cancelled].contains($0.status) }
    }

    func fetchHouseChoreOccurrences(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        try await fetchOccurrences(homeId: homeId, from: startDate, through: endDate)
    }

    func fetchOccurrencesAwaitingApproval(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        try await fetchOccurrences(homeId: homeId, from: startDate, through: endDate)
            .filter { $0.status == .awaitingApproval }
    }

    func fetchMyActionChoreCount(homeId: UUID) async throws -> Int {
        let userId = try await authenticatedUserId()
        let actionableStatuses: [ChoreOccurrenceStatus] = [.notStarted, .inProgress, .needsRedo]
        var actionableOccurrenceIds: Set<UUID> = []

        for status in actionableStatuses {
            let occurrences = try await fetchOccurrences(homeId: homeId, status: status)
            for occurrence in occurrences {
                if occurrence.assignmentMode == .open, occurrence.claimedBy == userId {
                    actionableOccurrenceIds.insert(occurrence.id)
                    continue
                }

                let assignees = try await fetchOccurrenceAssignees(occurrenceId: occurrence.id)
                if assignees.contains(where: { assignee in
                    assignee.userId == userId && assignee.status.isActionableForAttention
                }) {
                    actionableOccurrenceIds.insert(occurrence.id)
                }
            }
        }

        return actionableOccurrenceIds.count
    }

    func fetchPendingChoreApprovalCount(homeId: UUID) async throws -> Int {
        try await fetchPendingChoreApprovals(homeId: homeId).count
    }

    func fetchPausedTemplates(homeId: UUID) async throws -> [ChoreTemplate] {
        try await fetchTemplates(homeId: homeId, includeArchived: false).filter { !$0.isActive }
    }

    func fetchArchivedTemplates(homeId: UUID) async throws -> [ChoreTemplate] {
        try await fetchTemplates(homeId: homeId, includeArchived: true).filter { $0.archivedAt != nil }
    }

    func fetchMemberHistory(homeId: UUID, from startDate: Date, through endDate: Date) async throws -> [ChoreOccurrence] {
        try await fetchMyCompletedHistory(homeId: homeId, from: startDate, through: endDate)
    }

    func fetchHouseholdHistory(homeId: UUID, from startDate: Date, through endDate: Date, currentRole: HomeMemberRole?) async throws -> [ChoreOccurrence] {
        guard currentRole?.canManageChores == true else {
            return try await fetchMemberHistory(homeId: homeId, from: startDate, through: endDate)
        }
        return try await fetchOccurrences(homeId: homeId, from: startDate, through: endDate)
            .filter { [.completed, .skipped, .cancelled].contains($0.status) }
    }

    // MARK: - Private

    private func callOccurrenceRPC(_ rpcName: String, occurrenceId: UUID) async throws {
        do {
            try await requireAuthenticatedSession()
            try await client
                .rpc(rpcName, params: RequestedOccurrenceRPCParameters(requestedOccurrenceId: occurrenceId))
                .execute()
        } catch {
            logChoreError(error, operation: rpcName, categoryId: occurrenceId)
            throw ChoreRepositoryError.map(error)
        }
    }

    private func requireAuthenticatedSession() async throws {
        do {
            _ = try await client.auth.session
        } catch {
            throw ChoreRepositoryError.authenticationRequired
        }
    }

    private func authenticatedUserId() async throws -> UUID {
        do {
            return try await client.auth.session.user.id
        } catch {
            throw ChoreRepositoryError.authenticationRequired
        }
    }

    private func fetchRewardTitle(rewardId: UUID) async throws -> String? {
        if let title = try? await fetchRewardTitle(rewardId: rewardId, tableName: "rewards", columnName: "title") {
            return title
        }
        if let name = try? await fetchRewardTitle(rewardId: rewardId, tableName: "rewards", columnName: "name") {
            return name
        }
        if let title = try? await fetchRewardTitle(rewardId: rewardId, tableName: "chore_rewards", columnName: "title") {
            return title
        }
        return try await fetchRewardTitle(rewardId: rewardId, tableName: "chore_rewards", columnName: "name")
    }

    private func fetchRewardTitle(rewardId: UUID, tableName: String, columnName: String) async throws -> String? {
        let rows: [RewardTitleRow] = try await client
            .from(tableName)
            .select("id,\(columnName)")
            .eq("id", value: rewardId.uuidString)
            .limit(1)
            .execute()
            .value

        return rows.first?.displayTitle
    }

    private func normalizedRequiredString(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func logChoreError(_ error: Error, operation: String, homeId: UUID? = nil, categoryId: UUID? = nil) {
        #if DEBUG
        print("========== CHORE OPERATION FAILED ==========")
        print("operation: \(operation)")
        if let homeId { print("home_id: \(homeId.uuidString)") }
        if let categoryId { print("entity_id: \(categoryId.uuidString)") }
        print(String(reflecting: error))
        if let postgrestError = error as? PostgrestError {
            print("PostGREST code: \(postgrestError.code ?? "")")
            print("PostGREST message: \(postgrestError.message)")
            print("PostGREST detail: \(postgrestError.detail ?? "")")
            print("PostGREST hint: \(postgrestError.hint ?? "")")
        }
        print("============================================")
        #endif
    }

    private func logApprovalQueueSummary(homeId: UUID, pendingSubmissionCount: Int) {
        #if DEBUG
        print("========== CHORE APPROVAL QUEUE ==========")
        print("home_id: \(homeId.uuidString)")
        print("pending_submission_count: \(pendingSubmissionCount)")
        print("==========================================")
        #endif
    }

    private func logApprovalQueueDecision(
        homeId: UUID,
        submission: ChoreSubmission,
        occurrence: ChoreOccurrence?,
        included: Bool,
        exclusionReason: String?
    ) {
        #if DEBUG
        print("========== CHORE APPROVAL QUEUE ==========")
        print("home_id: \(homeId.uuidString)")
        print("submission:")
        print("- submission_id: \(submission.id.uuidString)")
        print("  occurrence_id: \(submission.occurrenceId.uuidString)")
        if let occurrence {
            print("  occurrence_due_at: \(ChoreTimestampFormatter.string(from: occurrence.dueAt))")
            print("  occurrence_due_local_date: \(ChoreTimestampFormatter.string(from: occurrence.dueLocalDate))")
            print("  occurrence_status: \(occurrence.status.rawValue)")
        } else {
            print("  occurrence_due_at: nil")
            print("  occurrence_due_local_date: nil")
            print("  occurrence_status: nil")
        }
        print("  submission_status: \(submission.status.rawValue)")
        print("  submitted_at: \(ChoreTimestampFormatter.string(from: submission.submittedAt))")
        print("  included_in_queue: \(included)")
        print("  exclusion_reason: \(exclusionReason ?? "none")")
        print("==========================================")
        #endif
    }

    private func logChoreOperation(_ operation: String, entityId: UUID, updatedStatus: ChoreOccurrenceStatus? = nil) {
        #if DEBUG
        print("========== CHORE OPERATION ==========")
        print("operation: \(operation)")
        print("entity_id: \(entityId.uuidString)")
        if let updatedStatus {
            print("updated_status: \(updatedStatus.rawValue)")
        }
        print("=====================================")
        #endif
    }

    private func logClearHomeChoresRequest(homeId: UUID) {
        #if DEBUG
        print("========== CLEAR CHORES ==========")
        print("home_id: \(homeId.uuidString)")
        print("==================================")
        #endif
    }

    private func logClearHomeChoresResult(_ result: ClearHomeChoresResult) {
        #if DEBUG
        print("========== CLEAR CHORES COMPLETE ==========")
        print("definitions_deleted: \(result.choreDefinitionsDeleted)")
        print("recurrence_rules_deleted: \(result.recurrenceRulesDeleted)")
        print("occurrences_deleted: \(result.occurrencesDeleted)")
        print("calendar_events_deleted: \(result.calendarEventsDeleted)")
        print("submissions_deleted: \(result.submissionsDeleted)")
        print("approvals_deleted: \(result.approvalsDeleted)")
        print("point_transactions_deleted: \(result.pointTransactionsDeleted)")
        print("categories_deleted: \(result.categoriesDeleted)")
        print("rooms_deleted: \(result.roomsDeleted)")
        print("===========================================")
        #endif
    }

    private func rewardRedemptionHistoryDate(_ redemption: ChoreRewardRedemption) -> Date {
        switch redemption.status {
        case .redeemed:
            return redemption.redeemedAt ?? redemption.updatedAt
        case .cancelled:
            return redemption.cancelledAt ?? redemption.updatedAt
        case .pending:
            return redemption.updatedAt
        }
    }
}

private extension HomeMemberRole {
    var canManageChores: Bool {
        switch self {
        case .owner, .admin:
            return true
        case .member:
            return false
        }
    }
}

private struct ChoreMutationIdResponse: Decodable {
    let id: UUID
}

private struct ChoreCategoryMutationPayload: Encodable {
    let homeId: UUID
    let name: String
    let colorHex: String?
    let iconName: String?
    let sortOrder: Int
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
        case archivedAt = "archived_at"
    }
}

private struct ChoreCategoryUpdatePayload: Encodable {
    let name: String
    let colorHex: String?
    let iconName: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case sortOrder = "sort_order"
    }
}

private struct ChoreRoomMutationPayload: Encodable {
    let homeId: UUID
    let name: String
    let sortOrder: Int
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case sortOrder = "sort_order"
        case archivedAt = "archived_at"
    }
}

private struct ChoreRoomUpdatePayload: Encodable {
    let name: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name
        case sortOrder = "sort_order"
    }
}

private struct ChoreRewardMutationPayload: Encodable {
    let homeId: UUID
    let name: String
    let description: String?
    let pointCost: Int
    let isActive: Bool
    let isArchived: Bool
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case description
        case pointCost = "point_cost"
        case isActive = "is_active"
        case isArchived = "is_archived"
        case createdBy = "created_by"
    }
}

private struct ChoreRewardUpdatePayload: Encodable {
    let name: String
    let description: String?
    let pointCost: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case pointCost = "point_cost"
        case isActive = "is_active"
    }
}

private struct ArchiveRewardPayload: Encodable {
    let isArchived = true

    enum CodingKeys: String, CodingKey {
        case isArchived = "is_archived"
    }
}

private struct RedeemChoreRewardRPCParameters: Encodable {
    let homeId: UUID
    let rewardId: UUID

    enum CodingKeys: String, CodingKey {
        case homeId = "requested_home_id"
        case rewardId = "requested_reward_id"
    }
}

private struct RequestedRedemptionRPCParameters: Encodable {
    let redemptionId: UUID

    enum CodingKeys: String, CodingKey {
        case redemptionId = "requested_redemption_id"
    }
}

private struct CancelRewardRedemptionRPCParameters: Encodable {
    let redemptionId: UUID
    let cancellationReason: String?

    enum CodingKeys: String, CodingKey {
        case redemptionId = "requested_redemption_id"
        case cancellationReason = "requested_cancellation_reason"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(redemptionId, forKey: .redemptionId)
        try encodeOptional(cancellationReason, forKey: .cancellationReason, into: &container)
    }
}

private struct ArchivePayload: Encodable {
    let archivedAt: String

    init(archivedAt: Date) {
        self.archivedAt = ChoreTimestampFormatter.string(from: archivedAt)
    }

    enum CodingKeys: String, CodingKey {
        case archivedAt = "archived_at"
    }
}

private struct LinkCalendarEventPayload: Encodable {
    let calendarEventId: UUID

    enum CodingKeys: String, CodingKey {
        case calendarEventId = "calendar_event_id"
    }
}

private struct RetireChoreTemplateRPCParameters: Encodable {
    let requestedTemplateId: UUID
    let effectiveFrom: String

    init(templateId: UUID, effectiveFrom: Date) {
        requestedTemplateId = templateId
        self.effectiveFrom = ChoreTimestampFormatter.string(from: effectiveFrom)
    }

    enum CodingKeys: String, CodingKey {
        case requestedTemplateId = "requested_template_id"
        case effectiveFrom = "effective_from"
    }
}

struct RetiredChoreResult: Sendable {
    let affectedOccurrenceIds: [UUID]
    let calendarEventIds: [UUID]
}

struct ChoreAssignmentRefreshResult: Sendable {
    let futureOccurrencesUpdated: Int
    let newAssigneeCount: Int
}

struct ChoreOccurrenceReplacementResult: Sendable {
    let removedOccurrenceIds: [UUID]
    let calendarEventIds: [UUID]
}

private struct RetiredChoreOccurrenceRow: Decodable {
    let occurrenceId: UUID
    let calendarEventId: UUID?

    enum CodingKeys: String, CodingKey {
        case occurrenceId = "occurrence_id"
        case calendarEventId = "calendar_event_id"
    }
}

private struct RefreshChoreOccurrenceAssigneesRPCParameters: Encodable {
    let requestedTemplateId: UUID
    let effectiveFrom: String

    init(templateId: UUID, effectiveFrom: Date) {
        requestedTemplateId = templateId
        self.effectiveFrom = ChoreTimestampFormatter.string(from: effectiveFrom)
    }

    enum CodingKeys: String, CodingKey {
        case requestedTemplateId = "requested_template_id"
        case effectiveFrom = "effective_from"
    }
}

private struct ReplaceFutureChoreOccurrencesRPCParameters: Encodable {
    let requestedTemplateId: UUID
    let effectiveFrom: String
    let generateThrough: String

    init(templateId: UUID, effectiveFrom: Date, generateThrough: Date, timezone: String) {
        requestedTemplateId = templateId
        self.effectiveFrom = ChoreTimestampFormatter.string(from: effectiveFrom)
        self.generateThrough = ChoreDateOnlyFormatter.string(from: generateThrough, timezone: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case requestedTemplateId = "requested_template_id"
        case effectiveFrom = "effective_from"
        case generateThrough = "generate_through"
    }
}

private struct ReplacedChoreOccurrenceRow: Decodable {
    let occurrenceId: UUID
    let calendarEventId: UUID?

    enum CodingKeys: String, CodingKey {
        case occurrenceId = "occurrence_id"
        case calendarEventId = "calendar_event_id"
    }
}

private struct RefreshChoreOccurrenceAssigneesResponse: Decodable {
    let futureOccurrencesUpdated: Int
    let newAssigneeCount: Int

    enum CodingKeys: String, CodingKey {
        case futureOccurrencesUpdated = "future_occurrences_updated"
        case newAssigneeCount = "new_assignee_count"
    }
}

private struct UpdateOccurrenceSchedulePayload: Encodable {
    let dueAt: String
    let endAt: String
    let dueLocalDate: String
    let dueTime: String?
    let isAllDay: Bool
    let timezone: String

    init(dueAt: Date, endAt: Date, dueLocalDate: Date, dueTime: ChoreLocalTime?, isAllDay: Bool, timezone: String) {
        self.dueAt = ChoreTimestampFormatter.string(from: dueAt)
        self.endAt = ChoreTimestampFormatter.string(from: endAt)
        self.dueLocalDate = ChoreDateOnlyFormatter.string(from: dueLocalDate, timezone: timezone)
        self.dueTime = dueTime?.rawValue
        self.isAllDay = isAllDay
        self.timezone = timezone
    }

    enum CodingKeys: String, CodingKey {
        case dueAt = "due_at"
        case endAt = "end_at"
        case dueLocalDate = "due_local_date"
        case dueTime = "due_time"
        case isAllDay = "is_all_day"
        case timezone
    }
}

private struct SaveChoreTemplateRPCParameters: Encodable {
    let requestedHomeId: UUID
    let requestedChoreId: UUID?
    let requestedTitle: String
    let requestedDescription: String?
    let requestedInstructions: String?
    let requestedCategoryId: UUID?
    let requestedRoomId: UUID?
    let requestedAssignmentMode: String
    let requestedCompletionMode: String
    let requestedPointsValue: Int
    let requestedRequiresApproval: Bool
    let requestedRequiresPhoto: Bool
    let requestedFrequency: String
    let requestedIntervalValue: Int
    let requestedStartDate: String
    let requestedDueTime: String?
    let requestedDurationMinutes: Int
    let requestedIsAllDay: Bool
    let requestedWeekdays: [Int]
    let requestedDayOfMonth: Int?
    let requestedMonthOfYear: Int?
    let requestedEndType: String
    let requestedEndsOn: String?
    let requestedOccurrenceCount: Int?
    let requestedTimezone: String
    let requestedAssigneeIds: [UUID]

    init(draft: ChoreTemplateDraft) {
        let normalizedDraft = draft.normalized
        requestedHomeId = normalizedDraft.homeId
        requestedChoreId = normalizedDraft.id
        requestedTitle = normalizedDraft.title
        requestedDescription = normalizedDraft.description.isEmpty ? nil : normalizedDraft.description
        requestedInstructions = normalizedDraft.instructions.isEmpty ? nil : normalizedDraft.instructions
        requestedCategoryId = nil
        requestedRoomId = nil
        requestedAssignmentMode = normalizedDraft.assignmentMode.rawValue
        requestedCompletionMode = Self.requestedCompletionMode(for: normalizedDraft).rawValue
        requestedPointsValue = normalizedDraft.pointsValue
        requestedRequiresApproval = normalizedDraft.requiresApproval
        requestedRequiresPhoto = false
        requestedFrequency = normalizedDraft.frequency.rawValue
        requestedIntervalValue = normalizedDraft.frequency == .none ? 1 : normalizedDraft.intervalValue
        requestedStartDate = ChoreDateOnlyFormatter.string(from: normalizedDraft.startDate, timezone: normalizedDraft.timezone)
        requestedDueTime = normalizedDraft.isAllDay ? nil : normalizedDraft.dueTime?.rawValue
        requestedDurationMinutes = normalizedDraft.durationMinutes
        requestedIsAllDay = normalizedDraft.isAllDay
        requestedWeekdays = normalizedDraft.frequency == .weekly ? normalizedDraft.weekdays.sorted() : []
        requestedDayOfMonth = Self.requestedDayOfMonth(for: normalizedDraft)
        requestedMonthOfYear = normalizedDraft.frequency == .yearly ? normalizedDraft.monthOfYear : nil
        requestedEndType = normalizedDraft.frequency == .none ? ChoreRecurrenceEndType.afterCount.rawValue : normalizedDraft.endType.rawValue
        requestedEndsOn = normalizedDraft.frequency != .none && normalizedDraft.endType == .onDate
            ? normalizedDraft.endsOn.map { ChoreDateOnlyFormatter.string(from: $0, timezone: normalizedDraft.timezone) }
            : nil
        requestedOccurrenceCount = Self.requestedOccurrenceCount(for: normalizedDraft)
        requestedTimezone = normalizedDraft.timezone
        requestedAssigneeIds = normalizedDraft.assignmentMode == .open ? [] : normalizedDraft.assigneeIds
    }

    private static func requestedDayOfMonth(for draft: ChoreTemplateDraft) -> Int? {
        switch draft.frequency {
        case .monthly, .yearly:
            return draft.dayOfMonth
        case .none, .daily, .weekly:
            return nil
        }
    }

    private static func requestedCompletionMode(for draft: ChoreTemplateDraft) -> ChoreCompletionMode {
        if draft.assignmentMode == .open || draft.assigneeIds.count <= 1 {
            return .single
        }

        return .everyone
    }

    private static func requestedOccurrenceCount(for draft: ChoreTemplateDraft) -> Int? {
        if draft.frequency == .none {
            return 1
        }

        return draft.endType == .afterCount ? draft.occurrenceCount : nil
    }

    enum CodingKeys: String, CodingKey {
        case requestedHomeId = "requested_home_id"
        case requestedChoreId = "requested_template_id"
        case requestedTitle = "requested_title"
        case requestedDescription = "requested_description"
        case requestedInstructions = "requested_instructions"
        case requestedCategoryId = "requested_category_id"
        case requestedRoomId = "requested_room_id"
        case requestedAssignmentMode = "requested_assignment_mode"
        case requestedCompletionMode = "requested_completion_mode"
        case requestedPointsValue = "requested_points_value"
        case requestedRequiresApproval = "requested_requires_approval"
        case requestedRequiresPhoto = "requested_requires_photo"
        case requestedFrequency = "requested_frequency"
        case requestedIntervalValue = "requested_interval_value"
        case requestedStartDate = "requested_start_date"
        case requestedDueTime = "requested_due_time"
        case requestedDurationMinutes = "requested_duration_minutes"
        case requestedIsAllDay = "requested_is_all_day"
        case requestedWeekdays = "requested_weekdays"
        case requestedDayOfMonth = "requested_day_of_month"
        case requestedMonthOfYear = "requested_month_of_year"
        case requestedEndType = "requested_end_type"
        case requestedEndsOn = "requested_ends_on"
        case requestedOccurrenceCount = "requested_occurrence_count"
        case requestedTimezone = "requested_timezone"
        case requestedAssigneeIds = "requested_assignee_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestedHomeId, forKey: .requestedHomeId)
        try encodeOptional(requestedChoreId, forKey: .requestedChoreId, into: &container)
        try container.encode(requestedTitle, forKey: .requestedTitle)
        try encodeOptional(requestedDescription, forKey: .requestedDescription, into: &container)
        try encodeOptional(requestedInstructions, forKey: .requestedInstructions, into: &container)
        try encodeOptional(requestedCategoryId, forKey: .requestedCategoryId, into: &container)
        try encodeOptional(requestedRoomId, forKey: .requestedRoomId, into: &container)
        try container.encode(requestedAssignmentMode, forKey: .requestedAssignmentMode)
        try container.encode(requestedCompletionMode, forKey: .requestedCompletionMode)
        try container.encode(requestedPointsValue, forKey: .requestedPointsValue)
        try container.encode(requestedRequiresApproval, forKey: .requestedRequiresApproval)
        try container.encode(requestedRequiresPhoto, forKey: .requestedRequiresPhoto)
        try container.encode(requestedFrequency, forKey: .requestedFrequency)
        try container.encode(requestedIntervalValue, forKey: .requestedIntervalValue)
        try container.encode(requestedStartDate, forKey: .requestedStartDate)
        try encodeOptional(requestedDueTime, forKey: .requestedDueTime, into: &container)
        try container.encode(requestedDurationMinutes, forKey: .requestedDurationMinutes)
        try container.encode(requestedIsAllDay, forKey: .requestedIsAllDay)
        try container.encode(requestedWeekdays, forKey: .requestedWeekdays)
        try encodeOptional(requestedDayOfMonth, forKey: .requestedDayOfMonth, into: &container)
        try encodeOptional(requestedMonthOfYear, forKey: .requestedMonthOfYear, into: &container)
        try container.encode(requestedEndType, forKey: .requestedEndType)
        try encodeOptional(requestedEndsOn, forKey: .requestedEndsOn, into: &container)
        try encodeOptional(requestedOccurrenceCount, forKey: .requestedOccurrenceCount, into: &container)
        try container.encode(requestedTimezone, forKey: .requestedTimezone)
        try container.encode(requestedAssigneeIds, forKey: .requestedAssigneeIds)
    }

    private func encodeOptional<Value: Encodable>(
        _ value: Value?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

private struct GenerateChoreOccurrencesRPCParameters: Encodable {
    let requestedChoreId: UUID
    let generateThrough: String

    init(templateId: UUID, through: Date, timezone: String) {
        requestedChoreId = templateId
        generateThrough = ChoreDateOnlyFormatter.string(from: through, timezone: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case requestedChoreId = "requested_template_id"
        case generateThrough = "generate_through"
    }
}

private struct GenerateHomeChoreOccurrencesRPCParameters: Encodable {
    let requestedHomeId: UUID
    let generateThrough: String

    init(homeId: UUID, through: Date, timezone: String) {
        requestedHomeId = homeId
        generateThrough = ChoreDateOnlyFormatter.string(from: through, timezone: timezone)
    }

    enum CodingKeys: String, CodingKey {
        case requestedHomeId = "requested_home_id"
        case generateThrough = "generate_through"
    }
}

private struct RequestedOccurrenceRPCParameters: Encodable {
    let requestedOccurrenceId: UUID

    enum CodingKeys: String, CodingKey {
        case requestedOccurrenceId = "requested_occurrence_id"
    }
}

private struct StartChoreRPCParameters: Encodable {
    let requestedOccurrenceId: UUID

    enum CodingKeys: String, CodingKey {
        case requestedOccurrenceId = "requested_occurrence_id"
    }
}

private struct SubmitChoreRPCParameters: Encodable {
    let requestedOccurrenceId: UUID
    let requestedCompletionNote: String?
    let requestedPhotoPath: String?

    enum CodingKeys: String, CodingKey {
        case requestedOccurrenceId = "requested_occurrence_id"
        case requestedCompletionNote = "requested_completion_note"
        case requestedPhotoPath = "requested_photo_path"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestedOccurrenceId, forKey: .requestedOccurrenceId)
        try encodeOptional(requestedCompletionNote, forKey: .requestedCompletionNote, into: &container)
        try encodeOptional(requestedPhotoPath, forKey: .requestedPhotoPath, into: &container)
    }
}

private struct ReviewChoreSubmissionRPCParameters: Encodable {
    let requestedSubmissionId: UUID
    let requestedDecision: String
    let requestedAdminNote: String?
    let requestedPointsAwarded: Int?

    enum CodingKeys: String, CodingKey {
        case requestedSubmissionId = "requested_submission_id"
        case requestedDecision = "requested_decision"
        case requestedAdminNote = "requested_admin_note"
        case requestedPointsAwarded = "requested_points_awarded"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestedSubmissionId, forKey: .requestedSubmissionId)
        try container.encode(requestedDecision, forKey: .requestedDecision)
        try encodeOptional(requestedAdminNote, forKey: .requestedAdminNote, into: &container)
        try encodeOptional(requestedPointsAwarded, forKey: .requestedPointsAwarded, into: &container)
    }
}

private func encodeOptional<Value: Encodable, Key: CodingKey>(
    _ value: Value?,
    forKey key: Key,
    into container: inout KeyedEncodingContainer<Key>
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}

private struct HomeIdParameters: Encodable {
    let homeId: UUID

    enum CodingKeys: String, CodingKey {
        case homeId = "requested_home_id"
    }
}

private struct ChoreHistoryRPCParameters: Encodable {
    let homeId: UUID
    let userId: UUID
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case homeId = "requested_home_id"
        case userId = "requested_user_id"
        case limit = "requested_limit"
        case offset = "requested_offset"
    }
}

private struct AdjustChorePointsRPCParameters: Encodable {
    let homeId: UUID
    let userId: UUID
    let points: Int
    let description: String
    let transactionAt: String

    init(homeId: UUID, userId: UUID, points: Int, description: String, transactionAt: Date) {
        self.homeId = homeId
        self.userId = userId
        self.points = points
        self.description = description
        self.transactionAt = ChoreTimestampFormatter.string(from: transactionAt)
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "requested_home_id"
        case userId = "requested_user_id"
        case points = "requested_points"
        case description = "requested_description"
        case transactionAt = "requested_transaction_at"
    }
}

private struct RewardTitleRow: Decodable {
    let displayTitle: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
    }
}
