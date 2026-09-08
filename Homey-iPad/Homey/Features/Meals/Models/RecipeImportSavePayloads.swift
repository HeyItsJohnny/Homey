import Foundation

struct UpdateRecipeImportTrackingPayload: Encodable, Hashable, Sendable {
    let status: String
    let completedAt: Date
    let globalRecipeId: UUID

    enum CodingKeys: String, CodingKey {
        case status
        case completedAt = "completed_at"
        case globalRecipeId = "global_recipe_id"
    }

    static func saved(globalRecipeId: UUID) -> UpdateRecipeImportTrackingPayload {
        UpdateRecipeImportTrackingPayload(
            status: "saved",
            completedAt: Date(),
            globalRecipeId: globalRecipeId
        )
    }
}
