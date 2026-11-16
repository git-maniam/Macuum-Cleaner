import Foundation

/// Category 16. Only "Mail Downloads" is removable; the Envelope Index is shown as advice and can never be removed.
public struct MailScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .mailJunk
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        var out: [JunkFile] = []
        let downloads = context.library.appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads")
        for child in (try? ScannerSupport.readableChildren(of: downloads)) ?? [] {
            if let f = try ScannerSupport.junkFile(url: child, category: .mailJunk, context: context, isSelected: false) { out.append(f) }
        }
        for index in PathExpander.glob(context.library.path + "/Mail/V*/MailData/Envelope Index") {
            let size = try DirectoryWalker.size(of: index)
            out.append(JunkFile(url: index, size: size, lastModified: DirectoryWalker.modificationDate(of: index), category: .mailJunk,
                                isSelected: false, displayName: "Mail Envelope Index (advisory — rebuilt by Mail)",
                                metadata: ["advisoryOnly": "true"]))
        }
        return out
    }
}
