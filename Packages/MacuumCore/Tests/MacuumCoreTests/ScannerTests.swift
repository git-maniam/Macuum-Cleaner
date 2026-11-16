import XCTest
@testable import MacuumCore

final class ScannerTests: XCTestCase {
    let old = Date(timeIntervalSinceNow: -40 * 86_400)

    func age(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testAppCacheScannerSkipsRunningAndLaunchServices() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Library/Caches/com.dead.app/a.bin")
        _ = try sb.write("Library/Caches/com.running.app/a.bin")
        _ = try sb.write("Library/Caches/com.apple.LaunchServices-134501.csstore/a.bin")
        var ctx = sb.context(); ctx.runningBundleIDs = ["com.running.app"]
        let files = try await CacheScanner(kind: .appCaches, context: ctx).scan()
        XCTAssertEqual(files.map(\.url.lastPathComponent), ["com.dead.app"])
    }

    func testSystemCacheNeedsFDA() async throws {
        let sb = try SandboxHolder.make()
        do { _ = try await CacheScanner(kind: .systemCaches, context: sb.context(fda: false)).scan(); XCTFail() }
        catch { XCTAssertTrue(error is ScannerError) }
    }

    func testLogScannerAgeAndSizeRules() async throws {
        let sb = try SandboxHolder.make()
        let big = try sb.write("Library/Logs/App/big.log", bytes: 20_000); try age(big, old)
        let small = try sb.write("Library/Logs/App/small.log", bytes: 100); try age(small, old)
        _ = try sb.write("Library/Logs/App/fresh.log", bytes: 20_000)
        let crash = try sb.write("Library/Logs/DiagnosticReports/x.crash", bytes: 100); try age(crash, old)
        let names = Set(try await LogScanner(context: sb.context()).scan().map(\.url.lastPathComponent))
        XCTAssertEqual(names, ["big.log", "x.crash"])
    }

    func testTempScannerFindsPatternsInAppSupportAndDownloads() async throws {
        let sb = try SandboxHolder.make()
        let a = try sb.write("Library/Application Support/Foo/doc.tmp"); try age(a, old)
        let b = try sb.write("Library/Application Support/Foo/~$report.docx"); try age(b, old)
        _ = try sb.write("Library/Application Support/Foo/keep.db"); 
        let c = try sb.write("Downloads/movie.mp4.crdownload"); try age(c, old)
        _ = try sb.write("Library/Application Support/Foo/new.tmp")   // < 1h
        let names = Set(try await TempFileScanner(context: sb.context()).scan().map(\.url.lastPathComponent))
        XCTAssertEqual(names, ["doc.tmp", "~$report.docx", "movie.mp4.crdownload"])
    }

