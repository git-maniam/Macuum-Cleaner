import Foundation

/// Category 21. Desktop screenshots older than the configured threshold; never pre-selected.
public struct ScreenshotScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .screenshots
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    static func isScreenshotName(_ name: String) -> Bool {
        (name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ")) && name.lowercased().hasSuffix(".png")
    }

    public func scan() async throws -> [JunkFile] {
        let threshold = TimeInterval(context.settings.oldScreenshotThresholdDays) * 86_400
        var out: [JunkFile] = []
        for url in DirectoryWalker.children(of: context.home.appendingPathComponent("Desktop")) where Self.isScreenshotName(url.lastPathComponent) {
            guard context.now.timeIntervalSince(DirectoryWalker.modificationDate(of: url)) >= threshold else { continue }
            if let f = try ScannerSupport.junkFile(url: url, category: .screenshots, context: context) { out.append(f) }
        }
        return out
    }
}
