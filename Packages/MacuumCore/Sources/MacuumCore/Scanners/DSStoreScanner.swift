import Foundation

/// Category 13. Lean walk of the home folder: only directory/symlink flags are read per entry, and trees where
/// Finder never writes user-visible metadata or that can be enormous (Library, hidden folders, git working trees,
/// dependency/build folders) are pruned. A wall-clock budget stops runaway walks; results found so far are kept.
public struct DSStoreScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .dsStore
    let context: ScanContext
    /// Backstop so a pathological home folder can't blow the 30 s scan target.
    let timeBudget: TimeInterval
    public init(context: ScanContext, timeBudget: TimeInterval = 20) { self.context = context; self.timeBudget = timeBudget }

    static let prunedNames: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", "Pods", "DerivedData", ".build", "build", "target", "venv", ".venv",
        "__pycache__", ".npm", ".cargo", ".rustup", ".gradle", ".m2", ".nvm", ".pyenv", ".rbenv", ".cache", ".Trash",
        ".docker", ".vscode", ".cocoapods", ".pub-cache", "Carthage"
    ]
    static let prunedExtensions: Set<String> = ["app", "photoslibrary", "xcodeproj", "xcworkspace", "framework", "bundle", "musiclibrary", "imovielibrary"]

    public func scan() async throws -> [JunkFile] {
        let library = context.library.path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(at: context.home, includingPropertiesForKeys: keys, options: [],
                                                     errorHandler: { _, _ in true }) else { return [] }
        var out: [JunkFile] = []
        var counter = 0
        let deadline = Date().addingTimeInterval(timeBudget)
        for case let url as URL in e {
            counter += 1
            if counter % 512 == 0 { try Task.checkCancellation(); if Date() > deadline { break } }
            let name = url.lastPathComponent
            if name == ".DS_Store" {
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]),
                      v.isRegularFile == true, !context.validator.isExcluded(url), context.validator.validate(url).isAllowed else { continue }
                out.append(JunkFile(url: url, size: Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0),
                                    lastModified: v.contentModificationDate ?? .distantPast, category: .dsStore))
                if out.count % 50 == 0 { context.reporter.report(.dsStore, found: out.count, path: url.path) }
                continue
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { e.skipDescendants(); continue }
            guard v.isDirectory == true else { continue }
            if name.hasPrefix(".") || FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                e.skipDescendants(); continue
            }
            if url.path == library || Self.prunedNames.contains(name) || Self.prunedExtensions.contains(url.pathExtension)
                || context.validator.isExcluded(url) { e.skipDescendants() }
        }
        return out
    }
}
