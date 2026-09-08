import Foundation

struct AutoPlanEngine: Sendable {
    private var calendar: Calendar
    private let seed: Int
    private let scoring = AutoPlanScoringConstants()

    init(calendar: Calendar = .autoupdatingCurrent, seed: Int = 0) {
        self.calendar = calendar
        self.seed = seed
    }

    func generateDraft(
        homeId: UUID,
        weekRange: (start: Date, end: Date),
        weekDays: [Date],
        eligibleMeals: [Meal],
        favoritesByMember: [UUID: Set<UUID>],
        members: [AutoPlanMember],
        existingPlannedMeals: [PlannedMeal],
        recentPlannedMeals: [PlannedMeal],
        configuration: AutoPlanConfiguration
    ) -> AutoPlanDraft {
        let today = calendar.startOfDay(for: Date())
        var slots = buildSlots(
            weekDays: weekDays,
            selectedDates: configuration.selectedDates,
            selectedMealTypes: configuration.selectedMealTypes,
            existingPlannedMeals: existingPlannedMeals,
            today: today
        )
        for index in slots.indices where slots[index].isFilled {
            slots[index].suggestion = AutoPlanSuggestion(
                meal: slots[index].existingPlannedMeals.first?.meal,
                status: .existing,
                attributedMemberId: nil,
                favoriteMemberIds: [],
                score: 0,
                explanation: "Already planned"
            )
        }
        let missingSlotIndices = slots.indices.filter { !slots[$0].isFilled }
        var suggestionCounts = Dictionary(uniqueKeysWithValues: members.map { ($0.id, 0) })
        var selectedMealIds = Set<UUID>()
        let targetFavoriteCount = favoriteTargetCount(for: missingSlotIndices.map { slots[$0] })
        var generatedSuggestionCount = 0
        var favoriteSuggestionCount = 0

        #if DEBUG
        let selectedDayCount = weekDays.filter { day in
            configuration.selectedDates.contains { calendar.isDate($0, inSameDayAs: day) }
        }.count
        let eligibleDayCount = weekDays.filter { day in
            configuration.selectedDates.contains { calendar.isDate($0, inSameDayAs: day) }
                && calendar.startOfDay(for: day) >= today
        }.count
        print("========== AUTO PLAN SLOT FILTER ==========")
        print("today_home_local_date: \(today)")
        print("selected_week_start: \(weekRange.start)")
        print("selected_week_end: \(weekRange.end)")
        print("past_slots_skipped: \(max(0, selectedDayCount - eligibleDayCount) * configuration.selectedMealTypes.count)")
        print("eligible_slots: \(slots.count)")
        print("existing_slots: \(slots.filter(\.isFilled).count)")
        print("missing_slots: \(missingSlotIndices.count)")
        print("selected_recipe_pool_mode: \(configuration.recipePool.rawValue)")
        print("missing_slot_count: \(missingSlotIndices.count)")
        print("target_favorite_ratio: \(AutoPlanConfiguration.defaultFavoriteTargetRatio)")
        print("target_favorite_count: \(targetFavoriteCount)")
        #endif

        for index in missingSlotIndices {
            guard let suggestion = chooseSuggestion(
                for: slots[index],
                eligibleMeals: eligibleMeals,
                favoritesByMember: favoritesByMember,
                members: members,
                existingPlannedMeals: existingPlannedMeals,
                recentPlannedMeals: recentPlannedMeals,
                selectedMealIds: selectedMealIds,
                suggestionCounts: suggestionCounts,
                configuration: configuration,
                targetFavoriteCount: targetFavoriteCount,
                generatedSuggestionCount: generatedSuggestionCount,
                favoriteSuggestionCount: favoriteSuggestionCount
            ) else {
                slots[index].suggestion = AutoPlanSuggestion(
                    meal: nil,
                    status: .noSuggestion,
                    attributedMemberId: nil,
                    favoriteMemberIds: [],
                    score: 0,
                    explanation: "No eligible recipe"
                )
                continue
            }

            slots[index].suggestion = suggestion
            generatedSuggestionCount += 1
            if !suggestion.favoriteMemberIds.isEmpty {
                favoriteSuggestionCount += 1
            }
            if let mealId = suggestion.meal?.id {
                selectedMealIds.insert(mealId)
            }
            if let memberId = suggestion.attributedMemberId {
                suggestionCounts[memberId, default: 0] += 1
            }
        }

        #if DEBUG
        let generatedCount = slots.filter { $0.suggestion?.status == .suggested || $0.suggestion?.status == .manuallySelected }.count
        print("future_slots_generated: \(generatedCount)")
        print("favorite_suggestions_selected: \(favoriteSuggestionCount)")
        print("final_favorite_suggestion_ratio: \(generatedCount == 0 ? 0 : Double(favoriteSuggestionCount) / Double(generatedCount))")
        #endif

        return AutoPlanDraft(
            homeId: homeId,
            weekStart: weekRange.start,
            weekEnd: weekRange.end,
            configuration: configuration,
            slots: slots,
            memberSuggestionCounts: suggestionCounts,
            generatedAt: Date()
        )
    }

