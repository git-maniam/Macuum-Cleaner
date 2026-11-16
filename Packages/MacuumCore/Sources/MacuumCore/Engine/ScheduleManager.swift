import Foundation

/// Weekly scheduled scan, implemented as a per-user LaunchAgent that launches the app with `--scheduled-scan`.
/// The agent only exists while the user has scheduling enabled; it never cleans anything.
public enum ScheduleManager {
    public static let label = "com.macuum.cleaner.scheduled-scan"
    public static let launchArgument = "--scheduled-scan"

    public static func plistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// launchd weekday: 0/7 = Sunday, 1 = Monday … 6 = Saturday (matches `AppSettings.scheduledScanDayOfWeek`).
    public static func plist(settings: AppSettings, executable: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable, launchArgument],
            "StartCalendarInterval": ["Weekday": settings.scheduledScanDayOfWeek, "Hour": settings.scheduledScanHour, "Minute": 0],
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
    }

    /// Installs or removes the agent to match `settings`. `launchctl` is skipped when `load` is false (tests).
    public static func apply(_ settings: AppSettings,
                             executable: String? = Bundle.main.executableURL?.path,
                             home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             load: Bool = true) async throws {
        let url = plistURL(home: home)
        let domain = "gui/\(getuid())"
        if load { _ = try? await ShellRunner.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 15) }

        guard settings.scheduledScanEnabled, let executable else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist(settings: settings, executable: executable),
                                                      format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        if load { _ = try await ShellRunner.run("/bin/launchctl", ["bootstrap", domain, url.path], timeout: 15) }
    }
}
