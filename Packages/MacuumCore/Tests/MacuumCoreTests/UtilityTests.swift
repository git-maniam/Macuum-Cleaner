import XCTest
@testable import MacuumCore

final class UtilityTests: XCTestCase {
    func testPathExpander() {
        let home = URL(fileURLWithPath: "/Users/x")
        XCTAssertEqual(PathExpander.expand("~/Library", home: home), "/Users/x/Library")
        XCTAssertEqual(PathExpander.expand("~", home: home), "/Users/x")
        XCTAssertEqual(PathExpander.expand("$FOO/a/${BAR}", home: home, environment: ["FOO": "/f", "BAR": "b"]), "/f/a/b")
        XCTAssertEqual(PathExpander.expand("$NOPE/a", home: home, environment: [:]), "$NOPE/a")
    }

    func testGlob() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macuum-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for p in ["Profiles/a.default", "Profiles/b.release"] {
            let d = root.appendingPathComponent(p)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: d.appendingPathComponent("places.sqlite"))
        }
        let hits = PathExpander.glob(root.path + "/Profiles/*/places.sqlite")
        XCTAssertEqual(hits.count, 2)
    }

    func testByteFormatter() {
        XCTAssertTrue(ByteFormatter.string(from: 1_500_000_000).contains("GB"))
        XCTAssertTrue(ByteFormatter.string(from: 0).contains("0"))
    }

    func testDirectoryWalkerSizesFilesAndIgnoresSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macuum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 100_000).write(to: root.appendingPathComponent("sub/a.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("l"), withDestinationURL: URL(fileURLWithPath: "/usr"))
        let size = try DirectoryWalker.size(of: root)
        XCTAssertGreaterThanOrEqual(size, 100_000)
        XCTAssertLessThan(size, 200_000)
    }

    func testCategoryInvariants() {
        XCTAssertEqual(JunkCategory.allCases.count, 24)
        for c in JunkCategory.allCases where c.risk == .advisory { XCTAssertFalse(c.selectsFilesByDefault) }
        XCTAssertFalse(JunkCategory.iOSBackups.isEnabledByDefault)
        XCTAssertTrue(JunkCategory.defaultEnabled.contains(.logs))
    }

    func testSettingsRoundTripAndReset() {
        let d = UserDefaults(suiteName: "macuum-test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: d)
        var s = store.load(); s.permanentDeleteEnabled = true; s.excludedPaths = ["~/x"]
        store.save(s)
        XCTAssertEqual(store.load(), s)
        store.reset()
        XCTAssertEqual(store.load(), AppSettings())
    }

    func testUnusedAppThreshold() {
        let old = InstalledApp(bundleURL: URL(fileURLWithPath: "/Applications/A.app"), bundleIdentifier: "a", displayName: "A",
                               version: "1", vendorName: "", bundleSize: 10,
                               lastUsedDate: Date(timeIntervalSinceNow: -100 * 86_400), isSystemApp: false)
        XCTAssertTrue(old.isUnused(thresholdDays: 90))
        XCTAssertFalse(old.isUnused(thresholdDays: 180))
    }
}
