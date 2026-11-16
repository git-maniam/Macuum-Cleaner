import Foundation
import CoreServices

public actor AppDiscoveryEngine {
    private let home: URL
    private let userAppDirs: [URL]
    private let systemAppDirs: [URL]
    private let settings: AppSettings
    private let systemLibrary: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                userAppDirs: [URL]? = nil,
                systemAppDirs: [URL] = [URL(fileURLWithPath: "/System/Applications")],
                systemLibrary: URL = URL(fileURLWithPath: "/Library"),
                settings: AppSettings = AppSettings()) {
        self.home = home
        self.userAppDirs = userAppDirs ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        self.systemAppDirs = systemAppDirs
        self.systemLibrary = systemLibrary
        self.settings = settings
    }

    /// Discovers every app and its leftovers concurrently (one task per app).
    public func discoverApps() async throws -> [InstalledApp] {
        var bundles: [(URL, Bool)] = []
        for d in userAppDirs { bundles += InstalledAppIndex.appBundles(in: d, maxDepth: 3).map { ($0, false) } }
        if settings.appManagerShowSystemApps {
            for d in systemAppDirs { bundles += InstalledAppIndex.appBundles(in: d, maxDepth: 2).map { ($0, true) } }
        }
        var seen = Set<String>()
        bundles = bundles.filter { seen.insert($0.0.standardizedFileURL.path).inserted }

        let engine = self
        return try await withThrowingTaskGroup(of: InstalledApp?.self) { group in
            for (url, isSystem) in bundles {
                group.addTask {
                    try Task.checkCancellation()
                    guard var app = try Self.readApp(at: url, isSystem: isSystem) else { return nil }
                    if !isSystem { app.remnants = (try? await engine.findRemnants(for: app)) ?? [] }
                    return app
                }
            }
            var apps: [InstalledApp] = []
            for try await a in group { if let a { apps.append(a) } }
            return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    static func readApp(at url: URL, isSystem: Bool) throws -> InstalledApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? ""
        let vendor = vendorName(info: info, bundleID: id)
        var lastUsed: Date?, added: Date?
        if let item = MDItemCreateWithURL(nil, url as CFURL) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        }
        return InstalledApp(bundleURL: url, bundleIdentifier: id, displayName: name, version: version, vendorName: vendor,
                            bundleSize: try DirectoryWalker.size(of: url), lastUsedDate: lastUsed, dateAdded: added,
                            isSystemApp: isSystem || url.path.hasPrefix("/System/"))
    }

    static func vendorName(info: [String: Any], bundleID: String) -> String {
        if let copyright = info["NSHumanReadableCopyright"] as? String,
           let r = copyright.range(of: #"(?i)(?:©|\(c\)|copyright)\s*(?:\d{4}(?:\s*[-–,]\s*\d{4})*)?\s*([^.\n,]+)"#, options: .regularExpression) {
            let cleaned = copyright[r].replacingOccurrences(of: #"(?i)(©|\(c\)|copyright|\d{4}|[-–])"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty, cleaned.count < 60 { return cleaned }
        }
        let parts = bundleID.split(separator: ".")
        return parts.count >= 2 ? parts[1].capitalized : ""
    }

    /// Leftovers outside the bundle. Matches are exact on bundle ID; name-based matches are not pre-selected.
    public func findRemnants(for app: InstalledApp) async throws -> [AppRemnant] {
        let id = app.bundleIdentifier
        let name = app.bundleURL.deletingPathExtension().lastPathComponent
        let lib = home.appendingPathComponent("Library")
        let fm = FileManager.default
        var found: [(URL, RemnantKind, Bool)] = []   // url, kind, preselected

        func add(_ rel: String, _ kind: RemnantKind, base: URL? = nil, selected: Bool = true) {
            let u = (base ?? lib).appendingPathComponent(rel)
            if fm.fileExists(atPath: u.path) || (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                found.append((u, kind, selected))
            }
        }
        add("Application Support/\(id)", .applicationSupport)
        add("Application Support/\(name)", .applicationSupport, selected: false)
        add("Caches/\(id)", .caches)
        add("Preferences/\(id).plist", .preferences)
        for u in PathExpander.glob(lib.path + "/Preferences/ByHost/\(id).*.plist") { found.append((u, .preferences, true)) }
        add("Containers/\(id)", .containers)
        add("Application Scripts/\(id)", .applicationScripts)
        add("Saved Application State/\(id).savedState", .savedState)
        add("WebKit/\(id)", .webKit)
        add("Logs/\(id)", .logs)
        add("Logs/\(name)", .logs, selected: false)
        add("LaunchAgents/\(id).plist", .launchAgents)
        if settings.appManagerScanLaunchDaemons { add("LaunchDaemons/\(id).plist", .launchDaemons, base: systemLibrary) }

        for u in (try? fm.contentsOfDirectory(at: lib.appendingPathComponent("Group Containers"), includingPropertiesForKeys: nil)) ?? []
        where BundleIDParser.candidate(fromEntryName: u.lastPathComponent) == id { found.append((u, .groupContainers, true)) }

        let reports = lib.appendingPathComponent("Logs/DiagnosticReports")
        for u in (try? fm.contentsOfDirectory(at: reports, includingPropertiesForKeys: nil)) ?? []
        where u.lastPathComponent.hasPrefix(name + "_") || u.lastPathComponent.hasPrefix(name + "-") { found.append((u, .crashReports, true)) }

        var out: [AppRemnant] = []
        for (url, kind, selected) in found {
            try Task.checkCancellation()
            out.append(AppRemnant(url: url, kind: kind, size: try DirectoryWalker.size(of: url), isSelected: selected))
        }
        return out
    }
}
