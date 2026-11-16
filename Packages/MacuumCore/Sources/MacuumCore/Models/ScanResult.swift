import Foundation

public struct ScanProgress: Sendable {
    public enum Phase: Sendable { case started, scanning, finished, skipped(reason: String), failed(message: String) }
    public let category: JunkCategory
    public let phase: Phase
    public let filesFound: Int
    public let currentPath: String?

    public init(category: JunkCategory, phase: Phase, filesFound: Int = 0, currentPath: String? = nil) {
        self.category = category
        self.phase = phase
        self.filesFound = filesFound
        self.currentPath = currentPath
    }
}

public struct ScanResult: Sendable {
    public let startDate: Date
    public let endDate: Date
    public var filesByCategory: [JunkCategory: [JunkFile]]
    /// Categories that were skipped (e.g. Full Disk Access missing), with a user-facing reason.
    public var skipped: [JunkCategory: String]
    public var wasCancelled: Bool

    public init(startDate: Date, endDate: Date, filesByCategory: [JunkCategory: [JunkFile]],
                skipped: [JunkCategory: String] = [:], wasCancelled: Bool = false) {
        self.startDate = startDate
        self.endDate = endDate
        self.filesByCategory = filesByCategory
        self.skipped = skipped
        self.wasCancelled = wasCancelled
    }

    public var totalSize: Int64 { filesByCategory.values.joined().reduce(0) { $0 + $1.size } }
    public var totalFileCount: Int { filesByCategory.values.reduce(0) { $0 + $1.count } }

    public func size(of category: JunkCategory) -> Int64 {
        (filesByCategory[category] ?? []).reduce(0) { $0 + $1.size }
    }
}
