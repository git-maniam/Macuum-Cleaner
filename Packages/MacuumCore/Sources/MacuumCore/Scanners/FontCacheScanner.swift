import Foundation

/// Category 14. Font registry caches, plus zero-byte and byte-identical duplicate fonts in ~/Library/Fonts.
public struct FontCacheScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .fontCaches
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        var paths = [context.library.appendingPathComponent("Caches/com.apple.FontRegistry"),
                     context.library.appendingPathComponent("Caches/ATS")]
        if context.hasFullDiskAccess { paths.append(context.systemLibrary.appendingPathComponent("Caches/com.apple.FontRegistry")) }
        var out: [JunkFile] = []
        for p in paths {
            if let f = try ScannerSupport.junkFile(url: p, category: .fontCaches, context: context) { out.append(f) }
        }
        out += try fontProblems()
        return out
    }

    private func fontProblems() throws -> [JunkFile] {
        let dir = context.library.appendingPathComponent("Fonts")
        let exts: Set<String> = ["ttf", "otf", "ttc", "dfont", "otc"]
        var out: [JunkFile] = []
        var bySize: [Int64: [(URL, Date)]] = [:]
        for u in DirectoryWalker.children(of: dir) where exts.contains(u.pathExtension.lowercased()) {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
            let size = Int64(v?.fileSize ?? 0)
            if size == 0, context.validator.validate(u).isAllowed {
                out.append(JunkFile(url: u, size: 0, lastModified: v?.contentModificationDate ?? .distantPast, category: .fontCaches,
                                    displayName: u.lastPathComponent + " (empty font)"))
            } else { bySize[size, default: []].append((u, v?.creationDate ?? .distantFuture)) }
        }
        for (size, group) in bySize where group.count > 1 {
            var byHash: [String: [(URL, Date)]] = [:]
            for (u, d) in group { byHash[try FileHasher.sha256(of: u), default: []].append((u, d)) }
            for dupes in byHash.values where dupes.count > 1 {
                for (u, _) in dupes.sorted(by: { $0.1 < $1.1 }).dropFirst() where context.validator.validate(u).isAllowed {
                    out.append(JunkFile(url: u, size: size, lastModified: DirectoryWalker.modificationDate(of: u), category: .fontCaches,
                                        displayName: u.lastPathComponent + " (duplicate font)"))
                }
            }
        }
        return out
    }
}