    func reroll(
        slotId: AutoPlanSlotID,
        draft: AutoPlanDraft,
        eligibleMeals: [Meal],
        favoritesByMember: [UUID: Set<UUID>],
        members: [AutoPlanMember],
        existingPlannedMeals: [PlannedMeal],
        recentPlannedMeals: [PlannedMeal]
    ) -> AutoPlanDraft {
        var updated = draft
        guard let slotIndex = updated.slots.firstIndex(where: { $0.id == slotId }) else {
            return draft
        }

        let previousMealId = updated.slots[slotIndex].suggestion?.meal?.id
        var selectedMealIds = Set(updated.slots.compactMap { slot -> UUID? in
            guard slot.id != slotId, slot.suggestion?.isCreatable == true else { return nil }
            return slot.suggestion?.meal?.id
        })
        var counts = generatedCounts(from: updated.slots, members: members, excluding: slotId)

        let excludedMealIds = previousMealId.map { Set([$0]) } ?? []
        let suggestion = chooseSuggestion(
            for: updated.slots[slotIndex],
            eligibleMeals: eligibleMeals,
            favoritesByMember: favoritesByMember,
            members: members,
            existingPlannedMeals: existingPlannedMeals,
            recentPlannedMeals: recentPlannedMeals,
            selectedMealIds: selectedMealIds,
            suggestionCounts: counts,
            configuration: updated.configuration,
            excludedMealIds: excludedMealIds,
            targetFavoriteCount: favoriteTargetCount(for: updated.slots),
            generatedSuggestionCount: selectedMealIds.count,
            favoriteSuggestionCount: favoriteSuggestionCount(in: updated.slots, excluding: slotId)
        )

        updated.slots[slotIndex].suggestion = suggestion ?? AutoPlanSuggestion(
            meal: nil,
            status: .noSuggestion,
            attributedMemberId: nil,
            favoriteMemberIds: [],
            score: 0,
            explanation: "No alternate recipe"
        )
        if let mealId = suggestion?.meal?.id {
            selectedMealIds.insert(mealId)
        }
        if let memberId = suggestion?.attributedMemberId {
            counts[memberId, default: 0] += 1
        }
        updated.memberSuggestionCounts = counts
        updated.generatedAt = Date()
        return updated
    }

    private func buildSlots(
        weekDays: [Date],
        selectedDates: Set<Date>,
        selectedMealTypes: Set<MealType>,
        existingPlannedMeals: [PlannedMeal],
        today: Date
    ) -> [AutoPlanSlot] {
        let existingMealsBySlot = Dictionary(grouping: existingPlannedMeals) { plannedMeal in
            AutoPlanSlotID(dayKey: dayKey(for: plannedMeal.startsAt), mealType: plannedMeal.mealType)
        }

        return weekDays
            .filter { day in
                selectedDates.contains { calendar.isDate($0, inSameDayAs: day) }
                    && calendar.startOfDay(for: day) >= today
            }
            .flatMap { day in
                selectedMealTypes.sortedByMealPlannerOrder().map { mealType in
                    let slotId = AutoPlanSlotID(dayKey: dayKey(for: day), mealType: mealType)
                    let existing = existingPlannedMeals.filter {
                        calendar.isDate($0.startsAt, inSameDayAs: day) && $0.mealType == mealType
                    } + (existingMealsBySlot[slotId] ?? [])
                    return AutoPlanSlot(
                        id: slotId,
                        date: calendar.startOfDay(for: day),
                        mealType: mealType,
                        existingPlannedMeals: Array(Set(existing)),
                        suggestion: nil
                    )
                }
            }
    }

