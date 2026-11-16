import Foundation

/// Category 4. User Trash plus per-volume `.Trashes/<uid>` (local, non-boot volumes only).
public struct TrashScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .trash
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        var out: [JunkFile] = []
        let trash = context.home.appendingPathComponent(".Trash")
        for child in try ScannerSupport.readableChildren(of: trash) {
            try Task.checkCancellation()
            if child.lastPathComponent == ".DS_Store" { continue }
            if let f = try ScannerSupport.junkFile(url: child, category: .trash, context: context) { out.append(f) }
        }
        if context.hasFullDiskAccess {
            let uid = String(getuid())
            for vol in ExternalVolumes.list(root: context.volumesRoot) {
                let t = vol.appendingPathComponent(".Trashes/\(uid)")
                for child in (try? ScannerSupport.readableChildren(of: t)) ?? [] {
                    if let f = try ScannerSupport.junkFile(url: child, category: .trash, context: context) { out.append(f) }
                }
            }
        }
        return out
    }
}

public enum ExternalVolumes {
    /// Mounted, local, non-boot volumes under `root` (normally /Volumes).
    public static func list(root: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsInternalKey, .isSymbolicLinkKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))) ?? []
        return items.filter { u in
            guard let v = try? u.resourceValues(forKeys: keys) else { return false }
            if v.isSymbolicLink == true { return false }                // "Macintosh HD" -> /
            if u.resolvingSymlinksInPath().path == "/" { return false }
            return v.volumeIsLocal ?? false
        }
    }
}
