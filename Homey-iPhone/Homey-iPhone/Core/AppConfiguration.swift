import Foundation

enum AppConfiguration {
    static var supabaseURL: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: value), url.scheme != nil, url.host != nil else {
            fatalError("Missing or invalid SUPABASE_URL configuration.")
        }
        return url
    }

    static var supabasePublishableKey: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !value.isEmpty else {
            fatalError("Missing SUPABASE_PUBLISHABLE_KEY configuration.")
        }
        guard !value.lowercased().contains("service_role"), !value.hasPrefix("sb_secret_") else {
            fatalError("SUPABASE_PUBLISHABLE_KEY must be a client-safe key.")
        }
        return value
    }
}
