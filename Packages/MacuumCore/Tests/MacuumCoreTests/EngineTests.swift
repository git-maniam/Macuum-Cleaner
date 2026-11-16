import XCTest
@testable import MacuumCore

/// Sandbox helper: a throwaway "home" so no test touches the real disk.
final class Sandbox {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("macuum-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ rel: String, bytes: Int = 1000) throws -> URL {
        let u = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: u)
        return u
    }
    var validator: SafetyValidator { SafetyValidator(home: root, ownBundleURL: nil, runningAppPaths: { [] }) }
    func context(fda: Bool = false) -> ScanContext {
        ScanContext(home: root, systemLibrary: root.appendingPathComponent("SysLibrary"), tempDirs: [], logDirs: [],
                    volumesRoot: root.appendingPathComponent("Volumes"), applicationDirs: [root.appendingPathComponent("Applications")],
                    hasFullDiskAccess: fda, validator: validator)
    }
}

struct StubScanner: ScannerProtocol {
    let categoryID: JunkCategory
    let files: [JunkFile]
    var fda = false
    var requiresFullDiskAccess: Bool { fda }
    func scan() async throws -> [JunkFile] { files }
}

final class EngineTests: XCTestCase {
    func jf(_ url: URL, _ cat: JunkCategory, size: Int64 = 1000) -> JunkFile {
        JunkFile(url: url, size: size, lastModified: Date(), category: cat)
    }

    func testScanEngineDedupesAcrossCategoriesAndSkipsFDA() async throws {
        let sb = try SandboxHolder.make()
        let chrome = sb.root.appendingPathComponent("Library/Caches/Google/Chrome")
        let google = sb.root.appendingPathComponent("Library/Caches/Google")
        let engine = ScanEngine(context: sb.context()) { _ in [
            StubScanner(categoryID: .appCaches, files: [self.jf(google, .appCaches), self.jf(chrome, .appCaches)]),
            StubScanner(categoryID: .browserData, files: [self.jf(chrome, .browserData)]),
            StubScanner(categoryID: .notificationHistory, files: [], fda: true),
        ] }
        let result = try await engine.runAllScans(categories: [.appCaches, .browserData, .notificationHistory]) { _ in }
        XCTAssertEqual(result.filesByCategory[.browserData]?.count, 1)
        XCTAssertEqual(result.filesByCategory[.appCaches]?.count ?? 0, 0, "ancestor/duplicate of a claimed path must be dropped")
        XCTAssertNotNil(result.skipped[.notificationHistory])
    }

    func testCleanEngineTrashesAuthorizedFilesAndBlocksOthers() async throws {
        let sb = try SandboxHolder.make()
        let good = try sb.write("Library/Caches/com.old.app/blob.bin")
        let rogue = try sb.write("Library/Caches/com.other/blob.bin")
        let gf = jf(good, .appCaches), rf = jf(rogue, .appCaches)
        let engine = CleanEngine(validator: sb.validator)
        await engine.authorize(ScanResult(startDate: Date(), endDate: Date(), filesByCategory: [.appCaches: [gf]]))
        let r = try await engine.clean(files: [gf, rf], method: .moveToTrash)
        XCTAssertEqual(r.removed.count, 1)
        XCTAssertEqual(r.blocked.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: good.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rogue.path), "unauthorized file must survive")
    }

    func testPermanentDeleteRequiresSetting() async throws {
        let sb = try SandboxHolder.make()
        let f = jf(try sb.write("Library/Caches/x/y.bin"), .appCaches)
        let off = CleanEngine(validator: sb.validator, permanentDeleteAllowed: false)
        do { _ = try await off.clean(files: [f], method: .permanentDelete); XCTFail("should throw") }
        catch { XCTAssertTrue(error is CleanError) }
        let on = CleanEngine(validator: sb.validator, permanentDeleteAllowed: true)
        await on.authorize(ScanResult(startDate: Date(), endDate: Date(), filesByCategory: [.appCaches: [f]]))
        let r = try await on.clean(files: [f], method: .permanentDelete)
        XCTAssertEqual(r.removed.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    func testCleanEngineRefusesProtectedPathEvenIfAuthorized() async throws {
        let sb = try SandboxHolder.make()
        let caches = sb.root.appendingPathComponent("Library/Caches")
        let f = jf(caches, .appCaches)
        let engine = CleanEngine(validator: sb.validator)
        await engine.authorize(ScanResult(startDate: Date(), endDate: Date(), filesByCategory: [.appCaches: [f]]))
        let r = try await engine.clean(files: [f], method: .moveToTrash)
        XCTAssertEqual(r.removed.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: caches.path))
    }
}

/// Keeps sandboxes alive for the duration of a test process (deinit cleanup happens at process exit).
enum SandboxHolder {
    nonisolated(unsafe) static var all: [Sandbox] = []
    static func make() throws -> Sandbox { let s = try Sandbox(); all.append(s); return s }
}
