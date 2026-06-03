import Foundation

// MARK: - StorageLocation

public enum StorageLocation: Equatable, Sendable {
    /// `~/Library/Application Support/Webbed/Tabs/` — sandboxed app container.
    case localDefault
    /// User-picked folder via security-scoped bookmark (macOS only).
    case localCustom(URL)
    /// iCloud Drive ubiquity container `Documents/` folder.
    case iCloud
}

// MARK: - StorageLocationResolver

/// Resolves a `StorageLocation` to a concrete on-disk `URL`.
public enum StorageLocationResolver {

    /// iCloud container identifier shared by both macOS and iOS targets.
    public static let iCloudContainerID = "iCloud.com.arjun.Webbed"

    public static func resolve(_ location: StorageLocation) -> URL? {
        switch location {
        case .localDefault:        return defaultLocalDirectory()
        case .localCustom(let u):  return u
        case .iCloud:              return iCloudDirectory()
        }
    }

    public static func defaultLocalDirectory() -> URL {
        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first {
            return appSupport.appendingPathComponent("Webbed/Tabs", isDirectory: true)
        }
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("Webbed/Tabs", isDirectory: true)
    }

    public static func iCloudDirectory() -> URL? {
        guard let containerURL = FileManager.default
            .url(forUbiquityContainerIdentifier: iCloudContainerID) else { return nil }
        let docs = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    public static var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
