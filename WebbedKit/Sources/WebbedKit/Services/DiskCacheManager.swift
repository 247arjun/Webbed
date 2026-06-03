import Foundation

// MARK: - DiskCacheManager

/// Aggregates the two device-local caches Webbed keeps on disk:
///
/// 1. **Favicons** — `Caches/WebbedFavicons/`, owned by `FaviconCache`.
/// 2. **Snapshots** — `<uuid>.png` sidecars inside the tabs directory
///    (and its `Archived/`, `Trash/` subfolders).
///
/// Surfaces sizes for the Settings UI and provides clear / regenerate
/// actions. Regenerate is implemented as a clear — on macOS the next time
/// a tab loads, its `WKScriptMessageHandler` reports the favicon and
/// `didFinishNavigation` produces a fresh snapshot.
@MainActor
public final class DiskCacheManager {

    public static let shared = DiskCacheManager()
    private init() {}

    // MARK: - Stats

    public struct Stats: Equatable, Sendable {
        public var faviconBytes: Int64
        public var faviconCount: Int
        public var snapshotBytes: Int64
        public var snapshotCount: Int

        public var totalBytes: Int64 { faviconBytes + snapshotBytes }
        public var totalCount: Int   { faviconCount + snapshotCount }

        public static let zero = Stats(faviconBytes: 0, faviconCount: 0,
                                       snapshotBytes: 0, snapshotCount: 0)
    }

    /// Walk both cache directories and tally their on-disk footprint.
    /// Cheap enough for Settings; runs on the main actor.
    public func stats(tabsDirectory: URL) -> Stats {
        let (favBytes, favCount) = sizeAndCount(of: FaviconCache.directory)
        let (snapBytes, snapCount) = snapshotSizeAndCount(in: tabsDirectory)
        return Stats(faviconBytes: favBytes, faviconCount: favCount,
                     snapshotBytes: snapBytes, snapshotCount: snapCount)
    }

    // MARK: - Clear

    public func clearFavicons() {
        FaviconCache.shared.clearAll()
    }

    /// Wipe every `<uuid>.png` snapshot in every bucket and forget the
    /// `snapshotRef` field on each TabRecord so the next visit captures
    /// a fresh one.
    public func clearSnapshots(tabsDirectory: URL, tabStore: TabStore) {
        let fm = FileManager.default
        for sub in ["", "Archived", "Trash"] {
            let dir = sub.isEmpty
                ? tabsDirectory
                : tabsDirectory.appendingPathComponent(sub, isDirectory: true)
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "png" {
                try? fm.removeItem(at: url)
            }
        }
        // Forget the refs; regeneration happens on next visit naturally.
        for tab in tabStore.tabs.values where tab.snapshotRef != nil {
            tabStore.updateSnapshotRef(tabID: tab.id, ref: nil)
        }
    }

    /// "Regenerate" = clear, then optionally bump version counters so any
    /// in-memory list rows redraw. Actual regeneration is lazy — favicons
    /// re-download when the user next visits the tab, snapshots re-capture
    /// on next didFinishNavigation.
    public func regenerateFavicons(tabStore: TabStore) {
        clearFavicons()
        for tab in tabStore.tabs.values where tab.faviconRef != nil {
            tabStore.updateFaviconRef(tabID: tab.id, ref: nil)
        }
    }

    public func regenerateSnapshots(tabsDirectory: URL, tabStore: TabStore) {
        clearSnapshots(tabsDirectory: tabsDirectory, tabStore: tabStore)
    }

    // MARK: - Helpers

    private func sizeAndCount(of dir: URL) -> (Int64, Int) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return (0, 0) }
        var bytes: Int64 = 0
        var count = 0
        for u in contents {
            guard let vals = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            bytes += Int64(vals.fileSize ?? 0)
            count += 1
        }
        return (bytes, count)
    }

    private func snapshotSizeAndCount(in tabsDirectory: URL) -> (Int64, Int) {
        var total: Int64 = 0
        var count = 0
        for sub in ["", "Archived", "Trash"] {
            let dir = sub.isEmpty
                ? tabsDirectory
                : tabsDirectory.appendingPathComponent(sub, isDirectory: true)
            let (b, c) = sizeAndCount(of: dir)
            // sizeAndCount counts json + png; restrict to png by re-walking.
            // Cheap alt: walk once and filter inline.
            _ = (b, c)
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for u in contents where u.pathExtension == "png" {
                if let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(size)
                    count += 1
                }
            }
        }
        return (total, count)
    }
}

// MARK: - Formatter

public extension Int64 {
    /// Human-readable byte size like "1.2 MB".
    var bytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
