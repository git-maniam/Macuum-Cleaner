import AppKit
import MacuumCore

/// Headless run launched by the LaunchAgent (`--scheduled-scan`): scan, notify, quit. Never cleans.
enum ScheduledScan {
    static var isRequested: Bool { CommandLine.arguments.contains(ScheduleManager.launchArgument) }

    @MainActor static func run() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.orderOut(nil) }
        Task {
            let settings = SettingsStore().load()
            let categories = JunkCategory.allCases.filter { settings.enabledCategories.contains($0) }
            let engine = ScanEngine(context: ScanContext.live(settings: settings))
            if let result = try? await engine.runAllScans(categories: categories, progressHandler: { _ in }) {
                await ScanHistory().append(HistoryEntry(kind: .scan, itemCount: result.totalFileCount, bytes: result.totalSize))
                if result.totalSize > 0 {
                    Notifier.post("Macuum found \(ByteFormatter.string(from: result.totalSize)) of junk files. Tap to review.")
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // let the notification post before exiting
            NSApp.terminate(nil)
        }
    }
}
