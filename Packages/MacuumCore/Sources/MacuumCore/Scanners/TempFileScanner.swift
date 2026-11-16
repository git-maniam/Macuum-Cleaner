import Foundation

/// Category 3. System temp dirs need Full Disk Access; Application Support is scanned for temp-pattern files.
public struct TempFileScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .tempFiles
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    static func isTempName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".tmp") || lower.hasSuffix(".temp") || name.hasPrefix("~$")
            || lower.hasSuffix(".swp") || lower.hasSuffix(".lock")
    }
    static func isIncompleteDownload(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".crdownload") || lower.hasSuffix(".part") || lower.hasSuffix(".download")
    }

    public func scan() async throws -> [JunkFile] {
        let hour: TimeInterval = 3_600
        var out: [JunkFile] = []
        if context.canScanSystemPaths {
            for dir in context.tempDirs {
                out += try ScannerSupport.childFiles(of: dir, category: .tempFiles, context: context, minAge: hour)
            }
        }
        out += try ScannerSupport.walkFiles(
            root: context.library.appendingPathComponent("Application Support"), category: .tempFiles, context: context,
            skipDirectory: { $0.pathExtension == "app" }) { url, v in
                Self.isTempName(url.lastPathComponent) && ScannerSupport.age(v, now: context.now) >= hour
            }
        out += try ScannerSupport.walkFiles(root: context.home.appendingPathComponent("Downloads"), category: .tempFiles,
                                            context: context) { url, v in
            Self.isIncompleteDownload(url.lastPathComponent) && ScannerSupport.age(v, now: context.now) >= hour
        }
        return out
    }
}
