import Foundation
import Combine

// MARK: - PermissionStore

/// Per-origin permission grants. Persisted to a single `permissions.json`
/// sidecar inside the same directory as tabs so it syncs through iCloud
/// just like tab records.
@MainActor
public final class PermissionStore: ObservableObject {

    @Published public private(set) var origins: [String: OriginPermissions] = [:]
    @Published public private(set) var defaults: [PermissionKind: PermissionDecision]

    private let directoryProvider: @MainActor () -> URL
    private let coordinator = NSFileCoordinator()
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    public init(directoryProvider: @MainActor @escaping () -> URL) {
        self.directoryProvider = directoryProvider
        self.defaults = Self.builtInDefaults()
        load()
        saveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: - Lookup

    /// Resolved decision for `host` (eTLD+1 falls back to host). Consults the
    /// origin's grant, then the global default, then the kind's privacy default.
    public func decision(for host: String?, kind: PermissionKind) -> PermissionDecision {
        let key = canonicalHost(host)
        if !key.isEmpty, let perOrigin = origins[key]?.grants[kind] {
            return perOrigin
        }
        return defaults[kind] ?? kind.defaultDecision
    }

    public func grants(for host: String?) -> [PermissionKind: PermissionDecision] {
        let key = canonicalHost(host)
        return origins[key]?.grants ?? [:]
    }

    // MARK: - Mutators

    public func setDecision(for host: String, kind: PermissionKind, decision: PermissionDecision) {
        let key = canonicalHost(host)
        guard !key.isEmpty else { return }
        var record = origins[key] ?? OriginPermissions(origin: key)
        if decision == kind.defaultDecision && record.grants[kind] == nil {
            // Nothing to do.
            return
        }
        record.grants[kind] = decision
        record.lastUpdated = Date()
        origins[key] = record
        saveSubject.send()
    }

    /// Reset a specific kind to "use the default".
    public func resetDecision(for host: String, kind: PermissionKind) {
        let key = canonicalHost(host)
        guard var record = origins[key] else { return }
        record.grants.removeValue(forKey: kind)
        if record.grants.isEmpty {
            origins.removeValue(forKey: key)
        } else {
            record.lastUpdated = Date()
            origins[key] = record
        }
        saveSubject.send()
    }

    /// Forget every grant for this origin.
    public func resetOrigin(_ host: String) {
        let key = canonicalHost(host)
        guard origins.removeValue(forKey: key) != nil else { return }
        saveSubject.send()
    }

    /// Set the global "On Other Sites" default for a permission kind.
    public func setDefault(_ kind: PermissionKind, decision: PermissionDecision) {
        defaults[kind] = decision
        saveSubject.send()
    }

    public func resetAll() {
        origins.removeAll()
        defaults = Self.builtInDefaults()
        saveSubject.send()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        directoryProvider().appendingPathComponent("permissions.json")
    }

    public func load() {
        var loadError: Error?
        var coordErr: NSError?
        var data: Data?
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordErr) { url in
            if FileManager.default.fileExists(atPath: url.path) {
                do { data = try Data(contentsOf: url) } catch { loadError = error }
            }
        }
        if let coordErr {
            Log.persist.debug("PermissionStore load (coord): \(coordErr.localizedDescription, privacy: .public)")
            return
        }
        if let loadError {
            Log.persist.debug("PermissionStore load: \(loadError.localizedDescription, privacy: .public)")
            return
        }
        guard let data else { return }
        do {
            let decoded = try JSONDecoder.iso8601.decode(StoreFile.self, from: data)
            self.origins = Dictionary(uniqueKeysWithValues: decoded.origins.map { ($0.origin, $0) })
            self.defaults = decoded.defaults.merging(Self.builtInDefaults()) { current, _ in current }
        } catch {
            Log.persist.error("PermissionStore decode failed: \(error.localizedDescription)")
        }
    }

    public func save() {
        let file = StoreFile(
            defaults: defaults,
            origins: origins.values.sorted { $0.origin < $1.origin }
        )
        let data: Data
        do {
            data = try JSONEncoder.iso8601Sorted.encode(file)
        } catch {
            Log.persist.error("PermissionStore encode failed: \(error.localizedDescription)")
            return
        }
        var coordErr: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordErr) { url in
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            do { try data.write(to: url, options: .atomic) } catch { thrown = error }
        }
        if let coordErr {
            Log.persist.error("PermissionStore save (coord): \(coordErr.localizedDescription)")
        }
        if let thrown {
            Log.persist.error("PermissionStore save: \(thrown.localizedDescription)")
        }
    }

    // MARK: - Helpers

    public static func canonicalHost(_ host: String?) -> String {
        let trimmed = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("www.") { return String(trimmed.dropFirst(4)) }
        return trimmed
    }

    private func canonicalHost(_ host: String?) -> String { Self.canonicalHost(host) }

    private static func builtInDefaults() -> [PermissionKind: PermissionDecision] {
        var dict: [PermissionKind: PermissionDecision] = [:]
        for kind in PermissionKind.allCases { dict[kind] = kind.defaultDecision }
        return dict
    }

    // MARK: - On-disk shape

    private struct StoreFile: Codable {
        var defaults: [PermissionKind: PermissionDecision]
        var origins: [OriginPermissions]

        enum CodingKeys: String, CodingKey { case defaults, origins }

        init(defaults: [PermissionKind: PermissionDecision], origins: [OriginPermissions]) {
            self.defaults = defaults
            self.origins = origins
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.origins = try c.decodeIfPresent([OriginPermissions].self, forKey: .origins) ?? []
            let raw = try c.decodeIfPresent([String: String].self, forKey: .defaults) ?? [:]
            var d: [PermissionKind: PermissionDecision] = [:]
            for (k, v) in raw {
                guard let kind = PermissionKind(rawValue: k),
                      let decision = PermissionDecision(rawValue: v) else { continue }
                d[kind] = decision
            }
            self.defaults = d
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(origins, forKey: .origins)
            let raw: [String: String] = defaults.reduce(into: [:]) { acc, pair in
                acc[pair.key.rawValue] = pair.value.rawValue
            }
            try c.encode(raw, forKey: .defaults)
        }
    }
}

// MARK: - JSON helpers

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}

extension JSONEncoder {
    static var iso8601Sorted: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