    private func chooseSuggestion(
        for slot: AutoPlanSlot,
        eligibleMeals: [Meal],
        favoritesByMember: [UUID: Set<UUID>],
        members: [AutoPlanMember],
        existingPlannedMeals: [PlannedMeal],
        recentPlannedMeals: [PlannedMeal],
        selectedMealIds: Set<UUID>,
        suggestionCounts: [UUID: Int],
        configuration: AutoPlanConfiguration,
        excludedMealIds: Set<UUID> = [],
        targetFavoriteCount: Int,
        generatedSuggestionCount: Int,
        favoriteSuggestionCount: Int
    ) -> AutoPlanSuggestion? {
        let candidateMeals = eligibleMeals.filter { meal in
            meal.homeId == slot.existingPlannedMeals.first?.meal.homeId || slot.existingPlannedMeals.isEmpty
        }.filter { meal in
            !meal.isArchived
                && meal.mealTypes.contains(slot.mealType)
                && !excludedMealIds.contains(meal.id)
                && !slot.existingPlannedMeals.contains { $0.meal.id == meal.id }
                && (configuration.allowsRepeats || !existingPlannedMeals.contains { $0.meal.id == meal.id })
        }

        let candidates = candidateMeals.compactMap { meal -> AutoPlanCandidate? in
            let favoriteMemberIds = members
                .map(\.id)
                .filter { favoritesByMember[$0, default: []].contains(meal.id) }

            if !configuration.allowsRepeats && selectedMealIds.contains(meal.id) {
                return nil
            }

            let attribution = configuration.recipePool == .includeFavorites
                ? attributionMember(favoriteMemberIds: favoriteMemberIds, suggestionCounts: suggestionCounts)
                : nil
            let score = score(
                meal: meal,
                slot: slot,
                favoriteMemberIds: favoriteMemberIds,
                attributionMemberId: attribution,
                suggestionCounts: suggestionCounts,
                existingPlannedMeals: existingPlannedMeals,
                recentPlannedMeals: recentPlannedMeals,
                selectedMealIds: selectedMealIds,
                configuration: configuration,
                targetFavoriteCount: targetFavoriteCount,
                generatedSuggestionCount: generatedSuggestionCount,
                favoriteSuggestionCount: favoriteSuggestionCount
            )
            return AutoPlanCandidate(meal: meal, favoriteMemberIds: favoriteMemberIds, attributionMemberId: attribution, score: score)
        }

        #if DEBUG
        let favoriteCandidateCount = candidates.filter { !$0.favoriteMemberIds.isEmpty }.count
        let nonFavoriteCandidateCount = candidates.count - favoriteCandidateCount
        print("Auto Plan candidate pool for \(slot.id.description)")
        print("eligible_favorite_candidate_count: \(favoriteCandidateCount)")
        print("eligible_non_favorite_candidate_count: \(nonFavoriteCandidateCount)")
        print("favorite_suggestions_selected_so_far: \(favoriteSuggestionCount)")
        print("favorite_suggestions_remaining: \(max(0, targetFavoriteCount - favoriteSuggestionCount))")
        #endif

        guard let chosen = candidates.sorted(by: candidateSort).first else {
            return nil
        }

        #if DEBUG
        print("selected_candidate_favorite_status: \(!chosen.favoriteMemberIds.isEmpty)")
        if let memberId = chosen.attributionMemberId {
            print("attribution_member: \(memberId.uuidString)")
        }
        #endif

        return AutoPlanSuggestion(
            meal: chosen.meal,
            status: .suggested,
            attributedMemberId: chosen.attributionMemberId,
            favoriteMemberIds: chosen.favoriteMemberIds,
            score: chosen.score,
            explanation: "Score \(chosen.score)"
        )
    }

