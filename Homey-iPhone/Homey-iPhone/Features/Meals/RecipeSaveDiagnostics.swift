import Foundation
import PostgREST

// Deliberately excludes auth sessions, headers, keys, and tokens.
enum RecipeSaveDiagnostics {
    static func log(_ message: String) {
        #if DEBUG
        print("[RecipeSave] \(message)")
        #endif
    }

    static func failure(_ error: Error, stage: String) {
        #if DEBUG
        print("[RecipeSave] FAILED stage=\(stage)")
        print("[RecipeSave] Error type: \(String(reflecting: type(of: error)))")
        if let error = error as? PostgrestError {
            print("[RecipeSave] Supabase code: \(error.code ?? "nil")")
            print("[RecipeSave] Supabase message: \(error.message)")
            print("[RecipeSave] Supabase details: \(error.detail ?? "nil")")
            print("[RecipeSave] Supabase hint: \(error.hint ?? "nil")")
        } else {
            print("[RecipeSave] Error: \(error.localizedDescription)")
        }
        #endif
    }
}

/// The Home RPC accepts a numeric quantity; Community accepts free-form text.
enum RecipeQuantity {
    static func decimal(_ text: String) throws -> Decimal? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        func number(_ value: String) -> Decimal? {
            guard value.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
            return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        }
        func fraction(_ value: String) -> Decimal? {
            let parts = value.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let numerator = number(String(parts[0])),
                  let denominator = number(String(parts[1])), denominator != 0 else { return nil }
            return numerator / denominator
        }
        if let value = number(text) { return value }
        if let value = fraction(text) { return value }
        let parts = text.split(whereSeparator: \.isWhitespace)
        if parts.count == 2, let whole = number(String(parts[0])), let part = fraction(String(parts[1])) {
            return whole + (whole < 0 ? -part : part)
        }
        throw MealsError.message("Enter ingredient quantities as numbers or fractions, such as 2, 0.5, or 1/2. Put units in the ingredient name.")
    }
}
