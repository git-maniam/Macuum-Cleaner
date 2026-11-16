import Foundation

public enum FullDiskAccess {
    /// Probes a TCC-protected file. Readable only when the process has Full Disk Access.
    public static func isGranted() -> Bool {
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        guard FileManager.default.fileExists(atPath: probe) else { return false }
        guard let h = try? FileHandle(forReadingFrom: URL(fileURLWithPath: probe)) else { return false }
        try? h.close()
        return true
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
