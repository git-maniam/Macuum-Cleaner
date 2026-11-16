import Foundation
import AppKit

/// Set of bundle identifiers known to be installed. Shared by remnant/orphan detection and the App Manager.
public struct InstalledAppIndex: Sendable {
    public let bundleIDs: Set<String>

    public init(bundleIDs: Set<String>) { self.bundleIDs = bundleIDs }

    /// Scans app folders (to depth 3, e.g. /Applications/Utilities/X.app) plus nested helper bundles.
    public static func build(applicationDirs: [URL], includeSystem: Bool = true) -> InstalledAppIndex {
        var dirs = applicationDirs
        if includeSystem { dirs += [URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Library/CoreServices")] }
        var ids = Set<String>()
        for dir in dirs {
            for app in appBundles(in: dir, maxDepth: 3) {
                ids.formUnion(bundleIDs(inAppAt: app))
            }
        }
        return InstalledAppIndex(bundleIDs: ids)
    }

    /// Installed per the index, or Launch Services knows an existing app with this ID.
    public func isInstalled(_ id: String) -> Bool {
        if bundleIDs.contains(id) { return true }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           FileManager.default.fileExists(atPath: url.path) { return true }
        return false
    }

    static func appBundles(in dir: URL, maxDepth: Int) -> [URL] {
        var found: [URL] = []
        func walk(_ d: URL, depth: Int) {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: d, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for u in items {
                if u.pathExtension == "app" { found.append(u) }
                else if depth < maxDepth, (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { walk(u, depth: depth + 1) }
            }
        }
        walk(dir, depth: 1)
        return found
    }

    static func bundleIDs(inAppAt app: URL) -> Set<String> {
        var ids = Set<String>()
        if let id = Bundle(url: app)?.bundleIdentifier { ids.insert(id) }
        let contents = app.appendingPathComponent("Contents")
        for sub in ["Library/LoginItems", "XPCServices", "Helpers", "PlugIns", "Library/LaunchServices"] {
            for u in (try? FileManager.default.contentsOfDirectory(at: contents.appendingPathComponent(sub), includingPropertiesForKeys: nil)) ?? [] {
                if let id = Bundle(url: u)?.bundleIdentifier { ids.insert(id) }
            }
        }
        return ids
    }
}

/// Derives a candidate bundle identifier from a Library entry name and decides whether it is safe to judge.
public enum BundleIDParser {
    /// "group.com.x.y" / "ABCDE12345.com.x.y" / "com.x.y.plist" / "com.x.y.savedState" → "com.x.y".
    public static func candidate(fromEntryName name: String) -> String? {
        var n = name
        for suffix in [".plist", ".savedState", ".binarycookies", ".LSSharedFileList.plist"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
        }
        if n.hasPrefix("group.") { n = String(n.dropFirst(6)) }
        else if let dot = n.firstIndex(of: "."), n[..<dot].count == 10,
                n[..<dot].allSatisfy({ $0.isUppercase || $0.isNumber }) { n = String(n[n.index(after: dot)...]) }
        return looksLikeBundleID(n) ? n : nil
    }

    /// Reverse-DNS shaped (≥3 components, valid chars). Never matches `com.apple.*`.
    public static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, !s.hasPrefix("com.apple.") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
    }
}

/// Builds the index on first use and shares it between scanners (building walks every app folder).
public final class LazyAppIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: InstalledAppIndex?
    private let make: @Sendable () -> InstalledAppIndex
    public init(applicationDirs: [URL]) { make = { InstalledAppIndex.build(applicationDirs: applicationDirs) } }
    public init(_ index: InstalledAppIndex) { cached = index; make = { index } }
    public var value: InstalledAppIndex {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let built = make(); cached = built; return built
    }
}
