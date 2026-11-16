import XCTest
@testable import MacuumCore

final class AppManagerTests: XCTestCase {
    func makeApp(_ sb: Sandbox, name: String, id: String) throws -> URL {
        let app = sb.root.appendingPathComponent("Applications/\(name).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": "2.0",
                                    "CFBundleExecutable": name, "CFBundlePackageType": "APPL",
                                    "NSHumanReadableCopyright": "Copyright © 2024 Acme Corp. All rights reserved."]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(count: 50_000).write(to: app.appendingPathComponent("Contents/MacOS/\(name)"))
        return app
    }

    func engine(_ sb: Sandbox) -> AppDiscoveryEngine {
        AppDiscoveryEngine(home: sb.root, userAppDirs: [sb.root.appendingPathComponent("Applications")],
                           systemAppDirs: [], systemLibrary: sb.root.appendingPathComponent("SysLib"))
    }

    func testDiscoveryFindsAppAndExactRemnants() async throws {
        let sb = try SandboxHolder.make()
        _ = try makeApp(sb, name: "Widget", id: "com.acme.widget")
        _ = try sb.write("Library/Application Support/com.acme.widget/db", bytes: 3_000)
        _ = try sb.write("Library/Caches/com.acme.widget/c", bytes: 2_000)
        _ = try sb.write("Library/Preferences/com.acme.widget.plist", bytes: 100)
        _ = try sb.write("Library/Preferences/com.acme.widgetpro.plist", bytes: 100)      // different app
        _ = try sb.write("Library/Group Containers/ABCDE12345.com.acme.widget/g", bytes: 100)
        _ = try sb.write("Library/Group Containers/ABCDE12345.com.acme.widgetpro/g", bytes: 100)
        _ = try sb.write("Library/Application Support/Widget/legacy", bytes: 100)          // name match
        let apps = try await engine(sb).discoverApps()
        XCTAssertEqual(apps.count, 1)
        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(app.displayName, "Widget")
        XCTAssertEqual(app.version, "2.0")
        XCTAssertEqual(app.vendorName, "Acme Corp")
        XCTAssertFalse(app.isSystemApp)
        let kinds = app.remnants.map(\.kind)
        XCTAssertEqual(Set(kinds), [.applicationSupport, .caches, .preferences, .groupContainers])
        XCTAssertEqual(app.remnants.count, 5)
        XCTAssertFalse(app.remnants.contains { $0.url.lastPathComponent.contains("widgetpro") })
        XCTAssertEqual(app.remnants.first { $0.url.lastPathComponent == "Widget" }?.isSelected, false)
        XCTAssertGreaterThan(app.totalSizeOnDisk, app.bundleSize)
    }

    func uninstaller(_ sb: Sandbox, running: Bool = false) -> UninstallEngine {
        UninstallEngine(validator: sb.validator, isRunning: { _ in running })
    }

    func testUninstallMovesBundleAndSelectedRemnantsToTrash() async throws {
        let sb = try SandboxHolder.make()
        let appURL = try makeApp(sb, name: "Widget", id: "com.acme.widget")
        _ = try sb.write("Library/Caches/com.acme.widget/c", bytes: 2_000)
        _ = try sb.write("Library/Application Support/com.acme.widget/db", bytes: 3_000)
        let found = try await engine(sb).discoverApps()
        let app = try XCTUnwrap(found.first)
        let chosen = app.remnants.filter { $0.kind == .caches }
        let r = try await uninstaller(sb).uninstall(app: app, includeRemnants: chosen)
        XCTAssertEqual(r.removedItems.count, 2)
        XCTAssertTrue(r.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sb.root.appendingPathComponent("Library/Caches/com.acme.widget").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sb.root.appendingPathComponent("Library/Application Support/com.acme.widget").path))
    }

    func testUninstallRefusesRunningSelfAndSystemApps() async throws {
        let sb = try SandboxHolder.make()
        _ = try makeApp(sb, name: "Widget", id: "com.acme.widget")
        let found = try await engine(sb).discoverApps()
        let app = try XCTUnwrap(found.first)
        do { _ = try await uninstaller(sb, running: true).uninstall(app: app, includeRemnants: []); XCTFail() }
        catch { XCTAssertEqual(error as? UninstallError, .appIsRunning("Widget")) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.bundleURL.path))

        let me = InstalledApp(bundleURL: app.bundleURL, bundleIdentifier: SafetyValidator.ownBundleIdentifier, displayName: "Macuum Cleaner",
                              version: "1", vendorName: "", bundleSize: 1, lastUsedDate: nil, isSystemApp: false)
        do { _ = try await uninstaller(sb).uninstall(app: me, includeRemnants: []); XCTFail() }
        catch { XCTAssertEqual(error as? UninstallError, .cannotUninstallSelf) }

        let sys = InstalledApp(bundleURL: URL(fileURLWithPath: "/System/Applications/Notes.app"), bundleIdentifier: "com.apple.Notes",
                               displayName: "Notes", version: "1", vendorName: "Apple", bundleSize: 1, lastUsedDate: nil, isSystemApp: true)
        do { _ = try await uninstaller(sb).uninstall(app: sys, includeRemnants: []); XCTFail() }
        catch { XCTAssertEqual(error as? UninstallError, .systemApp("Notes")) }
    }

    func testMissingRemnantIsSkippedSilently() async throws {
        let sb = try SandboxHolder.make()
        _ = try makeApp(sb, name: "Widget", id: "com.acme.widget")
        let found = try await engine(sb).discoverApps()
        let app = try XCTUnwrap(found.first)
        let ghost = AppRemnant(url: sb.root.appendingPathComponent("Library/Caches/com.acme.widget"), kind: .caches, size: 999)
        let r = try await uninstaller(sb).uninstall(app: app, includeRemnants: [ghost])
        XCTAssertEqual(r.removedItems.count, 1)
        XCTAssertEqual(r.totalBytesRecovered, app.bundleSize, "ghost remnant size must not be counted")
        XCTAssertTrue(r.errors.isEmpty)
    }

    func testBatchRunsSequentiallyAndReportsPerApp() async throws {
        let sb = try SandboxHolder.make()
        _ = try makeApp(sb, name: "A", id: "com.acme.a"); _ = try makeApp(sb, name: "B", id: "com.acme.b")
        let apps = try await engine(sb).discoverApps()
        let results = await uninstaller(sb).uninstall(batch: apps.map { ($0, []) })
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { if case .success = $0 { true } else { false } })
    }
}
