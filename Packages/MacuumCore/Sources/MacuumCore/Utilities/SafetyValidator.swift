import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum SafetyVerdict: Equatable, Sendable {
    case allowed
    case blocked(reason: String)
    public var isAllowed: Bool { self == .allowed }
}

/// Defensive layer consulted before anything is removed. Blocks are logged, never shown to the user as errors.
public struct SafetyValidator: Sendable {
    public static let ownBundleIdentifier = "com.macuum.cleaner"
    public static let ownName = "Macuum Cleaner"

    private let home: String
    private let exclusions: [String]
    private let ownBundlePath: String?
    private let runningAppPaths: @Sendable () -> Set<String>
    private let protectedExact: Set<String>

    static let blockedPrefixes = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/dev", "/cores", "/Library/Apple"]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                exclusions: [String] = [],
                ownBundleURL: URL? = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil,
                runningAppPaths: @escaping @Sendable () -> Set<String> = SafetyValidator.liveRunningAppPaths) {
        let h = Self.normalize(home.resolvingSymlinksInPath().path)
        self.home = h
        self.exclusions = exclusions.map { Self.normalize(URL(fileURLWithPath: PathExpander.expand($0, home: home)).resolvingSymlinksInPath().path) }
        self.ownBundlePath = ownBundleURL.map { Self.normalize($0.resolvingSymlinksInPath().path) }
        self.runningAppPaths = runningAppPaths
        let lib = h + "/Library"
        self.protectedExact = Set([
            "/", "/Users", "/Applications", "/Library", "/private", "/private/var", "/private/tmp", "/var", "/tmp",
            "/Volumes", "/opt", h, h + "/Applications", h + "/.Trash",
            h + "/Desktop", h + "/Documents", h + "/Downloads", h + "/Movies", h + "/Music", h + "/Pictures", h + "/Public",
            lib, lib + "/Application Support", lib + "/Caches", lib + "/Preferences", lib + "/Containers",
            lib + "/Group Containers", lib + "/Logs", lib + "/Mobile Documents", lib + "/Mail", lib + "/Fonts",
            lib + "/Saved Application State", lib + "/WebKit", lib + "/LaunchAgents", lib + "/Developer",
            "/Library/Caches", "/Library/Logs", "/Library/Application Support", "/Library/Preferences",
        ])
    }

    public static let liveRunningAppPaths: @Sendable () -> Set<String> = {
        #if canImport(AppKit)
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map { normalize($0.path) } })
        #else
        []
        #endif
    }

    public func validate(_ url: URL) -> SafetyVerdict {
        guard url.isFileURL, url.path.hasPrefix("/") else { return .blocked(reason: "not an absolute file path") }
        let path = Self.canonical(url)

        if protectedExact.contains(path) { return .blocked(reason: "protected directory itself") }
        for prefix in Self.blockedPrefixes where Self.isSameOrDescendant(path, of: prefix) {
            return .blocked(reason: "system path \(prefix)")
        }
        if let own = ownBundlePath, Self.isSameOrDescendant(path, of: own) {
            return .blocked(reason: "Macuum Cleaner's own bundle")
        }
        if Self.touchesOwnSupportFiles(path) { return .blocked(reason: "Macuum Cleaner's own support files") }
        for ex in exclusions where Self.isSameOrDescendant(path, of: ex) {
            return .blocked(reason: "excluded by user")
        }
        for app in runningAppPaths() where Self.isSameOrDescendant(path, of: app) {
            return .blocked(reason: "running application")
        }
        return .allowed
    }

    public func isExcluded(_ url: URL) -> Bool {
        let p = Self.canonical(url)
        return exclusions.contains { Self.isSameOrDescendant(p, of: $0) }
    }

    /// True if any process has the file open (`lsof`). Expensive; use sparingly.
    public static func isOpenByProcess(_ url: URL) async -> Bool {
        guard let r = try? await ShellRunner.run("/usr/sbin/lsof", ["-t", "--", url.path], timeout: 5) else { return false }
        return r.status == 0 && !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Path helpers

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// Resolves symlinks in the parent directory (so `/tmp` → `/private/tmp`, and a symlinked parent can't
    /// smuggle a protected path in) but not the final component, since trashing a symlink moves only the link.
    static func canonical(_ url: URL) -> String {
        let std = url.standardizedFileURL
        let parent = std.deletingLastPathComponent().resolvingSymlinksInPath()
        return normalize(parent.appendingPathComponent(std.lastPathComponent).path)
    }

    static func isSameOrDescendant(_ path: String, of ancestor: String) -> Bool {
        let a = normalize(ancestor)
        if a == "/" { return true }
        return path == a || path.hasPrefix(a + "/")
    }

    private static func touchesOwnSupportFiles(_ path: String) -> Bool {
        for comp in path.split(separator: "/") {
            if comp == Substring(ownName) || comp.hasPrefix(ownBundleIdentifier) { return true }
        }
        return false
    }
}
