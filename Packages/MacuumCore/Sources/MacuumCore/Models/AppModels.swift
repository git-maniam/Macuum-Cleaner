import Foundation

public enum RemnantKind: String, CaseIterable, Sendable {
    case applicationSupport = "Application Support"
    case caches             = "Caches"
    case preferences        = "Preferences"
    case containers         = "Containers"
    case groupContainers    = "Group Containers"
    case logs               = "Logs"
    case savedState         = "Saved Application State"
    case webKit             = "WebKit Data"
    case applicationScripts = "Application Scripts"
    case launchAgents       = "Launch Agents"
    case launchDaemons      = "Launch Daemons"
    case crashReports       = "Crash Reports"
}

public struct AppRemnant: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: RemnantKind
    public let size: Int64
    public var isSelected: Bool

    public init(id: UUID = UUID(), url: URL, kind: RemnantKind, size: Int64, isSelected: Bool = true) {
        self.id = id; self.url = url; self.kind = kind; self.size = size; self.isSelected = isSelected
    }
}

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let bundleURL: URL
    public let bundleIdentifier: String
    public let displayName: String
    public let version: String
    public let vendorName: String
    public let bundleSize: Int64
    public var remnants: [AppRemnant]
    public let lastUsedDate: Date?
    public let dateAdded: Date?
    public let isSystemApp: Bool

    public init(id: UUID = UUID(), bundleURL: URL, bundleIdentifier: String, displayName: String,
                version: String, vendorName: String, bundleSize: Int64, remnants: [AppRemnant] = [],
                lastUsedDate: Date?, dateAdded: Date? = nil, isSystemApp: Bool) {
        self.id = id; self.bundleURL = bundleURL; self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName; self.version = version; self.vendorName = vendorName
        self.bundleSize = bundleSize; self.remnants = remnants; self.lastUsedDate = lastUsedDate
        self.dateAdded = dateAdded; self.isSystemApp = isSystemApp
    }

    public var totalSizeOnDisk: Int64 { bundleSize + remnants.reduce(0) { $0 + $1.size } }

    public func isUnused(thresholdDays: Int = 90, now: Date = Date()) -> Bool {
        guard let d = lastUsedDate else { return true }
        return now.timeIntervalSince(d) > Double(thresholdDays) * 86_400
    }
}
