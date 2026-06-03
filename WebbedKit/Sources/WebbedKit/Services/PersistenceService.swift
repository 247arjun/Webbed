import Foundation

// MARK: - StorageBucket

/// Where a tab's files live inside the tabs directory.
///
/// ```
/// <tabsDirectory>/
/// ├── <uuid>.json + <uuid>.png       (active)
/// ├── Archived/
/// │   └── <uuid>.json + <uuid>.png   (archived)
/// └── Trash/
///     └── <uuid>.json + <uuid>.png   (soft-deleted; purged after 30 days)
/// ```
public enum StorageBucket: String, Sendable, CaseIterable {
    case active   = ""
    case archived = "Archived"
    case trash    = "Trash"

    public var folderName: String { rawValue }
}

// MARK: - PersistenceService

public protocol PersistenceService: AnyObject, Sendable {
    func loadActive()   throws -> [TabRecord]
    func loadArchived() throws -> [TabRecord]
    func loadTrashed()  throws -> [TabRecord]

    func save(tab: TabRecord) throws
    func saveSnapshot(tabID: UUID, pngData: Data) throws
    func move(tabID: UUID, to bucket: StorageBucket) throws
    func permanentlyDelete(tabID: UUID) throws
    func purgeExpiredTrash(olderThan cutoff: Date) throws
    func migrateTabs(to newDirectory: URL) throws

    var tabsDirectory: URL { get }
}

// MARK: - FilePersistenceService

/// File-based persistence using `NSFileCoordinator` for safe concurrent
/// (iCloud) access. Mirrors the pattern in Noted's `FilePersistenceService`.
public final class FilePersistenceService: PersistenceService, @unchecked Sendable {

    public private(set) var tabsDirectory: URL
    private let coordinator = NSFileCoordinator()

    public init(directory: URL) {
        self.tabsDirectory = directory
        ensureBuckets()
    }

    // MARK: - Load

    public func loadActive()   throws -> [TabRecord] { try load(in: .active)   }
    public func loadArchived() throws -> [TabRecord] { try load(in: .archived) }
    public func loadTrashed()  throws -> [TabRecord] { try load(in: .trash)    }

    /// Load a single tab by id across all buckets — used for live updates
    /// from the iCloud change observer.
    public func loadTab(id: UUID) throws -> (tab: TabRecord, bucket: StorageBucket)? {
        for b in StorageBucket.allCases {
            let jURL = jsonURL(for: id, in: b)
            if FileManager.default.fileExists(atPath: jURL.path) {
                if let tab = try readTab(at: jURL) { return (tab, b) }
            }
        }
        return nil
    }

    // MARK: - Save

    public func save(tab: TabRecord) throws {
        ensureBuckets()
        let bucket = bucket(for: tab)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(tab)

        try coordinatedWrite(to: jsonURL(for: tab.id, in: bucket), data: jsonData)

        // Remove leftover copies from other buckets after a move.
        for other in StorageBucket.allCases where other != bucket {
            try? coordinatedRemove(jsonURL(for: tab.id, in: other))
            try? coordinatedRemove(pngURL(for: tab.id, in: other))
        }

        Log.persist.debug("Saved \(tab.id, privacy: .public) into bucket '\(bucket.rawValue, privacy: .public)')")
    }

    public func saveSnapshot(tabID: UUID, pngData: Data) throws {
        ensureBuckets()
        // Find which bucket the tab currently lives in.
        for b in StorageBucket.allCases {
            if FileManager.default.fileExists(atPath: jsonURL(for: tabID, in: b).path) {
                try coordinatedWrite(to: pngURL(for: tabID, in: b), data: pngData)
                return
            }
        }
        // Tab metadata not yet saved — write snapshot beside where it would land (.active).
        try coordinatedWrite(to: pngURL(for: tabID, in: .active), data: pngData)
    }

    // MARK: - Move / delete

    public func move(tabID: UUID, to bucket: StorageBucket) throws {
        ensureBuckets()
        var source: StorageBucket?
        for b in StorageBucket.allCases {
            if FileManager.default.fileExists(atPath: jsonURL(for: tabID, in: b).path) {
                source = b
                break
            }
        }
        guard let src = source, src != bucket else { return }

        for ext in ["json", "png"] {
            let s = tabsDirectory.appendingPathComponent(src.folderName, isDirectory: true)
                                 .appendingPathComponent("\(tabID.uuidString).\(ext)")
            let d = tabsDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
                                 .appendingPathComponent("\(tabID.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: s.path) {
                try coordinatedMove(from: s, to: d)
            }
        }
        Log.persist.debug("Moved \(tabID, privacy: .public) '\(src.rawValue, privacy: .public)' → '\(bucket.rawValue, privacy: .public)'")
    }

    public func permanentlyDelete(tabID: UUID) throws {
        for b in StorageBucket.allCases {
            try? coordinatedRemove(jsonURL(for: tabID, in: b))
            try? coordinatedRemove(pngURL(for: tabID, in: b))
        }
        Log.persist.debug("Permanently deleted \(tabID, privacy: .public)")
    }

