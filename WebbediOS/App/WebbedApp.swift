import SwiftUI
import WebbedKit

@main
struct WebbedApp: App {

    @UIApplicationDelegateAdaptor(WebbedAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup("Webbed", id: "main") {
            RootView()
                .environmentObject(appModel)
                .environmentObject(appModel.tabStore)
                .environmentObject(appModel.permissionStore)
        }

        // Per-tab scenes for iPadOS Stage Manager / Split View. On iPhone
        // these collapse into the main scene's navigation stack.
        WindowGroup("Tab", id: "tab", for: UUID.self) { $tabID in
            if let id = tabID {
                TabSceneView(tabID: id)
                    .environmentObject(appModel)
                    .environmentObject(appModel.tabStore)
                    .environmentObject(appModel.permissionStore)
            } else {
                Text("No tab selected").foregroundStyle(.secondary)
            }
        }
    }
}