    private func score(
        meal: Meal,
        slot: AutoPlanSlot,
        favoriteMemberIds: [UUID],
        attributionMemberId: UUID?,
        suggestionCounts: [UUID: Int],
        existingPlannedMeals: [PlannedMeal],
        recentPlannedMeals: [PlannedMeal],
        selectedMealIds: Set<UUID>,
        configuration: AutoPlanConfiguration,
        targetFavoriteCount: Int,
        generatedSuggestionCount: Int,
        favoriteSuggestionCount: Int
    ) -> Int {
        var score = scoring.base
        if configuration.recipePool == .includeFavorites {
            let isBelowFavoriteTarget = shouldPreferFavorite(
                targetFavoriteCount: targetFavoriteCount,
                generatedSuggestionCount: generatedSuggestionCount,
                favoriteSuggestionCount: favoriteSuggestionCount
            )
            if let attributionMemberId, favoriteMemberIds.contains(attributionMemberId) {
                score += isBelowFavoriteTarget ? scoring.priorityMemberFavoriteBonus : scoring.satisfiedTargetFavoriteBonus
            } else if !favoriteMemberIds.isEmpty {
                score += isBelowFavoriteTarget ? scoring.otherMemberFavoriteBonus : 0
            }
            score += max(0, favoriteMemberIds.count - 1) * scoring.additionalFavoriteMemberBonus
        }

        let plannedThisWeek = existingPlannedMeals.contains { $0.meal.id == meal.id }
        if plannedThisWeek {
            score -= scoring.plannedThisWeekPenalty
        } else {
            score += scoring.notPlannedThisWeekBonus
        }

        let recentUse = recentPlannedMeals.contains { $0.meal.id == meal.id }
        if recentUse {
            score -= scoring.recentUsePenalty
        } else {
            score += scoring.notRecentlyUsedBonus
        }

        let adjacentUse = (existingPlannedMeals + recentPlannedMeals).contains {
            $0.meal.id == meal.id && abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.startsAt), to: slot.date).day ?? 99) <= 1
        }
        score += adjacentUse ? -scoring.adjacentUsePenalty : scoring.notAdjacentBonus

        if selectedMealIds.contains(meal.id) {
            score -= scoring.draftRepeatPenalty
        }
        if meal.updatedAt > Date().addingTimeInterval(-14 * 24 * 60 * 60) {
            score += scoring.recentlyUpdatedBonus
        }
        if configuration.recipePool == .includeFavorites, let attributionMemberId {
            let minCount = suggestionCounts.values.min() ?? 0
            let extra = max(0, suggestionCounts[attributionMemberId, default: 0] - minCount)
            score -= extra * scoring.overrepresentedMemberPenalty
        }
        return score
    }

    private func favoriteTargetCount(for slots: [AutoPlanSlot]) -> Int {
        let missingSlotCount = slots.filter { !$0.isFilled }.count
        return Int((Double(missingSlotCount) * AutoPlanConfiguration.defaultFavoriteTargetRatio).rounded())
    }

    private func shouldPreferFavorite(targetFavoriteCount: Int, generatedSuggestionCount: Int, favoriteSuggestionCount: Int) -> Bool {
        guard targetFavoriteCount > 0 else { return false }
        let desiredFavoritesByThisPoint = min(
            targetFavoriteCount,
            Int((Double(generatedSuggestionCount + 1) * AutoPlanConfiguration.defaultFavoriteTargetRatio).rounded())
        )
        return favoriteSuggestionCount < desiredFavoritesByThisPoint
    }

    private func favoriteSuggestionCount(in slots: [AutoPlanSlot], excluding slotId: AutoPlanSlotID? = nil) -> Int {
        slots.filter { slot in
            slot.id != slotId
                && slot.suggestion?.isCreatable == true
                && slot.suggestion?.favoriteMemberIds.isEmpty == false
        }.count
    }

    private func attributionMember(favoriteMemberIds: [UUID], suggestionCounts: [UUID: Int]) -> UUID? {
        favoriteMemberIds
            .sorted { lhs, rhs in
                let lhsCount = suggestionCounts[lhs, default: 0]
                let rhsCount = suggestionCounts[rhs, default: 0]
                if lhsCount != rhsCount { return lhsCount < rhsCount }
                return tieBreakValue(for: lhs) < tieBreakValue(for: rhs)
            }
            .first
    }

    private func generatedCounts(from slots: [AutoPlanSlot], members: [AutoPlanMember], excluding slotId: AutoPlanSlotID? = nil) -> [UUID: Int] {
        var counts = Dictionary(uniqueKeysWithValues: members.map { ($0.id, 0) })
        for slot in slots where slot.id != slotId {
            guard let memberId = slot.suggestion?.attributedMemberId,
                  slot.suggestion?.status == .suggested else { continue }
            counts[memberId, default: 0] += 1
        }
        return counts
    }

    private func candidateSort(_ lhs: AutoPlanCandidate, _ rhs: AutoPlanCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return tieBreakValue(for: lhs.meal.id) < tieBreakValue(for: rhs.meal.id)
    }

    private func tieBreakValue(for id: UUID) -> Int {
        abs(id.uuidString.hashValue ^ seed)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct AutoPlanCandidate: Hashable {
    let meal: Meal
    let favoriteMemberIds: [UUID]
    let attributionMemberId: UUID?
    let score: Int
}

private struct AutoPlanScoringConstants: Sendable {
    let base = 50
    let priorityMemberFavoriteBonus = 35
    let satisfiedTargetFavoriteBonus = 5
    let otherMemberFavoriteBonus = 10
    let additionalFavoriteMemberBonus = 3
    let notPlannedThisWeekBonus = 25
    let notRecentlyUsedBonus = 20
    let notAdjacentBonus = 15
    let recentlyUpdatedBonus = 5
    let plannedThisWeekPenalty = 35
    let recentUsePenalty = 30
    let adjacentUsePenalty = 40
    let draftRepeatPenalty = 45
    let overrepresentedMemberPenalty = 25
}

private extension Sequence where Element == MealType {
    func sortedByMealPlannerOrder() -> [MealType] {
        sorted { lhs, rhs in lhs.autoPlanSortOrder < rhs.autoPlanSortOrder }
    }
}

private extension MealType {
    var autoPlanSortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        case .dessert: return 4
        case .drink: return 5
        }
    }
}
