import Foundation

/// Category 18. Requires Full Disk Access.
public struct NotificationScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .notificationHistory
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        let dir = context.library.appendingPathComponent("Application Support/NotificationCenter")
        return try ScannerSupport.readableChildren(of: dir).compactMap {
            try ScannerSupport.junkFile(url: $0, category: .notificationHistory, context: context, isSelected: false)
        }
    }
}
