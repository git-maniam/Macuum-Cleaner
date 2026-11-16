import XCTest
@testable import MacuumCore

final class SafetyValidatorTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/tester")

    func validator(exclusions: [String] = [], running: Set<String> = []) -> SafetyValidator {
        SafetyValidator(home: home, exclusions: exclusions,
                        ownBundleURL: URL(fileURLWithPath: "/Applications/Macuum Cleaner.app"),
                        runningAppPaths: { running })
    }

    func testBlocksSystemPaths() {
        let v = validator()
        for p in ["/System/Library/Foo", "/usr/bin/ls", "/bin/sh", "/sbin/mount", "/etc/hosts", "/private/etc/hosts", "/usr/local/x"] {
            XCTAssertFalse(v.validate(URL(fileURLWithPath: p)).isAllowed, p)
        }
    }

    func testBlocksProtectedDirectoriesThemselvesButAllowsChildren() {
        let v = validator()
        for p in ["/", "/Users/tester", "/Users/tester/Library", "/Users/tester/Library/Caches", "/Users/tester/Desktop", "/Applications"] {
            XCTAssertFalse(v.validate(URL(fileURLWithPath: p)).isAllowed, p)
        }
        XCTAssertTrue(v.validate(URL(fileURLWithPath: "/Users/tester/Library/Caches/com.foo.bar")).isAllowed)
        XCTAssertTrue(v.validate(URL(fileURLWithPath: "/Users/tester/Downloads/old.dmg")).isAllowed)
    }

    func testBlocksOwnBundleAndSupportFiles() {
        let v = validator()
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Applications/Macuum Cleaner.app")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Applications/Macuum Cleaner.app/Contents/MacOS/x")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Users/tester/Library/Application Support/Macuum Cleaner/history.json")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Users/tester/Library/Caches/com.macuum.cleaner")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Users/tester/Library/Preferences/com.macuum.cleaner.plist")).isAllowed)
    }

    func testExclusionsAndRunningApps() {
        let v = validator(exclusions: ["~/Downloads/keep"], running: ["/Applications/Busy.app"])
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Users/tester/Downloads/keep/a.dmg")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Users/tester/Downloads/keep")).isAllowed)
        XCTAssertTrue(v.validate(URL(fileURLWithPath: "/Users/tester/Downloads/keeper.dmg")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Applications/Busy.app")).isAllowed)
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Applications/Busy.app/Contents/Info.plist")).isAllowed)
        XCTAssertTrue(v.validate(URL(fileURLWithPath: "/Applications/Idle.app")).isAllowed)
    }

    func testDotDotTraversalIsNormalized() {
        let v = validator()
        XCTAssertFalse(v.validate(URL(fileURLWithPath: "/Users/tester/Library/Caches/../../../../System/Library")).isAllowed)
    }

    func testSymlinkedParentCannotSmuggleSystemPath() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("macuum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let link = tmp.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/usr"))
        let v = SafetyValidator(home: tmp, runningAppPaths: { [] })
        XCTAssertFalse(v.validate(link.appendingPathComponent("bin")).isAllowed)
    }
}
