import Foundation

public struct JunkFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let lastModified: Date
    public let category: JunkCategory
    public var isSelected: Bool
    public var displayName: String
    public var metadata: [String: String]
    /// Non-file items (e.g. Time Machine snapshots) carry an action key instead of a path.
    public var isFileSystemItem: Bool

    /// Advisory-only items are shown for information and can never be removed by the app.
    public var isAdvisoryOnly: Bool { metadata["advisoryOnly"] == "true" }

    public init(
        id: UUID = UUID(),
        url: URL,
        size: Int64,
        lastModified: Date,
        category: JunkCategory,
        isSelected: Bool? = nil,
        displayName: String? = nil,
        metadata: [String: String] = [:],
        isFileSystemItem: Bool = true
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.lastModified = lastModified
        self.category = category
        self.isSelected = isSelected ?? category.selectsFilesByDefault
        self.displayName = displayName ?? url.lastPathComponent
        self.metadata = metadata
        self.isFileSystemItem = isFileSystemItem
    }
}
