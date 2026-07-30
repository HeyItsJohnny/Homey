import Combine
import Foundation
import SwiftUI

@MainActor
final class CalendarCategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [CalendarCategory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isDeleting = false
    @Published private(set) var isReordering = false
    @Published var errorMessage: String?

    private let calendarService: CalendarService
    private var activeHomeId: UUID?

    init(calendarService: CalendarService? = nil) {
        self.calendarService = calendarService ?? CalendarService()
    }

    func load(homeId: UUID?) async {
        guard let homeId else {
            activeHomeId = nil
            categories = []
            errorMessage = "Choose a Home to manage calendar categories."
            isLoading = false
            return
        }

        if activeHomeId != homeId {
            activeHomeId = homeId
            categories = []
            errorMessage = nil
        }

        await reload()
    }

    func reload() async {
        guard let activeHomeId else {
            categories = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            categories = try await calendarService.fetchCategories(homeId: activeHomeId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCategory(homeId: UUID?, name: String, colorHex: String, iconName: String?, canManage: Bool) async -> CalendarCategoryMutationResult {
        guard canManage else {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        }

        guard let homeId else {
            errorMessage = "Choose a Home before adding categories."
            return .failure
        }

        guard !isSaving else {
            return .failure
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            _ = try await calendarService.createCategory(homeId: homeId, name: name, colorHex: colorHex, iconName: iconName)
            await reload()
            postCalendarRefresh()
            return .success
        } catch CalendarServiceError.categoryPermissionDenied {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        } catch {
            errorMessage = error.localizedDescription
            return .failure
        }
    }

    func updateCategory(categoryId: UUID, name: String, colorHex: String, iconName: String?, canManage: Bool) async -> CalendarCategoryMutationResult {
        guard canManage else {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        }

        guard !isSaving else {
            return .failure
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await calendarService.updateCategory(categoryId: categoryId, name: name, colorHex: colorHex, iconName: iconName)
            await reload()
            postCalendarRefresh()
            return .success
        } catch CalendarServiceError.categoryPermissionDenied {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        } catch {
            errorMessage = error.localizedDescription
            return .failure
        }
    }

    func deleteCategory(categoryId: UUID, canManage: Bool) async -> CalendarCategoryMutationResult {
        guard canManage else {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        }

        guard !isDeleting else {
            return .failure
        }

        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await calendarService.deleteCategory(categoryId: categoryId)
            categories.removeAll { $0.id == categoryId }
            await reload()
            postCalendarRefresh()
            return .success
        } catch CalendarServiceError.categoryPermissionDenied {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        } catch {
            errorMessage = error.localizedDescription
            return .failure
        }
    }

    func moveCategories(from source: IndexSet, to destination: Int, homeId: UUID?, canManage: Bool) async -> CalendarCategoryMutationResult {
        guard canManage else {
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        }

        guard let homeId else {
            errorMessage = "Choose a Home before reordering categories."
            return .failure
        }

        guard !isReordering else {
            return .failure
        }

        let previousCategories = categories
        categories.move(fromOffsets: source, toOffset: destination)
        let orderedIds = categories.map(\.id)

        isReordering = true
        errorMessage = nil
        defer { isReordering = false }

        do {
            try await calendarService.reorderCategories(homeId: homeId, orderedCategoryIds: orderedIds)
            await reload()
            postCalendarRefresh()
            return .success
        } catch CalendarServiceError.categoryPermissionDenied {
            categories = previousCategories
            errorMessage = CalendarServiceError.categoryPermissionDenied.localizedDescription
            return .permissionDenied
        } catch {
            categories = previousCategories
            errorMessage = error.localizedDescription
            return .failure
        }
    }

    private func postCalendarRefresh() {
        NotificationCenter.default.post(name: .homeyCalendarEventsDidChange, object: nil)
    }
}

enum CalendarCategoryMutationResult: Equatable {
    case success
    case permissionDenied
    case failure
}
