import Foundation

struct ParsedWebsiteIngredient: Equatable {
    enum Safety: String { case alreadyValid, safe, needsReview }
    let quantity: Decimal?
    let unit: String?
    let ingredientName: String
    let preparation: String?
    let originalText: String
    let usedFallback: Bool
    let isOptional: Bool
    let safety: Safety
}

enum WebsiteIngredientParser {
    private static let units: Set<String> = [
        "tsp", "teaspoon", "teaspoons", "tbsp", "tablespoon", "tablespoons",
        "cup", "cups", "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds",
        "g", "gram", "grams", "kg", "kilogram", "kilograms", "ml", "milliliter",
        "milliliters", "l", "liter", "liters", "clove", "cloves", "slice", "slices",
        "can", "cans", "package", "packages", "pinch"
    ]
    private static let preparations: Set<String> = [
        "melted", "softened", "chopped", "diced", "minced", "sliced", "shredded",
        "grated", "crushed", "quartered", "peeled"
    ]
    private static let unicodeFractions: [Character: String] = [
        "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4"
    ]

    static func parse(_ rawValue: String, suppliedQuantity: String? = nil) -> ParsedWebsiteIngredient {
        let original = cleanWhitespace(rawValue)
        var normalizedLine = expandUnicodeFractions(original)
        var isOptional = false
        if normalizedLine.lowercased().hasPrefix("optional:") {
            isOptional = true
            normalizedLine = cleanWhitespace(String(normalizedLine.dropFirst("optional:".count)))
        }
        if normalizedLine.range(of: #"\s*\(optional\)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            isOptional = true
            normalizedLine = normalizedLine.replacingOccurrences(
                of: #"\s*\(optional\)\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        let structurallyAmbiguous = containsRange(normalizedLine)
            || containsSecondaryMeasurement(normalizedLine)
            || isIngredientListHeading(normalizedLine)
        var words = normalizedLine.split(whereSeparator: \.isWhitespace).map(String.init)

        var quantity: Decimal?
        if let suppliedQuantity { quantity = parseQuantity(suppliedQuantity) }
        if let extracted = leadingQuantity(from: words) {
            if quantity == nil { quantity = extracted.value }
            words.removeFirst(extracted.wordCount)
        }

        var unit: String?
        if let first = words.first {
            let candidate = first.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if units.contains(candidate) {
                unit = candidate
                words.removeFirst()
            }
        }

        var preparation: String?
        if let first = words.first {
            let candidate = first.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if preparations.contains(candidate) {
                preparation = candidate
                words.removeFirst()
            }
        }

        var name = cleanWhitespace(words.joined(separator: " "))
        if let malformed = malformedPreparation(in: name) {
            name = malformed.name
            preparation = preparation ?? malformed.preparation
        } else if let comma = name.firstIndex(of: ",") {
            let suffix = cleanWhitespace(String(name[name.index(after: comma)...]))
            if isPreparationPhrase(suffix) {
                preparation = preparation ?? suffix
                name = cleanWhitespace(String(name[..<comma]))
            }
        }
        if let match = name.range(of: #"\s*\(([A-Za-z]+)\)\s*$"#, options: .regularExpression) {
            let marker = name[match].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .lowercased()
            if preparations.contains(marker) {
                preparation = preparation ?? marker
                name = cleanWhitespace(String(name[..<match.lowerBound]))
            }
        }

        let fallback = name.isEmpty
        if name.isEmpty { name = original }
        let changed = name.caseInsensitiveCompare(original) != .orderedSame
            || quantity != nil || unit != nil || preparation != nil || isOptional
        let safety: ParsedWebsiteIngredient.Safety
        if structurallyAmbiguous || fallback {
            safety = .needsReview
        } else if changed {
            safety = .safe
        } else {
            safety = .alreadyValid
        }
        let result = ParsedWebsiteIngredient(
            quantity: quantity,
            unit: unit,
            ingredientName: name,
            preparation: preparation,
            originalText: original,
            usedFallback: fallback,
            isOptional: isOptional,
            safety: safety
        )
        log(result)
        return result
    }

    private static func leadingQuantity(from words: [String]) -> (value: Decimal, wordCount: Int)? {
        guard let first = words.first else { return nil }
        if words.count > 1, let mixed = parseQuantity("\(first) \(words[1])") {
            return (mixed, 2)
        }
        return parseQuantity(first).map { ($0, 1) }
    }

    private static func parseQuantity(_ value: String) -> Decimal? {
        try? RecipeQuantity.decimal(expandUnicodeFractions(cleanWhitespace(value)))
    }

    private static func expandUnicodeFractions(_ value: String) -> String {
        var result = ""
        for character in value {
            guard let fraction = unicodeFractions[character] else {
                result.append(character)
                continue
            }
            if let last = result.last, last.isNumber { result.append(" ") }
            result.append(contentsOf: fraction)
        }
        return cleanWhitespace(result)
    }

    private static func cleanWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func containsRange(_ value: String) -> Bool {
        value.range(
            of: #"^\s*(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)\s*(?:-|\bto\b)\s*\d"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func containsSecondaryMeasurement(_ value: String) -> Bool {
        let patterns = [
            #"\([^)]*\d+(?:\s+\d+/\d+|/\d+|\.\d+)?[^)]*\)"#,
            #"\b(?:plus|or)\s+\d+(?:\s+\d+/\d+|/\d+|\.\d+)?\s+[A-Za-z]"#
        ]
        return patterns.contains { value.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func malformedPreparation(in value: String) -> (name: String, preparation: String)? {
        guard let range = value.range(
            of: #"\s*\(,\s*([^)]*)\)\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let contents = value[range]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        guard isPreparationPhrase(contents)
                || (contents.lowercased().hasPrefix("or ") && !containsSecondaryMeasurement(contents))
        else { return nil }
        return (cleanWhitespace(String(value[..<range.lowerBound])), cleanWhitespace(contents))
    }

    private static func isPreparationPhrase(_ value: String) -> Bool {
        let normalized = cleanWhitespace(value).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.hasPrefix("or ") { return false }
        if normalized == "for serving" || normalized == "for garnish" { return true }
        return preparations.contains { marker in
            normalized == marker
                || normalized.hasPrefix("\(marker) ")
                || normalized.contains(" \(marker)")
        }
    }

    private static func isIngredientListHeading(_ value: String) -> Bool {
        let lower = value.lowercased()
        return (lower.hasPrefix("for serving:") || lower.hasPrefix("toppings:")) && value.contains(",")
    }

    private static func log(_ value: ParsedWebsiteIngredient) {
        #if DEBUG
        print("[RecipeImportIngredient]")
        print("raw=\"\(value.originalText)\"")
        print("quantity=\(value.quantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "nil")")
        print("unit=\(value.unit ?? "nil")")
        print("ingredientName=\(value.ingredientName)")
        print("preparation=\(value.preparation ?? "nil")")
        print("isOptional=\(value.isOptional)")
        print("classification=\(value.safety.rawValue)")
        if value.usedFallback { print("[RecipeImportIngredient] fallback=true") }
        #endif
    }
}

extension RecipeDraft {
    mutating func apply(_ response: RecipeImportResponse) {
        imported = response
        importedImageRemoved = false
        difficulty = nil
        let recipe = response.recipe
        name = recipe.title
        description = recipe.description ?? ""
        cuisine = recipe.cuisine ?? ""
        let importedSourceName = recipe.source.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sourceName = importedSourceName.isEmpty ? recipe.source.domain : importedSourceName
        sourceURL = recipe.source.originalUrl
        prepMinutes = recipe.prepTimeMinutes
        cookMinutes = recipe.cookTimeMinutes
        servings = recipe.servings.flatMap(Double.init)
        mealTypes = Set(recipe.mealTypes.compactMap(MealType.init(rawValue:)))
        tagsText = recipe.keywords.joined(separator: ", ")
        ingredients = recipe.ingredients.sorted { $0.sortOrder < $1.sortOrder }.map { ingredient in
            let parsed = WebsiteIngredientParser.parse(
                ingredient.ingredientName,
                suppliedQuantity: ingredient.quantity
            )
            return IngredientDraft(
                name: parsed.ingredientName,
                quantity: parsed.quantity.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                unit: parsed.unit ?? "",
                section: ingredient.sectionName ?? "Ingredients",
                optional: ingredient.isOptional || parsed.isOptional,
                preparation: parsed.preparation
            )
        }
        steps = recipe.steps.sorted { $0.sortOrder < $1.sortOrder }.map { item in
            var step = StepDraft()
            let section = item.sectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = item.stepText.trimmingCharacters(in: .whitespacesAndNewlines)
            step.text = section.isEmpty ? text : "\(section): \(text)"
            return step
        }
    }
}

enum RecipeImportInput {
    static func validURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }), components.url != nil else { return nil }
        return trimmed
    }
    static func safeLogURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return "<invalid>" }
        components.user = nil; components.password = nil
        components.query = nil; components.fragment = nil
        return components.string ?? "<invalid>"
    }
    static func errorCode(data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (body["error"] as? [String: Any])?["code"] as? String ?? body["code"] as? String
    }
    static func message(for code: String) -> String {
        switch code {
        case "SOURCE_BLOCKED": "This website doesn't currently allow Homey to import this recipe."
        case "INVALID_URL": "Enter a valid recipe URL."
        case "AUTH_REQUIRED", "HTTP_401": "Please sign in again before importing a recipe."
        case "HOME_ACCESS_DENIED", "HTTP_403": "You don't have access to import recipes for this Home."
        case "RECIPE_NOT_FOUND", "NO_RECIPE_FOUND", "UNSUPPORTED_PAGE": "We couldn't find a recipe on that page. Try a direct recipe link."
        case "INVALID_RECIPE_DATA", "PARSE_FAILED", "SOURCE_PARSE_FAILED": "We couldn't read this recipe. Try another link or add it manually."
        case "RESPONSE_DECODING_ERROR": "Homey couldn't read the recipe returned by this website. Please try another recipe or try again later."
        case "NETWORK_ERROR", "TIMEOUT": "Homey couldn't reach the importer. Check your connection and try again."
        case "SOURCE_UNSUPPORTED", "NOT_HTML": "This page isn't supported. Try a direct recipe link."
        default: "Homey couldn't import this recipe. Please try another link or try again later."
        }
    }
}

/// The sheet payload and its editor identity are created together. Imported
/// content never travels through an independently changing optional State value.
struct RecipeCreationPresentation: Identifiable {
    enum Content {
        case website
        case scan
        case editor(RecipeDraft)
    }
    let id = UUID()
    let content: Content

    static func manual() -> Self { .init(content: .editor(RecipeDraft())) }
    static func website() -> Self { .init(content: .website) }
    static func scan() -> Self { .init(content: .scan) }
    static func imported(_ draft: RecipeDraft) -> Self { .init(content: .editor(draft)) }
}
