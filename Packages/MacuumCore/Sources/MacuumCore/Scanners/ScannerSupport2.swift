import Foundation
import CryptoKit

public enum ScannerError: Error, LocalizedError {
    case needsFullDiskAccess
    public var errorDescription: String? { "Requires Full Disk Access" }
}

public enum FileHasher {
    /// SHA-256 of the first `limit` bytes (or the whole file when nil), streamed in 1 MB chunks.
    public static func sha256(of url: URL, limit: Int? = nil) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try h.read(upToCount: min(1 << 20, remaining)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ScannerSupport {
    /// Lists direct children, distinguishing "doesn't exist" (returns []) from "exists but unreadable" (throws FDA error).
    static func readableChildren(of dir: URL) throws -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        do {
            return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: DirectoryWalker.sizeKeys, options: [])
        } catch let e as NSError where e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError {
            throw ScannerError.needsFullDiskAccess
        }
    }

    /// One JunkFile per regular file under `root`, filtered by `include`.
    static func walkFiles(root: URL, category: JunkCategory, context: ScanContext,
                          skipDirectory: (URL) -> Bool = { _ in false },
                          include: (URL, URLResourceValues) -> Bool) throws -> [JunkFile] {
        var out: [JunkFile] = []
        try DirectoryWalker.regularFiles(under: root, skipDirectory: { context.validator.isExcluded($0) || skipDirectory($0) }) { url, v in
            guard include(url, v), !context.validator.isExcluded(url), context.validator.validate(url).isAllowed else { return }
            out.append(JunkFile(url: url, size: Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0),
                                lastModified: v.contentModificationDate ?? .distantPast, category: category))
            if out.count % 50 == 0 { context.reporter.report(category, found: out.count, path: url.path) }
        }
        return out
    }

    static func age(_ v: URLResourceValues, now: Date) -> TimeInterval {
        now.timeIntervalSince(v.contentModificationDate ?? .distantPast)
    }
}
