import Foundation

/// Category 20. `name (1).ext` copies (only when the original sibling exists) and "conflicted copy" files.
/// Conflict copies may hold the newer edits, so they are never pre-selected.
public struct ICloudConflictScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .iCloudConflicts
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    static let numbered = try! NSRegularExpression(pattern: #"^(.*) \(\d+\)(\.[^.]+)?$"#)

    /// The name the original would have, if `name` looks like a conflict copy.
    static func originalName(for name: String) -> String?? {
        if name.contains(" conflicted copy ") { return .some(nil) }   // conflict copy, original unknown
        let ns = name as NSString
        guard let m = numbered.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let base = ns.substring(with: m.range(at: 1))
        let ext = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
        return .some(base + ext)
    }

    public func scan() async throws -> [JunkFile] {
        var out: [JunkFile] = []
        for root in [context.library.appendingPathComponent("Mobile Documents"), context.home.appendingPathComponent("iCloud Drive")] {
            out += try ScannerSupport.walkFiles(root: root, category: .iCloudConflicts, context: context,
                                                skipDirectory: { $0.pathExtension == "app" }) { url, _ in
                guard let orig = Self.originalName(for: url.lastPathComponent) else { return false }
                if let name = orig { return FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(name).path) }
                return true
            }
        }
        return out.map { var f = $0; f.isSelected = false; return f }
    }
}
