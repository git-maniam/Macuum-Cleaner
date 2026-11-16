import XCTest
@testable import MacuumCore

final class ScheduleTests: XCTestCase {
    func testPlistContents() throws {
        var s = AppSettings(); s.scheduledScanEnabled = true; s.scheduledScanDayOfWeek = 3; s.scheduledScanHour = 14
        let p = ScheduleManager.plist(settings: s, executable: "/Applications/Macuum Cleaner.app/Contents/MacOS/Macuum Cleaner")
        XCTAssertEqual(p["Label"] as? String, ScheduleManager.label)
        XCTAssertEqual((p["ProgramArguments"] as? [String])?.last, "--scheduled-scan")
        let cal = try XCTUnwrap(p["StartCalendarInterval"] as? [String: Int])
        XCTAssertEqual(cal["Weekday"], 3); XCTAssertEqual(cal["Hour"], 14)
        XCTAssertEqual(p["RunAtLoad"] as? Bool, false)
    }

    func testApplyWritesAndRemovesAgent() async throws {
        let sb = try SandboxHolder.make()
        var s = AppSettings(); s.scheduledScanEnabled = true
        try await ScheduleManager.apply(s, executable: "/x/app", home: sb.root, load: false)
        let url = ScheduleManager.plistURL(home: sb.root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        s.scheduledScanEnabled = false
        try await ScheduleManager.apply(s, executable: "/x/app", home: sb.root, load: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSystemPathsNeedOptInEvenWithFDA() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("SysLibrary/Caches/com.sys.cache/x", bytes: 500)
        var ctx = sb.context(fda: true)
        ctx.scanSystemPaths = false
        let off = try await CacheScanner(kind: .systemCaches, context: ctx).scan()
        XCTAssertTrue(off.isEmpty)
        ctx.scanSystemPaths = true
        let on = try await CacheScanner(kind: .systemCaches, context: ctx).scan()
        XCTAssertEqual(on.count, 1)
    }
}
