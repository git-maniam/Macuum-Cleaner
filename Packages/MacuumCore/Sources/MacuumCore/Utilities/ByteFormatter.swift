import Foundation

public enum ByteFormatter {
    public static func string(from bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useAll]
        f.includesUnit = true
        f.allowsNonnumericFormatting = false
        f.zeroPadsFractionDigits = false
        return f.string(fromByteCount: bytes)
    }
}
