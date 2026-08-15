import Foundation
import Functions
import Supabase

protocol RecipeImportServicing: AnyObject {
    func importRecipe(homeId: UUID, url: String) async throws -> RecipeImportResponse
}

@MainActor
final class RecipeImportService: RecipeImportServicing {
    private let client = SupabaseManager.shared.client

    func importRecipe(homeId: UUID, url: String) async throws -> RecipeImportResponse {
        let request = RecipeImportRequest(homeId: homeId, url: url)

        do {
            return try await client.functions.invoke(
                "import-recipe-url",
                options: FunctionInvokeOptions(body: request)
            )
        } catch let error as FunctionsError {
            throw decodeFunctionError(error) ?? RecipeImportServiceError.importFailed
        } catch let error as RecipeImportAPIError {
            throw error
        } catch {
            #if DEBUG
            print("Recipe import failed: \(String(reflecting: error))")
            #endif
            throw RecipeImportServiceError.importFailed
        }
    }

    private func decodeFunctionError(_ error: FunctionsError) -> Error? {
        guard case .httpError(let statusCode, let data) = error else {
            #if DEBUG
            print("Recipe import function error: \(error.localizedDescription)")
            #endif
            return RecipeImportServiceError.importFailed
        }

        let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 response body>"
        #if DEBUG
        print("Recipe import HTTP error status: \(statusCode)")
        print("Recipe import HTTP error content-type: unavailable from Supabase FunctionsError")
        print("Recipe import raw error body: \(rawBody)")
        #endif

        return FlexibleRecipeImportErrorDecoder.decode(data: data, statusCode: statusCode, rawBody: rawBody)
    }
}

enum RecipeImportServiceError: LocalizedError, Equatable {
    case importFailed
    case message(String)

    var errorDescription: String? {
        switch self {
        case .importFailed:
            return "Homey could not import this recipe. Please try again."
        case .message(let message):
            return message
        }
    }
}

private enum FlexibleRecipeImportErrorDecoder {
    static func decode(data: Data, statusCode: Int, rawBody: String) -> Error {
        let decoder = JSONDecoder()

        if let nested = try? decoder.decode(RecipeImportErrorResponse.self, from: data) {
            return nested.error
        }

        if let flat = try? decoder.decode(FlatErrorResponse.self, from: data) {
            if let code = flat.recipeImportCode {
                return RecipeImportAPIError(code: code, message: flat.message)
            }
            return fallbackForStatus(statusCode, message: flat.message)
        }

        if let messageOnly = try? decoder.decode(MessageOnlyErrorResponse.self, from: data) {
            return fallbackForStatus(statusCode, message: messageOnly.message)
        }

        let trimmedBody = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            return fallbackForStatus(statusCode, message: trimmedBody)
        }

        return fallbackForStatus(statusCode, message: nil)
    }

    private static func fallbackForStatus(_ statusCode: Int, message: String?) -> Error {
        switch statusCode {
        case 401:
            return RecipeImportAPIError(code: .authRequired, message: message ?? "Sign in before importing recipes.")
        case 403:
            return RecipeImportAPIError(code: .homeAccessDenied, message: message ?? "You do not have permission to import recipes for this Home.")
        default:
            return RecipeImportServiceError.importFailed
        }
    }
}

private struct FlatErrorResponse: Decodable {
    let code: FlexibleErrorCode?
    let message: String

    var recipeImportCode: RecipeImportAPIError.Code? {
        guard let code else { return nil }
        switch code {
        case .string(let value):
            return RecipeImportAPIError.Code(rawValue: value)
        case .number:
            return nil
        }
    }
}

private struct MessageOnlyErrorResponse: Decodable {
    let message: String
}

private enum FlexibleErrorCode: Decodable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported error code value.")
        }
    }
}

extension RecipeImportAPIError {
    var userFacingMessage: String {
        switch code {
        case .invalidURL:
            return "Enter a valid recipe URL."
        case .authRequired:
            return "Sign in again before importing a recipe."
        case .homeAccessDenied:
            return "You do not have permission to import recipes for this Home."
        case .fetchFailed:
            return "Homey couldn't access this recipe page."
        case .notHTML:
            return "This link does not look like a recipe page."
        case .noRecipeFound:
            return "We couldn't find recipe information on this page."
        case .invalidRecipeData:
            return "Homey found recipe information, but it could not be imported."
        case .pageTooLarge:
            return "This recipe page is too large for Homey to import."
        case .sourceBlocked:
            return "This website doesn't currently allow Homey to import this recipe."
        case .timeout:
            return "This recipe page took too long to respond. Please try again."
        case .internalError:
            return "Homey could not import this recipe. Please try again."
        }
    }
}
