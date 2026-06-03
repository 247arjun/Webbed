import Foundation
import Combine

// MARK: - TabStore

/// Single source of truth for tab data. Mirrors Noted's `NoteStore` bucket
/// model — active loaded eagerly, archived/trashed on demand.
@MainActor
public final class TabStore: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var tabs:         [UUID: TabRecord] = [:]
    @Published public private(set) var archivedTabs: [UUID: TabRecord] = [:]
    @Published public private(set) var trashedTabs:  [UUID: TabRecord] = [:]

    // MARK: - Dependencies

    public private(set) var persistenceService: PersistenceService

    // MARK: - Debounce

    private let frameSaveSubject  = PassthroughSubject<UUID, Never>()
    private let scrollSaveSubject = PassthroughSubject<UUID, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var pendingTabIDs = Set<UUID>()

    // MARK: - iCloud observer

    private var changeObserver: iCloudChangeObserver?
    private var changeObserverCancellable: AnyCancellable?

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
        setupDebounce()
    }

    public func swapPersistenceService(_ newService: PersistenceService) {
        self.persistenceService = newService
        attachICloudObserver(nil)
        Log.persist.info("Swapped persistence backend → \(newService.tabsDirectory.path, privacy: .public)")
    }

    public func attachICloudObserver(_ observer: iCloudChangeObserver?) {
        changeObserverCancellable?.cancel()
        changeObserver?.stop()
        changeObserver = observer
        guard let observer else { return }
        changeObserverCancellable = observer.changes.sink { [weak self] change in
            guard let self else { return }
            Task { @MainActor in self.applyExternalChange(change) }
        }
    }

    private func applyExternalChange(_ change: iCloudChangeObserver.Change) {
        switch change.kind {
        case .added, .updated:
            guard let svc = persistenceService as? FilePersistenceService else { return }
            do {
                guard let resolved = try svc.loadTab(id: change.tabID) else { return }
                let (updated, bucket) = resolved
                switch bucket {
                case .active:
                    if shouldApplyExternalUpdate(updated, currentlyAt: tabs[change.tabID]) {
                        tabs[change.tabID] = updated
                    }
                case .archived:
                    if !archivedTabs.isEmpty { archivedTabs[change.tabID] = updated }
                    tabs.removeValue(forKey: change.tabID)
                case .trash:
                    if !trashedTabs.isEmpty  { trashedTabs[change.tabID] = updated }
                    tabs.removeValue(forKey: change.tabID)
                }
            } catch {
                Log.sync.error("Failed to load iCloud update for \(change.tabID, privacy: .public): \(error.localizedDescription)")
            }
        case .removed:
            if tabs.removeValue(forKey: change.tabID) != nil
                || archivedTabs.removeValue(forKey: change.tabID) != nil
                || trashedTabs.removeValue(forKey: change.tabID) != nil {
                Log.sync.debug("Pulled iCloud deletion for \(change.tabID, privacy: .public)")
            }
        }
    }

    private func shouldApplyExternalUpdate(_ updated: TabRecord, currentlyAt local: TabRecord?) -> Bool {
        guard let local else { return true }
        if local.updatedAt >= updated.updatedAt
            && local.url == updated.url
            && local.title == updated.title
            && local.dominantColor == updated.dominantColor
            && local.isPinned == updated.isPinned
            && local.isPinnedTab == updated.isPinnedTab {
            return false
        }
        return true
    }

    // MARK: - Loads

    public func loadAll() {
        do {
            let loaded = try persistenceService.loadActive()
            tabs = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            Log.persist.info("Loaded \(loaded.count) active tabs")
        } catch {
            Log.persist.error("Failed to load tabs: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public func loadArchived() -> [TabRecord] {
        do {
            let loaded = try persistenceService.loadArchived()
            archivedTabs = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            return loaded
        } catch {
            Log.persist.error("Failed to load archived tabs: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    public func loadTrashed() -> [TabRecord] {
        do {
            let loaded = try persistenceService.loadTrashed()
            trashedTabs = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            return loaded
        } catch {
            Log.persist.error("Failed to load trashed tabs: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Create

    @discardableResult
    public func createTab(
        url: URL? = nil,
        frame: PersistedRect = .default
    ) -> TabRecord {
        let maxOrder = tabs.values.map(\.manualSortOrder).max() ?? -1
        var tab = TabRecord(url: url, frame: frame)
        tab.manualSortOrder = maxOrder + 1
        tabs[tab.id] = tab
        persistImmediately(tab.id)
        Log.tab.info("Created tab \(tab.id, privacy: .public)")
        return tab
    }

    // MARK: - Mutators (active)

    public func updateURL(tabID: UUID, url: URL?) {
        guard var tab = tabs[tabID] else { return }
        tab.url = url
        tab.lastVisitedAt = Date()
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateTitle(tabID: UUID, title: String) {
        guard var tab = tabs[tabID] else { return }
        guard tab.title != title else { return }
        tab.title = title
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateScroll(tabID: UUID, y: Double) {
        guard var tab = tabs[tabID] else { return }
        tab.scrollY = y
        tabs[tabID] = tab
        pendingTabIDs.insert(tabID)
        scrollSaveSubject.send(tabID)
    }

    public func updatePinned(tabID: UUID, isPinned: Bool) {
        guard var tab = tabs[tabID] else { return }
        tab.isPinned = isPinned
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updatePinnedTab(tabID: UUID, isPinnedTab: Bool) {
        guard var tab = tabs[tabID] else { return }
        tab.isPinnedTab = isPinnedTab
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateLiveMode(tabID: UUID, interval: LiveModeInterval) {
        guard var tab = tabs[tabID] else { return }
        tab.liveModeInterval = interval
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateDominantColor(tabID: UUID, rgba: Data?) {
        guard var tab = tabs[tabID] else { return }
        guard tab.dominantColor != rgba else { return }
        tab.dominantColor = rgba
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateAutoTintFromSite(tabID: UUID, enabled: Bool) {
        guard var tab = tabs[tabID] else { return }
        tab.autoTintFromSite = enabled
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateFrame(tabID: UUID, frame: PersistedRect) {
        guard var tab = tabs[tabID] else { return }
        tab.frame = frame
        tabs[tabID] = tab
        pendingTabIDs.insert(tabID)
        frameSaveSubject.send(tabID)
    }

    public func updateFaviconRef(tabID: UUID, ref: String?) {
        guard var tab = tabs[tabID] else { return }
        guard tab.faviconRef != ref else { return }
        tab.faviconRef = ref
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateSnapshotRef(tabID: UUID, ref: String?) {
        guard var tab = tabs[tabID] else { return }
        tab.snapshotRef = ref
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func markClosed(tabID: UUID, isClosed: Bool) {
        guard var tab = tabs[tabID] else { return }
        tab.isClosed = isClosed
        // isClosed is local-only display state — don't bump updatedAt.
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    public func updateManualSortOrder(tabID: UUID, order: Int) {
        guard var tab = tabs[tabID] else { return }
        tab.manualSortOrder = order
        tabs[tabID] = tab
        persistImmediately(tabID)
    }

    @discardableResult
    public func duplicateTab(tabID: UUID) -> TabRecord? {
        guard let original = tabs[tabID] else { return nil }
        var dup = TabRecord(
            url: original.url,
            title: original.title
        )
        dup.updatedAt = Date()
        tabs[dup.id] = dup
        persistImmediately(dup.id)
        return dup
    }

    // MARK: - Archive / trash

    public func archive(tabID: UUID) {
        guard var tab = tabs[tabID] else { return }
        tab.isArchived = true
        tab.updatedAt = Date()
        tabs.removeValue(forKey: tabID)
        archivedTabs[tabID] = tab
        do { try persistenceService.save(tab: tab) }
        catch { Log.persist.error("Archive failed: \(error.localizedDescription)") }
    }

    public func unarchive(tabID: UUID) {
        guard var tab = archivedTabs[tabID] ?? loadOne(.archived, id: tabID) else { return }
        tab.isArchived = false
        tab.updatedAt = Date()
        archivedTabs.removeValue(forKey: tabID)
        tabs[tabID] = tab
        do { try persistenceService.save(tab: tab) }
        catch { Log.persist.error("Unarchive failed: \(error.localizedDescription)") }
    }

    public func trash(tabID: UUID) {
        let src: TabRecord? = tabs[tabID]
            ?? archivedTabs[tabID]
            ?? loadOne(.active, id: tabID)
            ?? loadOne(.archived, id: tabID)
        guard var tab = src else { return }
        tab.isInTrash = true
        tab.trashedAt = Date()
        tab.isArchived = false
        tab.updatedAt = Date()
        tabs.removeValue(forKey: tabID)
        archivedTabs.removeValue(forKey: tabID)
        trashedTabs[tabID] = tab
        do { try persistenceService.save(tab: tab) }
        catch { Log.persist.error("Trash failed: \(error.localizedDescription)") }
    }

    public func restoreFromTrash(tabID: UUID) {
        guard var tab = trashedTabs[tabID] ?? loadOne(.trash, id: tabID) else { return }
        tab.isInTrash = false
        tab.trashedAt = nil
        tab.updatedAt = Date()
        trashedTabs.removeValue(forKey: tabID)
        tabs[tabID] = tab
        do { try persistenceService.save(tab: tab) }
        catch { Log.persist.error("Restore failed: \(error.localizedDescription)") }
    }

    public func deleteForever(tabID: UUID) {
        tabs.removeValue(forKey: tabID)
        archivedTabs.removeValue(forKey: tabID)
        trashedTabs.removeValue(forKey: tabID)
        pendingTabIDs.remove(tabID)
        try? persistenceService.permanentlyDelete(tabID: tabID)
    }

    public func emptyTrash() {
        let toRemove = Array(trashedTabs.keys)
        for id in toRemove { try? persistenceService.permanentlyDelete(tabID: id) }
        trashedTabs.removeAll()
    }

    public func purgeOldTrash(maxAge seconds: TimeInterval = 30 * 24 * 60 * 60) {
        let cutoff = Date().addingTimeInterval(-seconds)
        try? persistenceService.purgeExpiredTrash(olderThan: cutoff)
        if !trashedTabs.isEmpty {
            trashedTabs = trashedTabs.filter { (_, t) in (t.trashedAt ?? t.updatedAt) >= cutoff }
        }
    }

    // MARK: - Flush

    public func flushPendingSaves() {
        for id in pendingTabIDs { persistImmediately(id) }
    }

    // MARK: - Private

    private func setupDebounce() {
        frameSaveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] id in self?.persistImmediately(id) }
            .store(in: &cancellables)

        scrollSaveSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] id in self?.persistImmediately(id) }
            .store(in: &cancellables)
    }

    private func persistImmediately(_ tabID: UUID) {
        guard let tab = tabs[tabID] ?? archivedTabs[tabID] ?? trashedTabs[tabID] else { return }
        do {
            try persistenceService.save(tab: tab)
            pendingTabIDs.remove(tabID)
        } catch {
            Log.persist.error("Save failed for \(tabID, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func loadOne(_ bucket: StorageBucket, id: UUID) -> TabRecord? {
        guard let svc = persistenceService as? FilePersistenceService else { return nil }
        return (try? svc.loadTab(id: id))?.tab
    }
}
