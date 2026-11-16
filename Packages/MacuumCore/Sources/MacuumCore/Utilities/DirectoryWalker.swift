import Foundation

public enum DirectoryWalker {
    static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey
    ]

    /// Allocated size of a file, or the recursive sum for a directory. Symlinks count as zero (never followed).
    /// Honors task cancellation. Unreadable entries are skipped.
    public static func size(of url: URL) throws -> Int64 {
        let values = try? url.resourceValues(forKeys: Set(sizeKeys))
        if values?.isSymbolicLink == true { return 0 }
        if values?.isDirectory != true { return fileSize(values) }

        var total: Int64 = 0
        var counter = 0
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: sizeKeys,
                                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let child as URL in e {
            counter += 1
            if counter % 256 == 0 { try Task.checkCancellation() }
            guard let v = try? child.resourceValues(forKeys: Set(sizeKeys)) else { continue }
            if v.isSymbolicLink == true { e.skipDescendants(); continue }
            if v.isRegularFile == true { total += fileSize(v) }
        }
        return total
    }

    /// Newest modification date among a directory's descendants is expensive; use the item's own date.
    public static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Direct children (including hidden), or [] if unreadable.
    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: sizeKeys, options: [])) ?? []
    }

    /// Recursively yields regular files under `root`, optionally pruning directories.
    public static func regularFiles(under root: URL,
                                    skipDirectory: (URL) -> Bool = { _ in false },
                                    visit: (URL, URLResourceValues) throws -> Void) throws {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: sizeKeys,
                                                     options: [], errorHandler: { _, _ in true }) else { return }
        var counter = 0
        for case let url as URL in e {
            counter += 1
            if counter % 256 == 0 { try Task.checkCancellation() }
            guard let v = try? url.resourceValues(forKeys: Set(sizeKeys)) else { continue }
            if v.isSymbolicLink == true { e.skipDescendants(); continue }
            if v.isDirectory == true {
                if skipDirectory(url) { e.skipDescendants() }
                continue
            }
            if v.isRegularFile == true { try visit(url, v) }
        }
    }

    private static func fileSize(_ v: URLResourceValues?) -> Int64 {
        Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
    }
}
