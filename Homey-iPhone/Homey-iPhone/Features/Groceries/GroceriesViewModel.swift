import Combine
import Foundation

@MainActor
final class GroceriesViewModel: ObservableObject {
    @Published private(set) var list: GroceryList?
    @Published private(set) var items: [GroceryItemWithSources] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isClearing = false
    @Published private(set) var mutatingItemIDs: Set<UUID> = []
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let repository: GroceryRepository

    init(repository: GroceryRepository? = nil) {
        self.repository = repository ?? GroceryRepository()
    }

    var groupedItems: [(category: GroceryCategory, items: [GroceryItemWithSources])] {
        GroceryCategory.allCases.compactMap { category in
            let matching = items.filter { $0.item.category == category }.sorted { lhs, rhs in
                if lhs.item.isChecked != rhs.item.isChecked { return !lhs.item.isChecked }
                return lhs.item.ingredientName.localizedCaseInsensitiveCompare(rhs.item.ingredientName) == .orderedAscending
            }
            return matching.isEmpty ? nil : (category, matching)
        }
    }

    var checkedItemCount: Int { items.count { $0.item.isChecked } }

    func load(homeID: UUID) async {
        isLoading = true
        errorMessage = nil
        do {
            let resolvedList = try await repository.defaultList(homeID: homeID)
            list = resolvedList
            items = try await repository.loadItemsWithSources(listID: resolvedList.id)
        } catch {
            errorMessage = "Unable to load groceries."
        }
        isLoading = false
    }

    func addManualItem(name: String, category: GroceryCategory, homeID: UUID) async -> Bool {
        guard let list else {
            errorMessage = "Unable to load groceries."
            return false
        }
        do {
            let result = try await repository.addManualItemWithResult(
                listID: list.id,
                homeID: homeID,
                displayName: name,
                category: category
            )
            if result.wasCreated {
                items.append(GroceryItemWithSources(item: result.item, sources: []))
                noticeMessage = "Added \(result.item.ingredientName)."
            } else {
                noticeMessage = "\(result.item.ingredientName) is already on your grocery list."
            }
            return true
        } catch GroceryRepositoryError.emptyItemName {
            errorMessage = "Enter an item name."
            return false
        } catch {
            errorMessage = "Homey couldn't add that grocery item."
        }
        return false
    }

    func toggleChecked(_ display: GroceryItemWithSources) async {
        guard !mutatingItemIDs.contains(display.id) else { return }
        let original = display.item
        replaceItem(original.replacing(isChecked: !original.isChecked), sources: display.sources)
        mutatingItemIDs.insert(display.id)
        defer { mutatingItemIDs.remove(display.id) }
        do {
            let saved = try await repository.setChecked(!original.isChecked, itemID: original.id)
            replaceItem(saved, sources: display.sources)
        } catch {
            replaceItem(original, sources: display.sources)
            errorMessage = "Homey couldn't update that item."
        }
    }

    func update(_ display: GroceryItemWithSources, name: String, category: GroceryCategory) async -> Bool {
        guard !mutatingItemIDs.contains(display.id) else { return false }
        mutatingItemIDs.insert(display.id)
        defer { mutatingItemIDs.remove(display.id) }
        do {
            let result = try await repository.updateItem(display.item, name: name, category: category)
            if result.didMerge, let list {
                items = try await repository.loadItemsWithSources(listID: list.id)
                noticeMessage = "Combined with \(result.item.ingredientName)."
            } else {
                replaceItem(result.item, sources: display.sources)
            }
            return true
        } catch GroceryRepositoryError.emptyItemName {
            errorMessage = "Enter an item name."
            return false
        } catch {
            errorMessage = "Homey couldn't update that grocery item."
            return false
        }
    }

    func delete(_ display: GroceryItemWithSources) async {
        guard !mutatingItemIDs.contains(display.id) else { return }
        mutatingItemIDs.insert(display.id)
        defer { mutatingItemIDs.remove(display.id) }
        do {
            try await repository.deleteItem(itemID: display.id)
            items.removeAll { $0.id == display.id }
        } catch {
            errorMessage = "Homey couldn't delete that item."
        }
    }

    func clearCheckedItems() async -> Bool {
        guard let list, checkedItemCount > 0, !isClearing else { return false }
        isClearing = true
        defer { isClearing = false }
        do {
            try await repository.clearCheckedItems(listID: list.id)
            items = try await repository.loadItemsWithSources(listID: list.id)
            return true
        } catch {
            items = (try? await repository.loadItemsWithSources(listID: list.id)) ?? items
            errorMessage = "Some grocery items couldn't be removed."
            return false
        }
    }

    func clearAllItems() async -> Bool {
        guard let list, !items.isEmpty, !isClearing else { return false }
        isClearing = true
        defer { isClearing = false }
        do {
            try await repository.clearAllItems(listID: list.id)
            items = try await repository.loadItemsWithSources(listID: list.id)
            return true
        } catch {
            items = (try? await repository.loadItemsWithSources(listID: list.id)) ?? items
            errorMessage = "Unable to clear the grocery list."
            return false
        }
    }

    private func replaceItem(_ item: GroceryItem, sources: [GrocerySource]) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = GroceryItemWithSources(item: item, sources: sources)
    }
}
