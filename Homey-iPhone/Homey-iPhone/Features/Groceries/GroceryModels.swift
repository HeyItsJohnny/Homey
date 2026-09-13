import Foundation

enum GroceryCategory: String, Codable, CaseIterable, Identifiable {
    case produce = "Produce"
    case dairyAndEggs = "Dairy & Eggs"
    case meatAndSeafood = "Meat & Seafood"
    case bakery = "Bakery"
    case pantry = "Pantry"
    case frozen = "Frozen"
    case beverages = "Beverages"
    case snacks = "Snacks"
    case household = "Household"
    case personalCare = "Personal Care"
    case other = "Other"

    var id: String { rawValue }
}

enum GrocerySourceType: String, Codable, CaseIterable {
    case homeRecipe = "home_recipe"
    case mealEvent = "meal_event"
}

struct GroceryList: Identifiable, Decodable, Hashable {
    let id: UUID
    let homeID: UUID
    let name: String?
    let isDefault: Bool
    let createdBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case homeID = "home_id", isDefault = "is_default", createdBy = "created_by"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeID = try container.decode(UUID.self, forKey: .homeID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? true
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct GroceryItem: Identifiable, Decodable, Hashable {
    let id: UUID
    let groceryListID: UUID
    let homeID: UUID
    let ingredientName: String
    let normalizedName: String
    let category: GroceryCategory
    let isChecked: Bool
    let createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, category
        case groceryListID = "grocery_list_id", homeID = "home_id"
        case ingredientName = "ingredient_name", normalizedName = "normalized_name"
        case isChecked = "is_checked", createdBy = "created_by"
        case createdAt = "created_at", updatedAt = "updated_at"
    }


    func replacing(
        ingredientName: String? = nil,
        normalizedName: String? = nil,
        isChecked: Bool? = nil,
        category: GroceryCategory? = nil
    ) -> GroceryItem {
        GroceryItem(
            id: id,
            groceryListID: groceryListID,
            homeID: homeID,
            ingredientName: ingredientName ?? self.ingredientName,
            normalizedName: normalizedName ?? self.normalizedName,
            category: category ?? self.category,
            isChecked: isChecked ?? self.isChecked,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    init(
        id: UUID,
        groceryListID: UUID,
        homeID: UUID,
        ingredientName: String,
        normalizedName: String,
        category: GroceryCategory,
        isChecked: Bool,
        createdBy: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.groceryListID = groceryListID
        self.homeID = homeID
        self.ingredientName = ingredientName
        self.normalizedName = normalizedName
        self.category = category
        self.isChecked = isChecked
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GrocerySource: Identifiable, Decodable, Hashable {
    let id: UUID
    let groceryListID: UUID
    let homeID: UUID
    let sourceType: GrocerySourceType
    let sourceRefID: UUID
    let sourceLabel: String
    let sourceDate: GroceryDateOnly?
    let isActive: Bool
    let createdBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case groceryListID = "grocery_list_id", homeID = "home_id"
        case sourceType = "source_type", sourceRefID = "source_ref_id"
        case sourceLabel = "source_label", sourceDate = "source_date"
        case isActive = "is_active", createdBy = "created_by", createdAt = "created_at"
    }


    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groceryListID = try container.decode(UUID.self, forKey: .groceryListID)
        homeID = try container.decode(UUID.self, forKey: .homeID)
        sourceType = try container.decode(GrocerySourceType.self, forKey: .sourceType)
        sourceRefID = try container.decode(UUID.self, forKey: .sourceRefID)
        sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        sourceDate = try container.decodeIfPresent(GroceryDateOnly.self, forKey: .sourceDate)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdBy = try container.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        #if DEBUG
        if let sourceDate {
            print("[Groceries] raw source_date=\(sourceDate.rawValue)")
            print("[Groceries] decoded sourceDate=\(sourceDate.rawValue)")
        }
        #endif
    }
}

/// A validated Postgres `date` value. It intentionally has no timezone or time-of-day.
struct GroceryDateOnly: Decodable, Hashable {
    let rawValue: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard Self.components(for: value) != nil else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid grocery source date: \(value)"
            )
        }
        rawValue = value
    }

    func date(in timeZone: TimeZone) -> Date? {
        guard var components = Self.components(for: rawValue) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        components.calendar = calendar
        components.timeZone = timeZone
        return calendar.date(from: components)
    }

