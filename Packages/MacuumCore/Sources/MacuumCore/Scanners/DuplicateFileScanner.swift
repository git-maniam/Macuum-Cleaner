import Foundation

/// Category 12. Size buckets → partial hash → full SHA-256. The oldest file (by creation date) is the original and
/// is never listed; duplicates are never pre-selected.
public struct DuplicateFileScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .duplicates
    let context: ScanContext
    let minimumSize: Int64
    public init(context: ScanContext, minimumSize: Int64 = 1_024) { self.context = context; self.minimumSize = minimumSize }

    struct Candidate { let url: URL; let size: Int64; let created: Date; let modified: Date }

    public func scan() async throws -> [JunkFile] {
        var bySize: [Int64: [Candidate]] = [:]
        var seenIDs = Set<String>()
        for folder in context.settings.duplicateScanFolders {
            let root = PathExpander.url(folder, home: context.home)
            try DirectoryWalker.regularFiles(under: root, skipDirectory: { dir in
                dir.pathExtension == "app" || dir.pathExtension == "photoslibrary" || dir.lastPathComponent.hasPrefix(".")
                    || context.validator.isExcluded(dir)
            }) { url, v in
                let size = Int64(v.fileSize ?? 0)
                guard size >= minimumSize, !url.lastPathComponent.hasPrefix("."), !context.validator.isExcluded(url) else { return }
                // Hard links share an identifier and are not real duplicates.
                if let id = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
                   !seenIDs.insert("\(id)").inserted { return }
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? v.contentModificationDate ?? .distantFuture
                bySize[size, default: []].append(Candidate(url: url, size: size, created: created, modified: v.contentModificationDate ?? .distantPast))
            }
        }

        var out: [JunkFile] = []
        var groupNumber = 0
        for (size, group) in bySize where group.count > 1 {
            try Task.checkCancellation()
            var byPartial: [String: [Candidate]] = [:]
            for c in group { byPartial[try FileHasher.sha256(of: c.url, limit: 65_536), default: []].append(c) }
            for sub in byPartial.values where sub.count > 1 {
                var byFull: [String: [Candidate]] = [:]
                for c in sub { byFull[try FileHasher.sha256(of: c.url), default: []].append(c) }
                for dupes in byFull.values where dupes.count > 1 {
                    groupNumber += 1
                    let sorted = dupes.sorted { $0.created < $1.created }
                    let original = sorted[0]
                    for d in sorted.dropFirst() where context.validator.validate(d.url).isAllowed {
                        out.append(JunkFile(url: d.url, size: size, lastModified: d.modified, category: .duplicates, isSelected: false,
                                            metadata: ["group": String(groupNumber), "original": original.url.path]))
                    }
                }
            }
            context.reporter.report(.duplicates, found: out.count)
        }
        return out
    }
}
