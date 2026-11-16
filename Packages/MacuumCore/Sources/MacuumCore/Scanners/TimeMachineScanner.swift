import Foundation

/// Category 23. Lists local APFS snapshots older than 7 days via `tmutil`. Sizes are not exposed by tmutil.
public struct TimeMachineScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .timeMachineSnapshots
    let context: ScanContext
    let runner: @Sendable (String, [String]) async throws -> ShellResult

    public init(context: ScanContext,
                runner: @escaping @Sendable (String, [String]) async throws -> ShellResult = { try await ShellRunner.run($0, $1, timeout: 60) }) {
        self.context = context; self.runner = runner
    }

    /// Parses `com.apple.TimeMachine.2024-01-31-120000.local` lines into (stamp, date).
    static func parse(_ output: String) -> [(stamp: String, date: Date)] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd-HHmmss"
        var out: [(String, Date)] = []
        for line in output.split(separator: "\n") {
            guard let r = line.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { continue }
            let stamp = String(line[r])
            if let d = f.date(from: stamp) { out.append((stamp, d)) }
        }
        return out
    }

    public func scan() async throws -> [JunkFile] {
        let r = try await runner("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        guard r.succeeded else { throw ScannerError.needsFullDiskAccess }
        return Self.parse(r.stdout)
            .filter { context.now.timeIntervalSince($0.date) > 7 * 86_400 }
            .map { stamp, date in
                JunkFile(url: URL(string: "tmsnapshot:///\(stamp)")!, size: 0, lastModified: date, category: .timeMachineSnapshots,
                         isSelected: false, displayName: "Snapshot \(stamp)", metadata: ["snapshotDate": stamp],
                         isFileSystemItem: false)
            }
    }
}
