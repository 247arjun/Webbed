import Foundation
import CryptoKit
import Combine

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - FaviconCache

/// Two-tier favicon cache: small in-memory dictionary backed by a per-device
/// on-disk PNG store. Favicons are NOT synced through iCloud — every device
/// re-fetches from origin and caches locally, which keeps the ubiquity
/// container small.
@MainActor
public final class FaviconCache: ObservableObject {

    public static let shared = FaviconCache()

    /// Published version counter — bumps every time the cache changes so
    /// SwiftUI rows re-render. Use `.id(faviconCache.version)` if you need
    /// to force a re-render of a wider subtree.
    @Published public private(set) var version: Int = 0

    private var memory: [String: PlatformImage] = [:]   // ref → image
    private var inflight: Set<String> = []              // refs currently downloading
    private let session: URLSession
    private let memoryCap = 256

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory,
                                                 withIntermediateDirectories: true)
    }

    // MARK: - Lookup

    /// Synchronous lookup: memory only. Returns nil for a cache miss; the
    /// caller should kick off `fetch(_:)` if it knows the source URL.
    public func image(forRef ref: String?) -> PlatformImage? {
        guard let ref else { return nil }
        if let cached = memory[ref] { return cached }
        // Try disk one shot (cheap synchronous read; favicons are tiny).
        if let img = loadFromDisk(ref: ref) {
            memory[ref] = img
            return img
        }
        return nil
    }

    // MARK: - Download

    /// Fetch a favicon from `iconURL` and cache it. Returns the SHA-1-based
    /// ref string that callers can store on TabRecord.faviconRef so the next
    /// `image(forRef:)` call hits memory/disk.
    @discardableResult
    public func fetch(iconURL: URL) async -> String? {
        let ref = Self.ref(for: iconURL)
        if memory[ref] != nil { return ref }
        if loadFromDisk(ref: ref) != nil { return ref }
        guard !inflight.contains(ref) else { return ref }
        inflight.insert(ref)
        defer { inflight.remove(ref) }

        do {
            let (data, response) = try await session.data(from: iconURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            // Cap at 256 kB so a malicious origin can't bloat the cache.
            let trimmed = data.prefix(256 * 1024)
            guard let img = PlatformImage(data: Data(trimmed)) else { return nil }
            memory[ref] = img
            evictIfNeeded()
            saveToDisk(data: Data(trimmed), ref: ref)
            version &+= 1
            return ref
        } catch {
            Log.web.debug("Favicon fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Bulk ops

    /// Total bytes on disk for the favicon cache.
    public nonisolated func diskBytes() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: Self.cacheDirectory,
                                                     includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        for u in urls {
            if let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Wipe everything (memory + disk).
    public func clearAll() {
        memory.removeAll()
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: nil) {
            for u in contents { try? fm.removeItem(at: u) }
        }
        version &+= 1
    }

    // MARK: - Storage

    private nonisolated static let cacheDirectory: URL = {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WebbedFavicons", isDirectory: true)
    }()

    public nonisolated static var directory: URL { cacheDirectory }

    private nonisolated static func ref(for url: URL) -> String {
        let digest = Insecure.SHA1.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Public ref helper — used by the WKScriptMessageHandler so it can
    /// stash the ref before the download completes.
    public nonisolated static func ref(forURL url: URL) -> String { ref(for: url) }

    private func diskURL(for ref: String) -> URL {
        Self.cacheDirectory.appendingPathComponent("\(ref).bin", isDirectory: false)
    }

    private func loadFromDisk(ref: String) -> PlatformImage? {
        let url = diskURL(for: ref)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let img = PlatformImage(data: data) else { return nil }
        return img
    }

    private func saveToDisk(data: Data, ref: String) {
        let url = diskURL(for: ref)
        try? data.write(to: url, options: .atomic)
    }

    private func evictIfNeeded() {
        guard memory.count > memoryCap else { return }
        // Drop ~25% of entries (random sample; cheap and good enough).
        let drop = memory.count - Int(Double(memoryCap) * 0.75)
        for key in memory.keys.prefix(drop) {
            memory.removeValue(forKey: key)
        }
    }
}