    public func purgeExpiredTrash(olderThan cutoff: Date) throws {
        let trashed = (try? loadTrashed()) ?? []
        for tab in trashed where (tab.trashedAt ?? tab.updatedAt) < cutoff {
            try? permanentlyDelete(tabID: tab.id)
        }
    }

    // MARK: - Migration

    public func migrateTabs(to newDirectory: URL) throws {
        let fm = FileManager.default
        ensureBuckets()
        try fm.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        let oldDir = tabsDirectory

        for b in StorageBucket.allCases where !b.folderName.isEmpty {
            try? fm.createDirectory(
                at: newDirectory.appendingPathComponent(b.folderName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try copyAllTabFiles(from: oldDir, to: newDirectory)
        for b in StorageBucket.allCases where !b.folderName.isEmpty {
            let src = oldDir.appendingPathComponent(b.folderName, isDirectory: true)
            let dst = newDirectory.appendingPathComponent(b.folderName, isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                try copyAllTabFiles(from: src, to: dst)
            }
        }

        for b in StorageBucket.allCases {
            let dir = oldDir.appendingPathComponent(b.folderName, isDirectory: true)
            if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in contents where f.pathExtension == "json" || f.pathExtension == "png" {
                    try? fm.removeItem(at: f)
                }
            }
        }

        tabsDirectory = newDirectory
        ensureBuckets()
        Log.persist.info("Migrated tabs (all buckets) to \(newDirectory.path, privacy: .public)")
    }

    // MARK: - Private

    private func load(in bucket: StorageBucket) throws -> [TabRecord] {
        ensureBuckets()
        let fm = FileManager.default
        let dir = tabsDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
        var tabs: [TabRecord] = []
        var loadError: Error?

        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: dir, options: [], error: &coordErr) { dirURL in
            do {
                let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                for jURL in contents where jURL.pathExtension == "json" {
                    do {
                        if let tab = try readTab(at: jURL) { tabs.append(tab) }
                    } catch {
                        Log.persist.error("Failed to load \(jURL.lastPathComponent, privacy: .public) in '\(bucket.rawValue, privacy: .public)': \(error.localizedDescription)")
                    }
                }
            } catch { loadError = error }
        }
        if let coordErr { throw coordErr }
        if let loadError { throw loadError }
        return tabs
    }

    private func readTab(at jsonURL: URL) throws -> TabRecord? {
        var tab: TabRecord?
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: jsonURL, options: [], error: &coordErr) { url in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                tab = try decoder.decode(TabRecord.self, from: data)
            } catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
        return tab
    }

    private func coordinatedWrite(to url: URL, data: Data) throws {
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordErr) { u in
            do { try data.write(to: u, options: .atomic) } catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

    private func coordinatedRemove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordErr) { u in
            do { try FileManager.default.removeItem(at: u) } catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

    private func coordinatedMove(from src: URL, to dst: URL) throws {
        try? FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var thrown: Error?
        var coordErr: NSError?
        coordinator.coordinate(
            writingItemAt: src, options: .forMoving,
            writingItemAt: dst, options: .forReplacing,
            error: &coordErr
        ) { s, d in
            do {
                if FileManager.default.fileExists(atPath: d.path) {
                    try FileManager.default.removeItem(at: d)
                }
                try FileManager.default.moveItem(at: s, to: d)
            } catch { thrown = error }
        }
        if let coordErr { throw coordErr }
        if let thrown { throw thrown }
    }

    private func copyAllTabFiles(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for f in contents where f.pathExtension == "json" || f.pathExtension == "png" {
            let dest = dst.appendingPathComponent(f.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: f, to: dest)
        }
    }

    private func bucket(for tab: TabRecord) -> StorageBucket {
        if tab.isInTrash  { return .trash }
        if tab.isArchived { return .archived }
        return .active
    }

    private func jsonURL(for id: UUID, in bucket: StorageBucket) -> URL {
        tabsDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
                     .appendingPathComponent("\(id.uuidString).json")
    }

    private func pngURL(for id: UUID, in bucket: StorageBucket) -> URL {
        tabsDirectory.appendingPathComponent(bucket.folderName, isDirectory: true)
                     .appendingPathComponent("\(id.uuidString).png")
    }

    /// Public accessor for callers that need to render a stored snapshot
    /// (e.g. the Library detail pane).
    public func snapshotURL(for id: UUID) -> URL? {
        for b in StorageBucket.allCases {
            let u = pngURL(for: id, in: b)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    private func ensureBuckets() {
        let fm = FileManager.default
        try? fm.createDirectory(at: tabsDirectory, withIntermediateDirectories: true)
        for b in StorageBucket.allCases where !b.folderName.isEmpty {
            let url = tabsDirectory.appendingPathComponent(b.folderName, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
