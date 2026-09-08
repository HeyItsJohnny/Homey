import Foundation

struct RecipeImportRequest: Codable, Hashable, Sendable {
    let homeId: UUID
    let url: String

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case url
    }
}

struct RecipeImportResponse: Codable, Hashable, Sendable {
    let importId: UUID
    let globalRecipeId: UUID?
    let alreadyExists: Bool
    let normalizedUrl: String
    let recipe: ImportedRecipePreview
}

enum ImportedRecipeSaveResult: Hashable, Sendable {
    case saved(UUID)
    case alreadyExists(Meal)
}

struct ImportedRecipePreview: Codable, Hashable, Sendable {
    let title: String
    let description: String?
    let imageUrl: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let totalTimeMinutes: Int?
    let servings: String?
    let cuisine: String?
    let mealTypes: [MealType]
    let keywords: [String]
    let ingredients: [ImportedRecipeIngredient]
    let steps: [ImportedRecipeStep]
    let nutrition: RecipeImportJSONValue?
    let source: ImportedRecipeSource
}

struct ImportedRecipeIngredient: Codable, Hashable, Sendable {
    let sectionName: String?
    let ingredientName: String
    let quantity: String?
    let isOptional: Bool
    let sortOrder: Int
}

struct ImportedRecipeStep: Codable, Hashable, Sendable {
    let sectionName: String?
    let stepText: String
    let sortOrder: Int
}

struct ImportedRecipeSource: Codable, Hashable, Sendable {
    let originalUrl: String
    let normalizedUrl: String
    let domain: String
    let name: String?
}

struct RecipeImportErrorResponse: Codable, Hashable, Sendable {
    let error: RecipeImportAPIError
}

struct RecipeImportAPIError: Codable, Hashable, Sendable, Error {
    let code: Code
    let message: String

    enum Code: String, Codable, CaseIterable, Hashable, Sendable {
        case invalidURL = "INVALID_URL"
        case authRequired = "AUTH_REQUIRED"
        case homeAccessDenied = "HOME_ACCESS_DENIED"
        case fetchFailed = "FETCH_FAILED"
        case notHTML = "NOT_HTML"
        case noRecipeFound = "NO_RECIPE_FOUND"
        case invalidRecipeData = "INVALID_RECIPE_DATA"
        case pageTooLarge = "PAGE_TOO_LARGE"
        case sourceBlocked = "SOURCE_BLOCKED"
        case sourceAccessDenied = "SOURCE_ACCESS_DENIED"
        case sourceUnsupported = "SOURCE_UNSUPPORTED"
        case sourceParseFailed = "SOURCE_PARSE_FAILED"
        case robotsDisallowed = "ROBOTS_DISALLOWED"
        case timeout = "TIMEOUT"
        case internalError = "INTERNAL_ERROR"
    }
}

enum RecipeImportJSONValue: Codable, Hashable, Sendable {
    case null
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: RecipeImportJSONValue])
    case array([RecipeImportJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: RecipeImportJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([RecipeImportJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported recipe import JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}
