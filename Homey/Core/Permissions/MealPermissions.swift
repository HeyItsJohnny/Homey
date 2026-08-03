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
        canDeleteCollections: Bool
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
                canDeleteCollections: false
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
        canDeleteCollections: true
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
        canDeleteCollections: false
    )
}
