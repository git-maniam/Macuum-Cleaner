import Foundation

/// Category 6. Library entries whose bundle ID exactly matches no installed app.
/// Preferences are reported by `BrokenPrefsScanner` (Category 10) so they are not double counted.
public struct AppRemnantScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .appRemnants
    let context: ScanContext
    let index: LazyAppIndex?
    public init(context: ScanContext, index: LazyAppIndex? = nil) { self.context = context; self.index = index }

    static let folders = ["Application Support", "Caches", "Containers", "Group Containers", "Logs",
                          "Application Scripts", "Saved Application State", "WebKit"]

    public func scan() async throws -> [JunkFile] {
        let idx = (index ?? LazyAppIndex(applicationDirs: context.applicationDirs)).value
        var out: [JunkFile] = []
        for folder in Self.folders {
            let dir = context.library.appendingPathComponent(folder)
            for entry in (try? ScannerSupport.readableChildren(of: dir)) ?? [] {
                try Task.checkCancellation()
                guard let id = BundleIDParser.candidate(fromEntryName: entry.lastPathComponent),
                      !idx.isInstalled(id), !context.runningBundleIDs.contains(id) else { continue }
                if let f = try ScannerSupport.junkFile(url: entry, category: .appRemnants, context: context,
                                                       displayName: "\(entry.lastPathComponent) (\(folder))",
                                                       metadata: ["bundleID": id, "location": folder]) { out.append(f) }
            }
        }
        return out
    }
}
