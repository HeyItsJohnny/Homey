import Foundation

struct RecipeImportResponseError: Error {
    let code: String
}

enum RecipeImportResponseDecoder {
    static func decode(_ data: Data) throws -> RecipeImportResponse {
        // Normal non-2xx errors are thrown by FunctionsClient. Also recognize an
        // error envelope on a 2xx response before trying the successful DTO.
        if let code = RecipeImportInput.errorCode(data: data) {
            throw RecipeImportResponseError(code: code)
        }
        return try JSONDecoder().decode(RecipeImportResponse.self, from: data)
    }
}

enum RecipeImportDiagnostics {
    static func decoded(_ response: RecipeImportResponse) {
        #if DEBUG
        print("[RecipeImport] decodedTitle=\(response.recipe.title)")
        print("[RecipeImport] decodedImage=\(RecipeImageReference.safeLog(response.recipe.imageUrl))")
        print("[RecipeImport] decodedIngredients=\(response.recipe.ingredients.count)")
        print("[RecipeImport] decodedDirections=\(response.recipe.steps.count)")
        print("[RecipeImport] decodedSource=\(response.recipe.source.name ?? response.recipe.source.domain)")
        print("[RecipeImport] decodedSourceURL=\(RecipeImportInput.safeLogURL(response.recipe.source.originalUrl))")
        #endif
    }

    static func mapped(_ draft: RecipeDraft) {
        #if DEBUG
        print("[RecipeImport] draftTitle=\(draft.name)")
        print("[RecipeImport] draftImage=\(RecipeImageReference.safeLog(draft.importImageURL))")
        print("[RecipeImport] draftIngredients=\(draft.ingredients.count)")
        print("[RecipeImport] draftDirections=\(draft.steps.count)")
        print("[RecipeImport] draftSource=\(draft.sourceName)")
        #endif
    }

    static func editor(_ draft: RecipeDraft, editing: Bool, mounted: Bool = false) {
        #if DEBUG
        let stage = mounted ? "mounted" : "initial"
        print("[RecipeEditor] \(stage)Title=\(draft.name)")
        print("[RecipeEditor] \(stage)Ingredients=\(draft.ingredients.count)")
        print("[RecipeEditor] \(stage)Directions=\(draft.steps.count)")
        print("[RecipeEditor] mode=\(editing ? "edit" : "create")")
        print("[RecipeEditor] imported=\(draft.imported != nil)")
        #endif
    }

    static func response(data: Data, status: Int, contentType: String?) {
        #if DEBUG
        print("[RecipeImport] HTTP/function response received")
        print("[RecipeImport] status=\(status)")
        print("[RecipeImport] contentType=\(contentType ?? "unavailable")")
        print("[RecipeImport] rawResponse=\(sanitizedJSON(data))")
        #endif
    }

    static func decoding(_ error: DecodingError) {
        #if DEBUG
        for line in decodingDetails(error) { print("[RecipeImport] \(line)") }
        #endif
    }

    static func decodingDetails(_ error: DecodingError) -> [String] {
        let context: DecodingError.Context
        var details: [String]
        switch error {
        case .keyNotFound(let key, let value):
            context = value
            details = ["DecodingError.keyNotFound", "missingKey=\(key.stringValue)"]
        case .valueNotFound(let type, let value):
            context = value
            details = ["DecodingError.valueNotFound", "expectedType=\(String(reflecting: type))"]
        case .typeMismatch(let type, let value):
            context = value
            details = ["DecodingError.typeMismatch", "expectedType=\(String(reflecting: type))"]
        case .dataCorrupted(let value):
            context = value
            details = ["DecodingError.dataCorrupted"]
        @unknown default: return ["DecodingError.unknown"]
        }
        let path = context.codingPath.reduce("") { path, key in
            if let index = key.intValue { return path + "[\(index)]" }
            return path.isEmpty ? key.stringValue : path + "." + key.stringValue
        }
        details.append("codingPath=\(path.isEmpty ? "<root>" : path)")
        details.append("debugDescription=\(context.debugDescription)")
        if let underlying = context.underlyingError as NSError? {
            details.append("underlyingDomain=\(underlying.domain) underlyingCode=\(underlying.code)")
        }
        return details
    }

    static func sanitizedJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
              let sanitized = try? JSONSerialization.data(withJSONObject: redact(object), options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let text = String(data: sanitized, encoding: .utf8) else {
            return "<non-JSON body, \(data.count) bytes; omitted to avoid logging unstructured secrets>"
        }
        return text
    }

    private static func redact(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                let key = entry.key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                if ["token", "authorization", "apikey", "secret", "password", "cookie"].contains(where: { key.contains($0) }) {
                    result[entry.key] = "<redacted>"
                } else { result[entry.key] = redact(entry.value) }
            }
        }
        if let array = value as? [Any] { return array.map { redact($0) } }
        if let text = value as? String, let scheme = URLComponents(string: text)?.scheme,
           ["http", "https"].contains(scheme.lowercased()) { return RecipeImportInput.safeLogURL(text) }
        return value
    }
}