    private static func components(for value: String) -> DateComponents? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components
        else { return nil }
        return components
    }
}

struct GroceryItemSource: Decodable, Hashable {
    let groceryItemID: UUID
    let grocerySourceID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case groceryItemID = "grocery_item_id"
        case grocerySourceID = "grocery_source_id"
        case createdAt = "created_at"
    }
}

struct GroceryItemWithSources: Identifiable, Hashable {
    let item: GroceryItem
    let sources: [GrocerySource]
    var id: UUID { item.id }
}

struct AddManualGroceryItemResult {
    let item: GroceryItem
    let wasCreated: Bool
}

struct UpdateGroceryItemResult {
    let item: GroceryItem
    let removedItemID: UUID?
    var didMerge: Bool { removedItemID != nil }
}

struct AddHomeRecipeToGroceriesResult: Equatable {
    let ingredientCount: Int
    let successfulCount: Int
    let newAssociationCount: Int
    let failureCount: Int

    var hasIngredients: Bool { ingredientCount > 0 }
    var wasAlreadyFullyAdded: Bool {
        hasIngredients && failureCount == 0 && newAssociationCount == 0
    }
    var isPartialSuccess: Bool { successfulCount > 0 && failureCount > 0 }
}

struct GroceryMealEventInput: Hashable {
    let eventID: UUID
    let mealID: UUID
    let label: String
    let isLeftover: Bool
}

struct GroceryMealEventResult: Identifiable, Equatable {
    enum Status: Equatable {
        case added, alreadyProcessed, leftoverSkipped, noIngredients, failed
    }

    let eventID: UUID
    let label: String
    let status: Status
    var id: UUID { eventID }
}

struct AddMealPlanDayToGroceriesResult: Equatable {
    let meals: [GroceryMealEventResult]
    var addedCount: Int { meals.count { $0.status == .added } }
    var alreadyProcessedCount: Int { meals.count { $0.status == .alreadyProcessed } }
    var leftoverCount: Int { meals.count { $0.status == .leftoverSkipped } }
    var noIngredientsCount: Int { meals.count { $0.status == .noIngredients } }
    var failureCount: Int { meals.count { $0.status == .failed } }
}

enum GroceryNameNormalizer {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func displayName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Recipe ingredient names are stored canonically and receive presentation casing only.
    /// Manual grocery entries continue to preserve the capitalization entered by the user.
    static func recipeDisplayName(_ ingredientName: String) -> String {
        displayName(ingredientName).localizedCapitalized
    }
}

enum GroceryCategoryMatcher {
    private static let keywords: [(GroceryCategory, [String])] = [
        (.frozen, ["frozen", "ice cream"]),
        (.dairyAndEggs, ["milk", "cheese", "butter", "cream", "yogurt", "egg", "eggs", "sour cream"]),
        (.produce, ["apple", "banana", "avocado", "tomato", "tomatoes", "lettuce", "onion", "onions", "garlic", "carrot", "carrots", "potato", "potatoes", "broccoli", "spinach", "cilantro", "lemon", "lime", "orange", "berries", "strawberry", "strawberries"]),
        (.meatAndSeafood, ["chicken", "beef", "steak", "pork", "turkey", "salmon", "shrimp", "fish", "bacon", "sausage"]),
        (.bakery, ["bread", "bagel", "bun", "buns", "roll", "rolls", "tortilla", "tortillas"]),
        (.pantry, ["rice", "pasta", "flour", "sugar", "oil", "vinegar", "beans", "stock", "broth", "breadcrumbs", "cereal", "oats", "spices", "seasoning"]),
        (.beverages, ["juice", "soda", "water", "coffee", "tea"]),
        (.snacks, ["chips", "crackers", "popcorn", "pretzels"]),
        (.household, ["paper towel", "paper towels", "toilet paper", "dish soap", "detergent", "trash bag", "trash bags", "foil"]),
        (.personalCare, ["toothpaste", "toothbrush", "shampoo", "conditioner", "soap", "deodorant"])
    ]

    static func category(for name: String) -> GroceryCategory {
        let normalized = GroceryNameNormalizer.normalize(name)
        for (category, categoryKeywords) in keywords where categoryKeywords.contains(where: { contains($0, in: normalized) }) {
            return category
        }
        return .other
    }

    private static func contains(_ keyword: String, in name: String) -> Bool {
        name == keyword || " \(name) ".contains(" \(keyword) ")
    }
}
