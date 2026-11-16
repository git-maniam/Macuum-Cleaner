import Foundation
import AppKit

/// Thread-safe sink scanners use to publish live counts/paths while they work.
public final class ScanReporter: @unchecked Sendable {
    private let handler: @Sendable (ScanProgress) -> Void
    public init(_ handler: @escaping @Sendable (ScanProgress) -> Void = { _ in }) { self.handler = handler }
    public func report(_ category: JunkCategory, found: Int, path: String? = nil) {
        handler(ScanProgress(category: category, phase: .scanning, filesFound: found, currentPath: path))
    }
    func emit(_ p: ScanProgress) { handler(p) }
}

/// Everything a scanner needs from its environment. Tests inject temp-dir roots; the app uses `live`.
public struct ScanContext: Sendable {
    public var home: URL
    public var systemLibrary: URL
    public var tempDirs: [URL]
    public var logDirs: [URL]
    public var volumesRoot: URL
    public var applicationDirs: [URL]
    public var settings: AppSettings
    public var hasFullDiskAccess: Bool
    public var validator: SafetyValidator
    public var now: Date
    public var reporter: ScanReporter
    public var runningBundleIDs: Set<String>
    /// User opt-in for system-level locations (/Library, /var/log, /tmp). Also needs Full Disk Access.
    public var scanSystemPaths: Bool
    public var canScanSystemPaths: Bool { hasFullDiskAccess && scanSystemPaths }

    public var library: URL { home.appendingPathComponent("Library") }

    public init(home: URL, systemLibrary: URL, tempDirs: [URL], logDirs: [URL], volumesRoot: URL,
                applicationDirs: [URL], settings: AppSettings = AppSettings(), hasFullDiskAccess: Bool,
                validator: SafetyValidator, now: Date = Date(), reporter: ScanReporter = ScanReporter(),
                runningBundleIDs: Set<String> = [], scanSystemPaths: Bool = true) {
        self.home = home; self.systemLibrary = systemLibrary; self.tempDirs = tempDirs; self.logDirs = logDirs
        self.volumesRoot = volumesRoot; self.applicationDirs = applicationDirs; self.settings = settings
        self.hasFullDiskAccess = hasFullDiskAccess; self.validator = validator; self.now = now; self.reporter = reporter
        self.runningBundleIDs = runningBundleIDs
        self.scanSystemPaths = scanSystemPaths
    }

    public static func live(settings: AppSettings = AppSettings()) -> ScanContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScanContext(
            home: home,
            systemLibrary: URL(fileURLWithPath: "/Library"),
            tempDirs: ["/private/tmp", "/private/var/tmp"].map { URL(fileURLWithPath: $0) },
            logDirs: [URL(fileURLWithPath: "/private/var/log")],
            volumesRoot: URL(fileURLWithPath: "/Volumes"),
            applicationDirs: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")],
            settings: settings,
            hasFullDiskAccess: FullDiskAccess.isGranted(),
            validator: SafetyValidator(exclusions: settings.excludedPaths),
            runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            scanSystemPaths: settings.scanSystemPaths)
    }
}

public protocol ScannerProtocol: Sendable {
    var categoryID: JunkCategory { get }
    var displayName: String { get }
    var description: String { get }
    var isEnabledByDefault: Bool { get }
    var requiresFullDiskAccess: Bool { get }
    func scan() async throws -> [JunkFile]
}

public extension ScannerProtocol {
    var displayName: String { categoryID.displayName }
    var description: String { categoryID.summary }
    var isEnabledByDefault: Bool { categoryID.isEnabledByDefault }
    var requiresFullDiskAccess: Bool { categoryID.requiresFullDiskAccess }
}

/// Shared helpers so individual scanners stay small.
public enum ScannerSupport {
    /// Builds a `JunkFile` for `url` (file or directory), computing its size. Returns nil if the item is excluded,
    /// blocked by the validator, or has vanished.
    public static func junkFile(url: URL, category: JunkCategory, context: ScanContext,
                                displayName: String? = nil, metadata: [String: String] = [:],
                                isSelected: Bool? = nil) throws -> JunkFile? {
        guard FileManager.default.fileExists(atPath: url.path) || (try? url.checkResourceIsReachable()) == true
                || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        else { return nil }
        guard context.validator.validate(url).isAllowed else { return nil }
        let size = try DirectoryWalker.size(of: url)
        return JunkFile(url: url, size: size, lastModified: DirectoryWalker.modificationDate(of: url),
                        category: category, isSelected: isSelected, displayName: displayName, metadata: metadata)
    }

    /// One `JunkFile` per direct child of `directory` (skips `.DS_Store`-style noise only when `skip` says so).
    public static func childFiles(of directory: URL, category: JunkCategory, context: ScanContext,
                                  minAge: TimeInterval = 0, skip: (URL) -> Bool = { _ in false }) throws -> [JunkFile] {
        var out: [JunkFile] = []
        for child in DirectoryWalker.children(of: directory) {
            try Task.checkCancellation()
            if skip(child) { continue }
            if context.validator.isExcluded(child) { continue }
            if minAge > 0, context.now.timeIntervalSince(DirectoryWalker.modificationDate(of: child)) < minAge { continue }
            if !context.settings.showHiddenFiles, child.lastPathComponent.hasPrefix("."),
               child.lastPathComponent != ".DS_Store" { continue }
            if let f = try junkFile(url: child, category: category, context: context) {
                out.append(f)
                context.reporter.report(category, found: out.count, path: child.path)
            }
        }
        return out
    }
}
