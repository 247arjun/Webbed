import AppIntents
import WebbedKit

/// Surfaces Webbed's intents to Siri / Spotlight / Shortcuts as built-in
/// phrases. iOS quick-action discovery picks these up automatically.
struct WebbedAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewTabIntent(),
            phrases: [
                "Open a new tab in \(.applicationName)",
                "New tab in \(.applicationName)",
            ],
            shortTitle: "New Tab",
            systemImageName: "plus.square"
        )
        AppShortcut(
            intent: SearchWebIntent(),
            phrases: [
                "Search the web with \(.applicationName)",
                "Search \(.applicationName) for \(\.$query)",
            ],
            shortTitle: "Search the Web",
            systemImageName: "magnifyingglass"
        )
    }
}
