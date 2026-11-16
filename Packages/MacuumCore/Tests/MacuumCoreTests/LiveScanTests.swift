import XCTest
@testable import MacuumCore

/// Read-only scan of the real machine. Opt in with MACUUM_LIVE=1; never cleans anything.
final class LiveScanTests: XCTestCase {
    func testLiveScanIsFastAndReadOnly() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACUUM_LIVE"] == "1")
        let ctx = ScanContext.live()
        let cats = JunkCategory.allCases.filter { $0 != .duplicates }
        let start = Date()
        let result = try await ScanEngine(context: ctx).runAllScans(categories: cats) { _ in }
        let secs = Date().timeIntervalSince(start)
        print("LIVE FDA=\(ctx.hasFullDiskAccess) time=\(String(format: "%.1f", secs))s total=\(ByteFormatter.string(from: result.totalSize))")
        for c in cats { print("  \(c.rawValue): \(result.filesByCategory[c]?.count ?? 0) files, \(ByteFormatter.string(from: result.size(of: c)))\(result.skipped[c].map { " [skipped: \($0)]" } ?? "")") }
        XCTAssertLessThan(secs, 30)
    }
}
