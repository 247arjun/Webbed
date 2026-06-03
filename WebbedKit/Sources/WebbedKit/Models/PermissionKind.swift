import Foundation

// MARK: - PermissionKind

/// What can be allowed/denied on a per-origin basis. Privacy-first defaults
/// (see `defaultDecision`).
public enum PermissionKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case javascript
    case popups
    case autoplay
    case camera
    case microphone
    case location
    case notifications
    case pasteboard
    case insecureContent
    case openInExternal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .javascript:      return "JavaScript"
        case .popups:          return "Pop-up Windows"
        case .autoplay:        return "Auto-play Media"
        case .camera:          return "Camera"
        case .microphone:      return "Microphone"
        case .location:        return "Location"
        case .notifications:   return "Notifications"
        case .pasteboard:      return "Clipboard Read"
        case .insecureContent: return "Insecure (HTTP) Subresources"
        case .openInExternal:  return "Always Open in External Browser"
        }
    }

    public var symbolName: String {
        switch self {
        case .javascript:      return "curlybraces"
        case .popups:          return "rectangle.on.rectangle"
        case .autoplay:        return "play.rectangle"
        case .camera:          return "camera"
        case .microphone:      return "mic"
        case .location:        return "location"
        case .notifications:   return "bell"
        case .pasteboard:      return "doc.on.clipboard"
        case .insecureContent: return "lock.open.trianglebadge.exclamationmark"
        case .openInExternal:  return "safari"
        }
    }

    /// Permissions that are silent toggles (Allow / Deny only — no system
    /// prompt to surface). The rest support a third `.ask` state because
    /// they're gated by an OS prompt the first time.
    public var supportsAsk: Bool {
        switch self {
        case .camera, .microphone, .location, .notifications, .pasteboard, .popups:
            return true
        case .javascript, .autoplay, .insecureContent, .openInExternal:
            return false
        }
    }

    /// Privacy-conscious default for power users.
    public var defaultDecision: PermissionDecision {
        switch self {
        case .javascript:      return .allow   // breaks too much when off
        case .popups:          return .deny    // privacy default
        case .autoplay:        return .deny
        case .camera:          return .ask
        case .microphone:      return .ask
        case .location:        return .ask
        case .notifications:   return .ask
        case .pasteboard:      return .ask
        case .insecureContent: return .deny
        case .openInExternal:  return .deny    // off by default; per-origin opt-in
        }
    }

    /// Changing this rule means in-flight pages need a reload to pick it up.
    public var requiresReload: Bool {
        switch self {
        case .javascript, .autoplay, .insecureContent, .openInExternal:
            return true
        default:
            return false
        }
    }
}

// MARK: - PermissionDecision

public enum PermissionDecision: String, Codable, Sendable, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ask:   return "Ask"
        case .allow: return "Allow"
        case .deny:  return "Deny"
        }
    }
}

// MARK: - OriginPermissions

public struct OriginPermissions: Codable, Equatable, Sendable, Identifiable {
    public var origin: String
    public var grants: [PermissionKind: PermissionDecision]
    public var lastUpdated: Date

    public var id: String { origin }

    public init(origin: String,
                grants: [PermissionKind: PermissionDecision] = [:],
                lastUpdated: Date = Date()) {
        self.origin = origin
        self.grants = grants
        self.lastUpdated = lastUpdated
    }

    /// Decoded shape uses string keys so the JSON sidecar is stable across
    /// PermissionKind reorderings.
    private enum CodingKeys: String, CodingKey { case origin, grants, lastUpdated }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.origin = try c.decode(String.self, forKey: .origin)
        self.lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        let raw = try c.decodeIfPresent([String: String].self, forKey: .grants) ?? [:]
        var grants: [PermissionKind: PermissionDecision] = [:]
        for (k, v) in raw {
            guard let kind = PermissionKind(rawValue: k),
                  let decision = PermissionDecision(rawValue: v) else { continue }
            grants[kind] = decision
        }
        self.grants = grants
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(origin, forKey: .origin)
        try c.encode(lastUpdated, forKey: .lastUpdated)
        let raw: [String: String] = grants.reduce(into: [:]) { acc, pair in
            acc[pair.key.rawValue] = pair.value.rawValue
        }
        try c.encode(raw, forKey: .grants)
    }
}
