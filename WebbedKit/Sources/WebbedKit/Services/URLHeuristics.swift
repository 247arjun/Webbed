import Foundation

// MARK: - URLHeuristics

/// Address-bar input handling: decide whether a user-entered string is a URL
/// to navigate to, or a search query to hand to the default search provider.
public enum URLHeuristics {

    /// Resolve user input into a navigable URL.
    /// - Parameters:
    ///   - input: raw user text from the address bar.
    ///   - searchProvider: provider to use if the input isn't a URL.
    public static func resolve(_ input: String,
                               using searchProvider: SearchProvider = .google) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Already has a scheme.
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "data"].contains(scheme) {
            return url
        }

        // 2. Looks like a host (has a dot, no spaces, no obvious search terms).
        if !trimmed.contains(" "),
           trimmed.contains("."),
           !trimmed.hasPrefix(".") && !trimmed.hasSuffix(".") {
            if let url = URL(string: "https://" + trimmed) {
                return url
            }
        }

        // 3. localhost / single-word hostnames with port (e.g. "localhost:8080").
        if !trimmed.contains(" "), trimmed.contains(":") {
            if let url = URL(string: "http://" + trimmed) { return url }
        }

        // 4. Fall through to search.
        return searchProvider.searchURL(for: trimmed)
    }

    /// Returns true when the resolved navigation would be a web search rather
    /// than a direct URL — useful for UI hints.
    public static func isSearchQuery(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if URL(string: trimmed)?.scheme != nil { return false }
        if !trimmed.contains(" "), trimmed.contains(".") { return false }
        return true
    }
}
