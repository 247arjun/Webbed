import Foundation

// MARK: - TabRecord

/// A single browser tab — the syncable unit in Webbed.
///
/// Phase 0 stub: full field set lives here so other types compile, but the
/// persistence path is added in Phase 1.
public struct TabRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL?
    public var title: String
    public var faviconRef: String?
    public var snapshotRef: String?
    public var scrollY: Double
    /// Tear-out window floats above other windows (macOS).
    public var isPinned: Bool
    /// Appears in the Pinned section of the library on all platforms.
    public var isPinnedTab: Bool
    public var groupID: UUID?
    /// macOS tear-out window frame.
    public var frame: PersistedRect
    public var createdAt: Date
    public var updatedAt: Date
    public var lastVisitedAt: Date
    /// Window is not currently open (macOS). Local-only; not synced.
    public var isClosed: Bool
    public var isArchived: Bool
    public var manualSortOrder: Int
    public var isInTrash: Bool
    public var trashedAt: Date?

    /// Auto-refresh cadence for this window. `.off` = disabled.
    public var liveModeInterval: LiveModeInterval

    /// Sampled / page-declared dominant color encoded as 4 bytes (RGBA).
    /// nil = use the theme registry color for `themeID`. Synced through
    /// iCloud so a tab opens with the same tint on every device.
    public var dominantColor: Data?

    /// When true, Webbed automatically tints the chrome based on the site's
    /// `theme-color` meta or sampled favicon. When false, the user has
    /// manually picked a theme and that choice wins.
    public var autoTintFromSite: Bool

    public init(
        id: UUID = UUID(),
        url: URL? = nil,
        title: String = "",
        faviconRef: String? = nil,
        snapshotRef: String? = nil,
        scrollY: Double = 0,
        isPinned: Bool = false,
        isPinnedTab: Bool = false,
        groupID: UUID? = nil,
        frame: PersistedRect = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastVisitedAt: Date = Date(),
        isClosed: Bool = false,
        isArchived: Bool = false,
        manualSortOrder: Int = 0,
        isInTrash: Bool = false,
        trashedAt: Date? = nil,
        liveModeInterval: LiveModeInterval = .off,
        dominantColor: Data? = nil,
        autoTintFromSite: Bool = true
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconRef = faviconRef
        self.snapshotRef = snapshotRef
        self.scrollY = scrollY
        self.isPinned = isPinned
        self.isPinnedTab = isPinnedTab
        self.groupID = groupID
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastVisitedAt = lastVisitedAt
        self.isClosed = isClosed
        self.isArchived = isArchived
        self.manualSortOrder = manualSortOrder
        self.isInTrash = isInTrash
        self.trashedAt = trashedAt
        self.liveModeInterval = liveModeInterval
        self.dominantColor = dominantColor
        self.autoTintFromSite = autoTintFromSite
    }

    // Backward-compatible decoding: any field added later defaults safely.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id              = try c.decode(UUID.self,          forKey: .id)
        self.url             = try c.decodeIfPresent(URL.self,  forKey: .url)
        self.title           = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.faviconRef      = try c.decodeIfPresent(String.self, forKey: .faviconRef)
        self.snapshotRef     = try c.decodeIfPresent(String.self, forKey: .snapshotRef)
        self.scrollY         = try c.decodeIfPresent(Double.self, forKey: .scrollY) ?? 0
        self.isPinned        = try c.decodeIfPresent(Bool.self,   forKey: .isPinned) ?? false
        self.isPinnedTab     = try c.decodeIfPresent(Bool.self,   forKey: .isPinnedTab) ?? false
        self.groupID         = try c.decodeIfPresent(UUID.self,   forKey: .groupID)
        self.frame           = try c.decodeIfPresent(PersistedRect.self, forKey: .frame) ?? .default
        self.createdAt       = try c.decodeIfPresent(Date.self,   forKey: .createdAt) ?? Date()
        self.updatedAt       = try c.decodeIfPresent(Date.self,   forKey: .updatedAt) ?? Date()
        self.lastVisitedAt   = try c.decodeIfPresent(Date.self,   forKey: .lastVisitedAt) ?? Date()
        self.isClosed        = try c.decodeIfPresent(Bool.self,   forKey: .isClosed) ?? false
        self.isArchived      = try c.decodeIfPresent(Bool.self,   forKey: .isArchived) ?? false
        self.manualSortOrder = try c.decodeIfPresent(Int.self,    forKey: .manualSortOrder) ?? 0
        self.isInTrash       = try c.decodeIfPresent(Bool.self,   forKey: .isInTrash) ?? false
        self.trashedAt       = try c.decodeIfPresent(Date.self,   forKey: .trashedAt)
        self.liveModeInterval = try c.decodeIfPresent(LiveModeInterval.self, forKey: .liveModeInterval) ?? .off
        self.dominantColor   = try c.decodeIfPresent(Data.self,   forKey: .dominantColor)
        self.autoTintFromSite = try c.decodeIfPresent(Bool.self,  forKey: .autoTintFromSite) ?? true
    }

    /// Best-effort display title — falls back to host, then to "New Tab".
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host(percentEncoded: false), !host.isEmpty { return host }
        return "New Tab"
    }

    /// Display string for address bar / list subtitle.
    public var displayURLString: String {
        url?.absoluteString ?? ""
    }
}
