import Foundation

/// Category 8. One entry per backup folder, with device info read from its Info.plist. Never pre-selected.
public struct iOSBackupScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .iOSBackups
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        let dir = context.library.appendingPathComponent("Application Support/MobileSync/Backup")
        var out: [JunkFile] = []
        for backup in try ScannerSupport.readableChildren(of: dir) where backup.lastPathComponent != ".DS_Store" {
            try Task.checkCancellation()
            var meta: [String: String] = [:]
            var date = DirectoryWalker.modificationDate(of: backup)
            var name = backup.lastPathComponent
            if let data = try? Data(contentsOf: backup.appendingPathComponent("Info.plist")),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                if let d = plist["Device Name"] as? String { meta["device"] = d; name = d }
                if let v = plist["Product Version"] as? String { meta["iOSVersion"] = v }
                if let t = plist["Product Type"] as? String { meta["model"] = t }
                if let l = plist["Last Backup Date"] as? Date { date = l; meta["backupDate"] = ISO8601DateFormatter().string(from: l) }
            }
            guard context.validator.validate(backup).isAllowed else { continue }
            let size = try DirectoryWalker.size(of: backup)
            out.append(JunkFile(url: backup, size: size, lastModified: date, category: .iOSBackups, isSelected: false,
                                displayName: name, metadata: meta))
        }
        if let newest = out.max(by: { $0.lastModified < $1.lastModified }), out.count > 1,
           let i = out.firstIndex(of: newest) { out[i].metadata["recommendation"] = "Most recent backup — consider keeping" }
        return out
    }
}
