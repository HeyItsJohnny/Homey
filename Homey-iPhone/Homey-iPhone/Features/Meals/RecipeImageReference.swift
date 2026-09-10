import Foundation

/// Durable database values are Storage object keys or existing remote HTTP(S)
/// references. Signed Storage URLs are generated only at the display/copy boundary.
enum RecipeImageReference: Equatable {
    case storage(String)
    case remote(URL)

    init?(_ rawValue: String?) {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let components = URLComponents(string: value), let scheme = components.scheme {
            guard ["https", "http"].contains(scheme.lowercased()),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil,
                  let url = components.url else { return nil }
            self = .remote(url)
        } else {
            let folders = value.split(separator: "/", omittingEmptySubsequences: false)
            guard folders.count >= 2, !value.contains("?"), !value.contains("#"),
                  folders.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
            self = .storage(value)
        }
    }

    var value: String {
        switch self {
        case .storage(let path): path
        case .remote(let url): url.absoluteString
        }
    }

    static func safeLog(_ value: String?) -> String {
        guard let reference = Self(value) else { return "nil" }
        switch reference {
        case .storage(let path): return path
        case .remote(let url):
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.fragment = nil
            return components?.string ?? "<remote image>"
        }
    }
}
