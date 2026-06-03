import Foundation
import Combine

// MARK: - iCloudChangeObserver

/// Watches the iCloud ubiquity container for tab file changes from other
/// devices. Emits add / update / remove events keyed by tab UUID. Mirrors
/// Noted's iCloudChangeObserver.
public final class iCloudChangeObserver: @unchecked Sendable {

    public struct Change: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case added, updated, removed }
        public let kind: Kind
        public let tabID: UUID
    }

    public let changes = PassthroughSubject<Change, Never>()

    private let lock = NSLock()
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var seenIDs: Set<UUID> = []

    public init() {}

    public func start(tabsDirectory: URL) {
        stop()

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        q.notificationBatchingInterval = 0.5

        let nc = NotificationCenter.default
        let gathering = nc.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: q, queue: .main
        ) { [weak self] note in self?.handle(note) }
        let updates = nc.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: q, queue: .main
        ) { [weak self] note in self?.handle(note) }

        lock.lock()
        observers = [gathering, updates]
        query = q
        lock.unlock()

        q.start()
        Log.sync.info("iCloud change observer started for \(tabsDirectory.path, privacy: .public)")
    }

    public func stop() {
        lock.lock()
        let q = query
        let obs = observers
        query = nil
        observers.removeAll()
        seenIDs.removeAll()
        lock.unlock()

        q?.stop()
        for o in obs { NotificationCenter.default.removeObserver(o) }
    }

    private func handle(_ note: Notification) {
        guard let q = note.object as? NSMetadataQuery else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        var currentIDs: Set<UUID> = []
        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else { continue }
            if isInSecondaryBucket(item) { continue }
            let stem = (name as NSString).deletingPathExtension
            guard let id = UUID(uuidString: stem) else { continue }
            currentIDs.insert(id)
        }

        let info = note.userInfo ?? [:]
        let added   = (info[NSMetadataQueryUpdateAddedItemsKey]   as? [NSMetadataItem] ?? []).filter { !isInSecondaryBucket($0) }
        let changed = (info[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []).filter { !isInSecondaryBucket($0) }
        let removed = (info[NSMetadataQueryUpdateRemovedItemsKey] as? [NSMetadataItem] ?? []).filter { !isInSecondaryBucket($0) }

        if note.name == .NSMetadataQueryDidFinishGathering {
            lock.lock()
            let previous = seenIDs
            seenIDs = currentIDs
            lock.unlock()
            for id in currentIDs.subtracting(previous) { changes.send(.init(kind: .added,   tabID: id)) }
            for id in previous.subtracting(currentIDs) { changes.send(.init(kind: .removed, tabID: id)) }
            return
        }

        for item in added   { if let id = id(of: item) { lock.lock(); seenIDs.insert(id); lock.unlock(); changes.send(.init(kind: .added,   tabID: id)) } }
        for item in changed { if let id = id(of: item) {                                                  changes.send(.init(kind: .updated, tabID: id)) } }
        for item in removed { if let id = id(of: item) { lock.lock(); seenIDs.remove(id); lock.unlock(); changes.send(.init(kind: .removed, tabID: id)) } }
    }

    private func isInSecondaryBucket(_ item: NSMetadataItem) -> Bool {
        guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return false }
        return path.contains("/Archived/") || path.contains("/Trash/")
    }

    private func id(of item: NSMetadataItem) -> UUID? {
        guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else { return nil }
        return UUID(uuidString: (name as NSString).deletingPathExtension)
    }
}
