import Foundation

/// Category 1. `.systemCaches` covers /Library/Caches (FDA); `.appCaches` covers ~/Library/Caches.
public struct CacheScanner: ScannerProtocol {
    public let categoryID: JunkCategory
    let context: ScanContext

    public init(kind: JunkCategory, context: ScanContext) {
        precondition(kind == .systemCaches || kind == .appCaches)
        self.categoryID = kind; self.context = context
    }

    public func scan() async throws -> [JunkFile] {
        let root: URL
        if categoryID == .systemCaches {
            guard context.scanSystemPaths else { return [] }
            guard context.hasFullDiskAccess else { throw ScannerError.needsFullDiskAccess }
            root = context.systemLibrary.appendingPathComponent("Caches")
        } else {
            root = context.library.appendingPathComponent("Caches")
        }
        return try ScannerSupport.childFiles(of: root, category: categoryID, context: context) { child in
            let name = child.lastPathComponent
            if name.hasPrefix("com.apple.LaunchServices-"), name.hasSuffix(".csstore") { return true }
            // Skip caches of running apps (directory named after the bundle ID).
            return context.runningBundleIDs.contains(name)
        }
    }
}
