import Foundation

// MARK: - TabGroup

/// Lightweight grouping for tabs. Optional in v1; the `groupID` field on
/// `TabRecord` is forward-compatible so groups can land in v1.1 without a
/// data migration.
public struct TabGroup: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var themeID: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "",
        themeID: String = "graphite",
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.themeID = themeID
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
