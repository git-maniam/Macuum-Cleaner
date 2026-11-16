import Foundation

/// Category 10. Orphaned `.plist` files. `com.apple.*` is skipped unless opted in; recent files are skipped.
public struct BrokenPrefsScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .brokenPrefs
    let context: ScanContext
    let index: LazyAppIndex?
    public init(context: ScanContext, index: LazyAppIndex? = nil) { self.context = context; self.index = index }

    public func scan() async throws -> [JunkFile] {
        let idx = (index ?? LazyAppIndex(applicationDirs: context.applicationDirs)).value
        let dir = context.library.appendingPathComponent("Preferences")
        var out: [JunkFile] = []
        for entry in (try? ScannerSupport.readableChildren(of: dir)) ?? [] where entry.pathExtension == "plist" {
            try Task.checkCancellation()
            let name = entry.lastPathComponent
            let isApple = name.hasPrefix("com.apple.")
            if isApple && !context.settings.includeApplePreferences { continue }
            let id = String(name.dropLast(".plist".count))
            // Apple IDs aren't judged by the generic parser, which rejects com.apple.*; here the user opted in explicitly.
            guard isApple ? id.split(separator: ".").count >= 3 : BundleIDParser.looksLikeBundleID(id) else { continue }
            if idx.isInstalled(id) || context.runningBundleIDs.contains(id) { continue }
            if context.now.timeIntervalSince(DirectoryWalker.modificationDate(of: entry)) < 7 * 86_400 { continue }
            if let f = try ScannerSupport.junkFile(url: entry, category: .brokenPrefs, context: context,
                                                   metadata: ["bundleID": id]) { out.append(f) }
        }
        return out
    }
}
