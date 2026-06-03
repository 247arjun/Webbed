import Foundation
import AppIntents

// MARK: - IntentHostRegistry

/// Glue between App Intents and the running app.
@MainActor
public enum IntentHostRegistry {
    public static var current: (any TabIntentHost)?
}

@MainActor
public protocol TabIntentHost: AnyObject {
    var tabStore: TabStore { get }
    /// Bring the tab into view (open a tear-out window on macOS, navigate
    /// to the editor on iOS).
    func openTab(id: UUID)
    /// Open a brand-new tab and bring it to the foreground.
    func openNewTab(url: URL?)
}

// MARK: - TabEntity

public struct TabEntity: AppEntity, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var urlString: String

    public init(id: UUID, title: String, urlString: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
    }

    public init(record: TabRecord) {
        self.id = record.id
        self.title = record.displayTitle
        self.urlString = record.displayURLString
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Tab")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(urlString)")
    }

    public static let defaultQuery = TabEntityQuery()
}

// MARK: - TabEntityQuery

public struct TabEntityQuery: EntityQuery, EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [TabEntity.ID]) async throws -> [TabEntity] {
        guard let store = IntentHostRegistry.current?.tabStore else { return [] }
        return identifiers.compactMap { id in store.tabs[id].map(TabEntity.init(record:)) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [TabEntity] {
        guard let store = IntentHostRegistry.current?.tabStore else { return [] }
        return store.tabs.values
            .sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            .prefix(10)
            .map(TabEntity.init(record:))
    }

    @MainActor
    public func entities(matching string: String) async throws -> [TabEntity] {
        guard let store = IntentHostRegistry.current?.tabStore else { return [] }
        let needle = string.lowercased()
        return store.tabs.values
            .filter {
                $0.title.lowercased().contains(needle)
                || $0.displayURLString.lowercased().contains(needle)
            }
            .sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            .map(TabEntity.init(record:))
    }
}

// MARK: - OpenTabIntent

public struct OpenTabIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Tab"
    public static let description = IntentDescription("Open an existing tab in Webbed.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Tab")
    public var tab: TabEntity

    public init() {}
    public init(tab: TabEntity) { self.tab = tab }

    @MainActor
    public func perform() async throws -> some IntentResult {
        IntentHostRegistry.current?.openTab(id: tab.id)
        return .result()
    }
}

// MARK: - NewTabIntent

public struct NewTabIntent: AppIntent {
    public static let title: LocalizedStringResource = "New Tab"
    public static let description = IntentDescription("Open a new tab in Webbed.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "URL", description: "Optional starting URL.", default: "")
    public var urlString: String

    public init() {}
    public init(urlString: String = "") { self.urlString = urlString }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL? = trimmed.isEmpty ? nil : URLHeuristics.resolve(trimmed,
                                                                       using: AppSettings.shared.searchProvider)
        IntentHostRegistry.current?.openNewTab(url: url)
        return .result(dialog: trimmed.isEmpty ? "Opened a new tab" : "Opened \(trimmed)")
    }
}

// MARK: - SearchWebIntent

public struct SearchWebIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search the Web"
    public static let description = IntentDescription("Search the web in Webbed using the current search provider.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Query")
    public var query: String

    public init() {}
    public init(query: String) { self.query = query }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = AppSettings.shared.searchProvider.searchURL(for: query) else {
            return .result(dialog: "Couldn't build a search URL.")
        }
        IntentHostRegistry.current?.openNewTab(url: url)
        return .result(dialog: "Searching for \(query)")
    }
}

// MARK: - Errors

public enum TabIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "Webbed isn't ready yet. Try again in a moment."
        }
    }
}
