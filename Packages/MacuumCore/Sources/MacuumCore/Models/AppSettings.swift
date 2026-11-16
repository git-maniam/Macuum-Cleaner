import Foundation

public enum AppSortOrder: String, Codable, Sendable {
    case nameAscending, nameDescending, sizeDescending, lastUsed, recentlyInstalled
}

public struct AppSettings: Codable, Equatable, Sendable {
    // Cleaner
    public var enabledCategories: Set<JunkCategory> = JunkCategory.defaultEnabled
    public var showHiddenFiles = false
    public var scanSystemPaths = false
    public var permanentDeleteEnabled = false
    public var scheduledScanEnabled = false
    public var scheduledScanDayOfWeek = 1   // 1 = Monday (launchd Weekday)
    public var scheduledScanHour = 9
    public var excludedPaths: [String] = []
    public var oldScreenshotThresholdDays = 30
    public var oldDownloadThresholdDays = 30
    public var iOSBackupWarningAcknowledged = false
    public var includeApplePreferences = false
    public var duplicateScanFolders: [String] = ["~/Downloads", "~/Documents", "~/Desktop"]

    // App Manager
    public var appManagerShowSystemApps = true
    public var appManagerDefaultSort: AppSortOrder = .nameAscending
    public var unusedAppThresholdDays = 90
    public var appManagerScanLaunchDaemons = false

    public init() {}
}

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "MacuumCleaner.AppSettings.v1"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public func save(_ settings: AppSettings) {
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
