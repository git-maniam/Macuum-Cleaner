import Foundation

/// Category 15.
public struct QuickLookScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .quickLookCaches
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        let paths = ["Caches/com.apple.QuickLook.thumbnailcache", "Caches/QuickLook", "Application Support/Quick Look"]
        return try paths.compactMap {
            try ScannerSupport.junkFile(url: context.library.appendingPathComponent($0), category: .quickLookCaches, context: context)
        }
    }
}
