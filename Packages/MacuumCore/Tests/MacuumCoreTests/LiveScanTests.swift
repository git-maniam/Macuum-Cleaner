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

final class LiveTimingTests: XCTestCase {
    func testPerScannerTiming() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACUUM_TIMING"] == "1")
        let ctx = ScanContext.live()
        for s in ScannerRegistry.allScanners(context: ctx) where s.categoryID != .duplicates && (ProcessInfo.processInfo.environment["MACUUM_ONLY"].map { $0 == s.categoryID.rawValue } ?? true) {
            let t = Date()
            let n = (try? await s.scan().count) ?? -1
            FileHandle.standardError.write(Data("TIMING \(s.categoryID.rawValue) \(String(format: "%.1f", Date().timeIntervalSince(t)))s n=\(n)\n".utf8))
        }
    }
}

final class LiveAppDiscoveryTests: XCTestCase {
    func testLiveDiscovery() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACUUM_LIVE"] == "1")
        let t = Date()
        let apps = try await AppDiscoveryEngine().discoverApps()
        let secs = Date().timeIntervalSince(t)
        let user = apps.filter { !$0.isSystemApp }
        print("LIVEAPPS count=\(apps.count) user=\(user.count) time=\(String(format: "%.1f", secs))s total=\(ByteFormatter.string(from: apps.reduce(0) { $0 + $1.totalSizeOnDisk }))")
        for a in user.sorted(by: { $0.totalSizeOnDisk > $1.totalSizeOnDisk }).prefix(5) {
            print("  \(a.displayName) v\(a.version) vendor=\(a.vendorName) bundle=\(ByteFormatter.string(from: a.bundleSize)) leftovers=\(a.remnants.count) last=\(a.lastUsedDate.map { "\($0)" } ?? "nil")")
        }
        XCTAssertLessThan(secs, 10)
    }
}
