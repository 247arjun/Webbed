import Foundation
import Combine
import WebbedKit

/// Holds the iOS app's persistent state: the `TabStore` and the persistence
/// backend. iCloud observer wiring happens in Phase 5.
@MainActor
final class AppModel: ObservableObject {

    static let shared = AppModel()

    let tabStore: TabStore
    private var persistence: FilePersistenceService
    private var iCloudObserver: iCloudChangeObserver?

    @Published private(set) var usingICloud: Bool = false

    /// Navigation hook for OpenTabIntent (Phase 6). The RootView watches
    /// this and pushes the editor when it changes.
    @Published var pendingOpenTabID: UUID?

    private init() {
        let directory = AppModel.resolveStartupDirectory()
        let service = FilePersistenceService(directory: directory)
        self.persistence = service
        self.tabStore = TabStore(persistenceService: service)
        self.usingICloud = StorageLocationResolver.iCloudAvailable
            && directory.path.contains("Mobile Documents")

        tabStore.loadAll()
        tabStore.purgeOldTrash()
        installICloudObserverIfNeeded(directory: directory)
    }

    /// Create a new tab and queue it for the editor.
    func createAndOpenTab(url: URL? = nil) {
        let tab = tabStore.createTab(url: url ?? AppSettings.shared.homepageURL)
        pendingOpenTabID = tab.id
    }

    static func resolveStartupDirectory() -> URL {
        if let url = StorageLocationResolver.iCloudDirectory() { return url }
        return StorageLocationResolver.defaultLocalDirectory()
    }

    private func installICloudObserverIfNeeded(directory: URL) {
        guard usingICloud else { return }
        let obs = iCloudChangeObserver()
        obs.start(tabsDirectory: directory)
        tabStore.attachICloudObserver(obs)
        iCloudObserver = obs
    }

    /// Re-resolve the storage location (used by pull-to-refresh).
    func refresh() {
        let newDir = AppModel.resolveStartupDirectory()
        let nowOnICloud = StorageLocationResolver.iCloudAvailable
            && newDir.path.contains("Mobile Documents")
        if persistence.tabsDirectory != newDir {
            let newService = FilePersistenceService(directory: newDir)
            self.persistence = newService
            tabStore.swapPersistenceService(newService)
            iCloudObserver?.stop()
            iCloudObserver = nil
            if nowOnICloud {
                let obs = iCloudChangeObserver()
                obs.start(tabsDirectory: newDir)
                tabStore.attachICloudObserver(obs)
                iCloudObserver = obs
            } else {
                tabStore.attachICloudObserver(nil)
            }
            usingICloud = nowOnICloud
        }
        tabStore.loadAll()
    }
}
