import Foundation

/// Category 13. Walks the home folder; skips app bundles, cloud placeholders and photo libraries.
public struct DSStoreScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .dsStore
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        let lib = context.library.path
        let skipped = [lib + "/Mobile Documents", lib + "/CloudStorage", context.home.path + "/.Trash"]
        return try ScannerSupport.walkFiles(root: context.home, category: .dsStore, context: context, skipDirectory: { dir in
            let ext = dir.pathExtension
            if ext == "app" || ext == "photoslibrary" || ext == "xcodeproj" { return true }
            return skipped.contains(dir.path)
        }) { url, _ in url.lastPathComponent == ".DS_Store" }
    }
}
