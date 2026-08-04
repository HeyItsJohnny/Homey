import Foundation

struct MealPermissions: Equatable, Hashable, Sendable {
    let canView: Bool
    let canCreate: Bool
    let canEdit: Bool
    let canArchive: Bool
    let canDelete: Bool
    let canFavorite: Bool
    let canUploadPhotos: Bool
    let canDeletePhotos: Bool
    let canCreateCollections: Bool
    let canEditCollections: Bool
    let canDeleteCollections: Bool
    let canViewMealPlan: Bool
    let canPlanMeals: Bool
    let canRunAutoPlan: Bool
    let canApplyAutoPlan: Bool
    let canRemovePlannedMeals: Bool
    let canReplaceExistingPlan: Bool
    let canClearMealPlan: Bool

    init(
        canView: Bool,
        canCreate: Bool,
        canEdit: Bool,
        canArchive: Bool,
        canDelete: Bool,
        canFavorite: Bool,
        canUploadPhotos: Bool,
        canDeletePhotos: Bool,
        canCreateCollections: Bool,
        canEditCollections: Bool,
        canDeleteCollections: Bool,
        canViewMealPlan: Bool,
        canPlanMeals: Bool,
        canRunAutoPlan: Bool,
        canApplyAutoPlan: Bool,
        canRemovePlannedMeals: Bool,
        canReplaceExistingPlan: Bool,
        canClearMealPlan: Bool
    ) {
        self.canView = canView
        self.canCreate = canCreate
        self.canEdit = canEdit
        self.canArchive = canArchive
        self.canDelete = canDelete
        self.canFavorite = canFavorite
        self.canUploadPhotos = canUploadPhotos
        self.canDeletePhotos = canDeletePhotos
        self.canCreateCollections = canCreateCollections
        self.canEditCollections = canEditCollections
        self.canDeleteCollections = canDeleteCollections
        self.canViewMealPlan = canViewMealPlan
        self.canPlanMeals = canPlanMeals
        self.canRunAutoPlan = canRunAutoPlan
        self.canApplyAutoPlan = canApplyAutoPlan
        self.canRemovePlannedMeals = canRemovePlannedMeals
        self.canReplaceExistingPlan = canReplaceExistingPlan
        self.canClearMealPlan = canClearMealPlan
    }

    init(role: HomeMemberRole?) {
        switch role {
        case .owner, .admin:
            self = .all
        case .member:
            self = MealPermissions(
                canView: true,
                canCreate: true,
                canEdit: true,
                canArchive: true,
                canDelete: false,
                canFavorite: true,
                canUploadPhotos: true,
                canDeletePhotos: false,
                canCreateCollections: true,
                canEditCollections: true,
                canDeleteCollections: false,
                canViewMealPlan: true,
                canPlanMeals: true,
                canRunAutoPlan: true,
                canApplyAutoPlan: true,
                canRemovePlannedMeals: true,
                canReplaceExistingPlan: false,
                canClearMealPlan: false
            )
        case nil:
            self = .restrictive
        }
    }

    static let all = MealPermissions(
        canView: true,
        canCreate: true,
        canEdit: true,
        canArchive: true,
        canDelete: true,
        canFavorite: true,
        canUploadPhotos: true,
        canDeletePhotos: true,
        canCreateCollections: true,
        canEditCollections: true,
        canDeleteCollections: true,
        canViewMealPlan: true,
        canPlanMeals: true,
        canRunAutoPlan: true,
        canApplyAutoPlan: true,
        canRemovePlannedMeals: true,
        canReplaceExistingPlan: true,
        canClearMealPlan: true
    )

    static let restrictive = MealPermissions(
        canView: false,
        canCreate: false,
        canEdit: false,
        canArchive: false,
        canDelete: false,
        canFavorite: false,
        canUploadPhotos: false,
        canDeletePhotos: false,
        canCreateCollections: false,
        canEditCollections: false,
        canDeleteCollections: false,
        canViewMealPlan: false,
        canPlanMeals: false,
        canRunAutoPlan: false,
        canApplyAutoPlan: false,
        canRemovePlannedMeals: false,
        canReplaceExistingPlan: false,
        canClearMealPlan: false
    )
}
