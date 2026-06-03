import Foundation

// MARK: - SearchProvider

/// User-selectable search engines. Templates URL-encode the query.
public enum SearchProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case google
    case duckDuckGo
    case bing
    case kagi
    case brave

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .google:     return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing:       return "Bing"
        case .kagi:       return "Kagi"
        case .brave:      return "Brave"
        }
    }

    /// `{query}`-templated search URL.
    public var templateString: String {
        switch self {
        case .google:     return "https://www.google.com/search?q={query}"
        case .duckDuckGo: return "https://duckduckgo.com/?q={query}"
        case .bing:       return "https://www.bing.com/search?q={query}"
        case .kagi:       return "https://kagi.com/search?q={query}"
        case .brave:      return "https://search.brave.com/search?q={query}"
        }
    }

    /// Build a search URL for the given query.
    public func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? query
        return URL(string: templateString.replacingOccurrences(of: "{query}", with: encoded))
    }
}
