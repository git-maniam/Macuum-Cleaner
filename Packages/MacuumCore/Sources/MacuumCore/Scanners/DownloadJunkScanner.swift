import Foundation

/// Category 11. Strictly ~/Downloads; nothing is pre-selected.
public struct DownloadJunkScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .downloadJunk
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    static let copyPattern = try! NSRegularExpression(pattern: #"( \(\d+\)| copy| - Copy)(\.[^.]+)?$"#)

    static func hasCopySuffix(_ name: String) -> Bool {
        copyPattern.firstMatch(in: name, range: NSRange(location: 0, length: (name as NSString).length)) != nil
    }

    public func scan() async throws -> [JunkFile] {
        let day: TimeInterval = 86_400
        let base = TimeInterval(context.settings.oldDownloadThresholdDays) * day
        return try ScannerSupport.walkFiles(root: context.home.appendingPathComponent("Downloads"), category: .downloadJunk,
                                            context: context, skipDirectory: { $0.pathExtension == "app" }) { url, v in
            let name = url.lastPathComponent, ext = url.pathExtension.lowercased()
            let age = ScannerSupport.age(v, now: context.now)
            if TempFileScanner.isIncompleteDownload(name) { return true }
            if (ext == "dmg" || ext == "pkg") && age >= base { return true }
            if ext == "zip" && age >= base * 3 { return true }
            return Self.hasCopySuffix(name)
        }
    }
}