    func testDSStoreSkipsAppBundles() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Documents/.DS_Store", bytes: 10)
        _ = try sb.write("Applications/Foo.app/Contents/.DS_Store", bytes: 10)
        let files = try await DSStoreScanner(context: sb.context()).scan()
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].url.path.contains("Documents"))
    }

    func testBundleIDParser() {
        XCTAssertEqual(BundleIDParser.candidate(fromEntryName: "com.foo.bar"), "com.foo.bar")
        XCTAssertEqual(BundleIDParser.candidate(fromEntryName: "com.foo.bar.plist"), "com.foo.bar")
        XCTAssertEqual(BundleIDParser.candidate(fromEntryName: "com.foo.bar.savedState"), "com.foo.bar")
        XCTAssertEqual(BundleIDParser.candidate(fromEntryName: "group.com.foo.bar"), "com.foo.bar")
        XCTAssertEqual(BundleIDParser.candidate(fromEntryName: "ABCDE12345.com.foo.bar"), "com.foo.bar")
        XCTAssertNil(BundleIDParser.candidate(fromEntryName: "com.apple.Safari"))
        XCTAssertNil(BundleIDParser.candidate(fromEntryName: "Google"))
        XCTAssertNil(BundleIDParser.candidate(fromEntryName: "Firefox"))
    }

    func testRemnantScannerUsesExactMatchOnly() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Library/Application Support/com.gone.app/data")
        _ = try sb.write("Library/Application Support/com.installed.app/data")
        _ = try sb.write("Library/Application Support/com.installed.app.helper/data")   // different ID: flagged
        _ = try sb.write("Library/Application Support/Google/data")                       // not a bundle ID
        _ = try sb.write("Library/Preferences/com.gone.app.plist")                       // belongs to prefs scanner
        let idx = LazyAppIndex(InstalledAppIndex(bundleIDs: ["com.installed.app"]))
        let names = Set(try await AppRemnantScanner(context: sb.context(), index: idx).scan().map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["com.gone.app", "com.installed.app.helper"])
    }

    func testBrokenPrefsRules() async throws {
        let sb = try SandboxHolder.make()
        let gone = try sb.write("Library/Preferences/com.gone.app.plist"); try age(gone, old)
        let recent = try sb.write("Library/Preferences/com.recent.app.plist")
        let apple = try sb.write("Library/Preferences/com.apple.macuumfake.plist"); try age(apple, old)
        let installed = try sb.write("Library/Preferences/com.installed.app.plist"); try age(installed, old)
        _ = (recent, apple)
        let idx = LazyAppIndex(InstalledAppIndex(bundleIDs: ["com.installed.app"]))
        let names = try await BrokenPrefsScanner(context: sb.context(), index: idx).scan().map { $0.url.lastPathComponent }
        XCTAssertEqual(names, ["com.gone.app.plist"])
        var ctx = sb.context(); ctx.settings.includeApplePreferences = true
        let withApple = Set(try await BrokenPrefsScanner(context: ctx, index: idx).scan().map { $0.url.lastPathComponent })
        XCTAssertTrue(withApple.contains("com.apple.macuumfake.plist"))
    }

    func testDownloadJunkRulesAndNoDefaultSelection() async throws {
        let sb = try SandboxHolder.make()
        let dmg = try sb.write("Downloads/Old.dmg"); try age(dmg, old)
        _ = try sb.write("Downloads/New.dmg")
        let zip = try sb.write("Downloads/a.zip"); try age(zip, old)             // 40d < 90d: kept
        _ = try sb.write("Downloads/report (1).pdf")
        _ = try sb.write("Elsewhere/Old.dmg")
        let files = try await DownloadJunkScanner(context: sb.context()).scan()
        XCTAssertEqual(Set(files.map(\.url.lastPathComponent)), ["Old.dmg", "report (1).pdf"])
        XCTAssertTrue(files.allSatisfy { !$0.isSelected })
    }

    func testScreenshotScanner() async throws {
        let sb = try SandboxHolder.make()
        let s1 = try sb.write("Desktop/Screenshot 2024-01-01 at 10.00.00.png"); try age(s1, old)
        _ = try sb.write("Desktop/Screenshot 2099.png")
        let s3 = try sb.write("Desktop/Resume.png"); try age(s3, old)
        let files = try await ScreenshotScanner(context: sb.context()).scan()
        XCTAssertEqual(files.count, 1)
    }

    func testDuplicateScannerKeepsOldestAndNeverSelects() async throws {
        let sb = try SandboxHolder.make()
        let payload = Data(repeating: 7, count: 5_000)
        func put(_ rel: String, created: Date) throws {
            let u = sb.root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: u)
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: u.path)
        }
        try put("Documents/original.bin", created: Date(timeIntervalSinceNow: -1_000))
        try put("Downloads/copy.bin", created: Date(timeIntervalSinceNow: -10))
        try Data(repeating: 8, count: 5_000).write(to: sb.root.appendingPathComponent("Desktop-other.bin"))
        let files = try await DuplicateFileScanner(context: sb.context()).scan()
        XCTAssertEqual(files.map(\.url.lastPathComponent), ["copy.bin"])
        XCTAssertFalse(files[0].isSelected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sb.root.appendingPathComponent("Documents/original.bin").path))
    }

    func testICloudConflictsRequireOriginal() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Library/Mobile Documents/com~apple~CloudDocs/notes.txt")
        _ = try sb.write("Library/Mobile Documents/com~apple~CloudDocs/notes (1).txt")
        _ = try sb.write("Library/Mobile Documents/com~apple~CloudDocs/lonely (1).txt")
        _ = try sb.write("Library/Mobile Documents/com~apple~CloudDocs/a conflicted copy 2024.txt")
        let files = try await ICloudConflictScanner(context: sb.context()).scan()
        XCTAssertEqual(Set(files.map(\.url.lastPathComponent)), ["notes (1).txt", "a conflicted copy 2024.txt"])
        XCTAssertTrue(files.allSatisfy { !$0.isSelected })
    }

    func testIOSBackupReadsInfoPlistAndIsNeverSelected() async throws {
        let sb = try SandboxHolder.make()
        let dir = sb.root.appendingPathComponent("Library/Application Support/MobileSync/Backup/ABC123")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["Device Name": "Ravi's iPhone", "Product Version": "17.4", "Last Backup Date": Date()]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
        let files = try await iOSBackupScanner(context: sb.context()).scan()
        XCTAssertEqual(files.first?.displayName, "Ravi's iPhone")
        XCTAssertEqual(files.first?.metadata["iOSVersion"], "17.4")
        XCTAssertEqual(files.first?.isSelected, false)
    }

    func testMailEnvelopeIndexIsAdvisoryAndUncleanable() async throws {
        let sb = try SandboxHolder.make()
        let idx = try sb.write("Library/Mail/V10/MailData/Envelope Index", bytes: 100)
        let files = try await MailScanner(context: sb.context()).scan()
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isAdvisoryOnly)
        let engine = CleanEngine(validator: sb.validator, permanentDeleteAllowed: true)
        await engine.authorize(ScanResult(startDate: Date(), endDate: Date(), filesByCategory: [.mailJunk: files]))
        let r = try await engine.clean(files: files, method: .permanentDelete)
        XCTAssertEqual(r.removed.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: idx.path))
    }

    func testBrowserScannerSelectsOnlyCaches() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Library/Caches/Google/Chrome/Default/Cache/x")
        _ = try sb.write("Library/Application Support/Google/Chrome/Default/History")
        _ = try sb.write("Library/Application Support/Firefox/Profiles/abc.default/places.sqlite")
        let files = try await BrowserScanner(context: sb.context()).scan()
        XCTAssertEqual(files.count, 3)
        for f in files { XCTAssertEqual(f.isSelected, f.metadata["kind"] == "Cache", f.displayName) }
    }

    func testDeveloperScannerWarnsOnArchives() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Library/Developer/Xcode/DerivedData/Proj/x")
        _ = try sb.write("Library/Developer/Xcode/Archives/2024/y")
        let files = try await DeveloperJunkScanner(context: sb.context()).scan()
        XCTAssertEqual(files.first { $0.displayName == "Xcode Derived Data" }?.isSelected, true)
        XCTAssertEqual(files.first { $0.displayName == "Xcode Archives" }?.isSelected, false)
    }

    func testTimeMachineParseAndOnlyOldSnapshots() async throws {
        let sb = try SandboxHolder.make()
        let oldStamp = "2020-01-01-120000"
        let newStamp: String = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: Date()) }()
        let out = "Snapshots for disk /:\ncom.apple.TimeMachine.\(oldStamp).local\ncom.apple.TimeMachine.\(newStamp).local\n"
        let scanner = TimeMachineScanner(context: sb.context()) { _, _ in ShellResult(status: 0, stdout: out, stderr: "", timedOut: false) }
        let files = try await scanner.scan()
        XCTAssertEqual(files.map { $0.metadata["snapshotDate"] }, [oldStamp])
        XCTAssertFalse(files[0].isFileSystemItem)
    }

    func testFullScanThroughRegistryOnSandbox() async throws {
        let sb = try SandboxHolder.make()
        _ = try sb.write("Library/Caches/com.dead.app/a.bin", bytes: 5_000)
        _ = try sb.write("Documents/.DS_Store", bytes: 10)
        var ctx = sb.context(); ctx.settings.excludedPaths = []
        let engine = ScanEngine(context: ctx)
        let result = try await engine.runAllScans(categories: [.appCaches, .dsStore, .appRemnants]) { _ in }
        XCTAssertEqual(result.filesByCategory[.appRemnants]?.count, 1, "specific category claims the path first")
        XCTAssertEqual(result.filesByCategory[.appCaches]?.count ?? 0, 0)
        XCTAssertEqual(result.filesByCategory[.dsStore]?.count, 1)
    }
}
