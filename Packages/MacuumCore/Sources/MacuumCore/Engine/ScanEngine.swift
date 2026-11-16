import Foundation

public enum ScannerRegistry {
    /// Builds every available scanner for a context. Scanners are appended here as they are implemented.
    public static func allScanners(context: ScanContext) -> [any ScannerProtocol] {
        // Remnant and prefs scanners share one installed-app index; it is built lazily by whichever runs first.
        let index = LazyAppIndex(applicationDirs: context.applicationDirs)
        return [
            CacheScanner(kind: .systemCaches, context: context),
            CacheScanner(kind: .appCaches, context: context),
            LogScanner(context: context),
            TempFileScanner(context: context),
            TrashScanner(context: context),
            BrowserScanner(context: context),
            AppRemnantScanner(context: context, index: index),
            DeveloperJunkScanner(context: context),
            iOSBackupScanner(context: context),
            BrokenPrefsScanner(context: context, index: index),
            DownloadJunkScanner(context: context),
            DuplicateFileScanner(context: context),
            DSStoreScanner(context: context),
            FontCacheScanner(context: context),
            QuickLookScanner(context: context),
            MailScanner(context: context),
            DeveloperJunkScanner(context: context, category: .packageManagers),
            NotificationScanner(context: context),
            SpotlightExternalScanner(context: context),
            ICloudConflictScanner(context: context),
            ScreenshotScanner(context: context),
            VMDockerScanner(context: context),
            TimeMachineScanner(context: context),
        ]
    }

}

public actor ScanEngine {
    private let baseContext: ScanContext
    private let scannerFactory: @Sendable (ScanContext) -> [any ScannerProtocol]

    /// Claim order for de-duplication: specific categories win over the broad cache/log/temp sweeps.
    static let priority: [JunkCategory] = [
        .browserData, .developerJunk, .packageManagers, .quickLookCaches, .fontCaches, .iOSBackups, .mailJunk,
        .vmDockerLeftovers, .notificationHistory, .appRemnants, .brokenPrefs, .trash, .timeMachineSnapshots,
        .spotlightExternal, .iCloudConflicts, .screenshots, .downloadJunk, .duplicates, .languageFiles, .dsStore,
        .tempFiles, .logs, .appCaches, .systemCaches
    ]

    public init(context: ScanContext,
                scannerFactory: @escaping @Sendable (ScanContext) -> [any ScannerProtocol] = { ScannerRegistry.allScanners(context: $0) }) {
        self.baseContext = context
        self.scannerFactory = scannerFactory
    }

    public func runAllScans(categories: [JunkCategory],
                            progressHandler: @escaping @Sendable (ScanProgress) -> Void) async throws -> ScanResult {
        let start = Date()
        var context = baseContext
        context.reporter = ScanReporter(progressHandler)
        let requested = Set(categories)
        let scanners = scannerFactory(context).filter { requested.contains($0.categoryID) }

        var skipped: [JunkCategory: String] = [:]
        var runnable: [any ScannerProtocol] = []
        for s in scanners {
            if s.requiresFullDiskAccess && !context.hasFullDiskAccess {
                let reason = "Requires Full Disk Access"
                skipped[s.categoryID] = reason
                progressHandler(ScanProgress(category: s.categoryID, phase: .skipped(reason: reason)))
            } else { runnable.append(s) }
        }

        var raw: [JunkCategory: [JunkFile]] = [:]
        await withTaskGroup(of: (JunkCategory, [JunkFile]?, String?).self) { group in
            for s in runnable {
                group.addTask {
                    progressHandler(ScanProgress(category: s.categoryID, phase: .started))
                    do {
                        let files = try await s.scan()
                        progressHandler(ScanProgress(category: s.categoryID, phase: .finished, filesFound: files.count))
                        return (s.categoryID, files, nil)
                    } catch is CancellationError {
                        return (s.categoryID, nil, nil)
                    } catch {
                        progressHandler(ScanProgress(category: s.categoryID, phase: .failed(message: error.localizedDescription)))
                        return (s.categoryID, nil, error.localizedDescription)
                    }
                }
            }
            for await (cat, files, error) in group {
                if let files { raw[cat] = files }
                if let error { skipped[cat] = error }
            }
        }

        let cancelled = Task.isCancelled
        return ScanResult(startDate: start, endDate: Date(), filesByCategory: Self.dedupe(raw),
                          skipped: skipped, wasCancelled: cancelled)
    }

    /// Drops files already claimed by a higher-priority category, or nested inside/around a claimed path.
    static func dedupe(_ raw: [JunkCategory: [JunkFile]]) -> [JunkCategory: [JunkFile]] {
        var claimed: [String] = []   // kept sorted for descendant lookups
        var claimedSet = Set<String>()
        var out: [JunkCategory: [JunkFile]] = [:]
        let order = priority + raw.keys.filter { !priority.contains($0) }

        func conflicts(_ path: String) -> Bool {
            if claimedSet.contains(path) { return true }
            var p = path
            while let slash = p.lastIndex(of: "/"), slash != p.startIndex {
                p = String(p[..<slash])
                if claimedSet.contains(p) { return true }       // an ancestor is already claimed
            }
            let prefix = path + "/"                              // a descendant is already claimed
            var lo = 0, hi = claimed.count
            while lo < hi { let mid = (lo + hi) / 2; if claimed[mid] < prefix { lo = mid + 1 } else { hi = mid } }
            return lo < claimed.count && claimed[lo].hasPrefix(prefix)
        }

        for cat in order {
            guard let files = raw[cat] else { continue }
            var kept: [JunkFile] = []
            var newClaims: [String] = []
            for f in files {
                guard f.isFileSystemItem else { kept.append(f); continue }
                let path = f.url.standardizedFileURL.path
                if conflicts(path) { continue }
                kept.append(f); newClaims.append(path)
            }
            for p in newClaims { claimedSet.insert(p) }
            claimed.append(contentsOf: newClaims); claimed.sort()
            out[cat] = kept
        }
        return out
    }
}
