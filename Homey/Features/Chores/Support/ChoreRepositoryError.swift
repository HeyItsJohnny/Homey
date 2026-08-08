import Foundation
import PostgREST

enum ChoreRepositoryError: LocalizedError, Equatable {
    case authenticationRequired
    case ownerRequired
    case ownerOrAdminRequired
    case homeMembershipRequired
    case choreAlreadyClaimed
    case choreNotAssignedToUser
    case invalidRecurrenceConfiguration
    case requiredPhotoMissing
    case submissionAlreadyReviewed
    case calendarSynchronizationFailed
    case duplicateGenerationIgnored
    case choreCategoryUnavailable
    case invalidDateRange
    case invalidPointAdjustment
    case pointRemovalExceedsBalance
    case adjustmentDescriptionRequired
    case invalidDraft(ChoreValidationError)
    case loadFailed
    case saveFailed
    case mutationFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Your session has expired. Please sign in again."
        case .ownerRequired:
            return "Only the Home owner can clear chores."
        case .ownerOrAdminRequired:
            return "Only Home owners and admins can manage this chore area."
        case .homeMembershipRequired:
            return "You need to be a member of this Home to use Chores."
        case .choreAlreadyClaimed:
            return "This chore has already been claimed."
        case .choreNotAssignedToUser:
            return "This chore is not assigned to you."
        case .invalidRecurrenceConfiguration:
            return "The chore recurrence settings are invalid."
        case .requiredPhotoMissing:
            return "This chore requires a photo before submission."
        case .submissionAlreadyReviewed:
            return "This submission has already been reviewed."
        case .calendarSynchronizationFailed:
            return "We could not synchronize this chore with the calendar."
        case .duplicateGenerationIgnored:
            return "Duplicate chore generation was safely ignored."
        case .choreCategoryUnavailable:
            return "Homey could not prepare the Chore calendar category for this Home."
        case .invalidDateRange:
            return "Choose a valid date range."
        case .invalidPointAdjustment:
            return "Enter a valid points adjustment."
        case .pointRemovalExceedsBalance:
            return "Cannot remove more points than this member currently has available."
        case .adjustmentDescriptionRequired:
            return "Description is required."
        case .invalidDraft(let validationError):
            return validationError.localizedDescription
        case .loadFailed:
            return "We could not load chores."
        case .saveFailed:
            return "We could not save this chore."
        case .mutationFailed:
            return "We could not update this chore."
        case .notFound:
            return "We could not find that chore."
        }
    }

    static func map(_ error: Error) -> ChoreRepositoryError {
        if let choreError = error as? ChoreRepositoryError {
            return choreError
        }

        if let validationError = error as? ChoreValidationError {
            return .invalidDraft(validationError)
        }

        guard let postgrestError = error as? PostgrestError else {
            return .mutationFailed
        }

        let message = postgrestError.message.lowercased()
        let detail = (postgrestError.detail ?? "").lowercased()
        let combined = message + " " + detail

        if combined.contains("jwt") || combined.contains("auth") || combined.contains("session") {
            return .authenticationRequired
        }
        if combined.contains("owner") || combined.contains("admin") || combined.contains("permission") || combined.contains("not authorized") {
            return .ownerOrAdminRequired
        }
        if combined.contains("membership") || combined.contains("member of this home") {
            return .homeMembershipRequired
        }
        if combined.contains("already claimed") || combined.contains("claim") && combined.contains("conflict") {
            return .choreAlreadyClaimed
        }
        if combined.contains("not assigned") {
            return .choreNotAssignedToUser
        }
        if combined.contains("recurrence") || combined.contains("frequency") || combined.contains("weekday") {
            return .invalidRecurrenceConfiguration
        }
        if combined.contains("photo") && combined.contains("required") {
            return .requiredPhotoMissing
        }
        if combined.contains("already reviewed") || combined.contains("reviewed") && combined.contains("submission") {
            return .submissionAlreadyReviewed
        }
        if combined.contains("duplicate") || combined.contains("unique") {
            return .duplicateGenerationIgnored
        }
        if combined.contains("cannot remove more points") || combined.contains("negative balance") {
            return .pointRemovalExceedsBalance
        }
        if combined.contains("description") && combined.contains("required") {
            return .adjustmentDescriptionRequired
        }
        if combined.contains("point adjustment") || combined.contains("cannot be zero") {
            return .invalidPointAdjustment
        }

        return .mutationFailed
    }
}
