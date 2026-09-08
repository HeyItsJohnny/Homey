import Foundation

enum AppConfiguration {
    static var supabaseURL: URL {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !value.isEmpty,
            let url = URL(string: value),
            let scheme = url.scheme,
            !scheme.isEmpty,
            url.host != nil
        else {
            fatalError("Missing or invalid SUPABASE_URL configuration.")
        }

        return url
    }

    static var supabasePublishableKey: String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
            !value.isEmpty
        else {
            fatalError("Missing SUPABASE_PUBLISHABLE_KEY configuration.")
        }

        guard !isServiceRoleKey(value) else {
            fatalError("SUPABASE_PUBLISHABLE_KEY must be a client-safe publishable or legacy anon key, not a service_role key.")
        }

        return value
    }

    private static func isServiceRoleKey(_ value: String) -> Bool {
        let lowercaseValue = value.lowercased()

        if lowercaseValue.contains("service_role") || lowercaseValue.hasPrefix("sb_secret_") {
            return true
        }

        let segments = value.split(separator: ".")
        guard segments.count >= 2 else {
            return false
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let role = object["role"] as? String
        else {
            return false
        }

        return role == "service_role"
    }
}
