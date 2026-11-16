import Foundation

/// Category 2. Skips files modified in the last 24 h and `.log` files under 10 KB.
public struct LogScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .logs
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        var roots = [context.library.appendingPathComponent("Logs")]
        if context.canScanSystemPaths {
            roots.append(context.systemLibrary.appendingPathComponent("Logs"))
            roots.append(contentsOf: context.logDirs)
        }
        var out: [JunkFile] = []
        for root in roots {
            out += try ScannerSupport.walkFiles(root: root, category: .logs, context: context) { url, v in
                if ScannerSupport.age(v, now: context.now) < 86_400 { return false }
                if url.pathExtension == "log", (v.fileSize ?? 0) < 10_240 { return false }
                if url.lastPathComponent.hasSuffix(".journal") { return false }
                return true
            }
        }
        return out
    }
}
