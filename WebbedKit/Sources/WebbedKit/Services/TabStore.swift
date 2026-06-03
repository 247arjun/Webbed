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

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
        setupDebounce()
    }

    public func swapPersistenceService(_ newService: PersistenceService) {
        self.persistenceService = newService
        Log.persist.info("Swapped persistence backend → \(newService.tabsDirectory.path, privacy: .public)")
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
        themeID: String = ThemeRegistry.defaultThemeID,
        frame: PersistedRect = .default
    ) -> TabRecord {
        let maxOrder = tabs.values.map(\.manualSortOrder).max() ?? -1
        var tab = TabRecord(url: url, themeID: themeID, frame: frame)
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

    public func updateTheme(tabID: UUID, themeID: String) {
        guard var tab = tabs[tabID] else { return }
        tab.themeID = themeID
        tab.updatedAt = Date()
        tabs[tabID] = tab
        persistImmediately(tabID)
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
            title: original.title,
            themeID: original.themeID
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
