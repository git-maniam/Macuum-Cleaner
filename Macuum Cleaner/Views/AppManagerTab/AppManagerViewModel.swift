import SwiftUI
import AppKit
import UserNotifications
import MacuumCore

enum AppFilter: String, CaseIterable, Identifiable {
    case all = "All", userInstalled = "User-installed", system = "System Apps (view only)"
    case large = "Large Apps (>500 MB)", unused = "Unused"
    var id: String { rawValue }
}

extension AppSortOrder {
    var title: String {
        switch self {
        case .nameAscending: "Name (A→Z)"
        case .nameDescending: "Name (Z→A)"
        case .sizeDescending: "Size (Largest first)"
        case .lastUsed: "Last Used"
        case .recentlyInstalled: "Recently Installed"
        }
    }
    static let menuOrder: [AppSortOrder] = [.nameAscending, .nameDescending, .sizeDescending, .lastUsed, .recentlyInstalled]
}

struct UninstallTarget: Identifiable {
    let app: InstalledApp
    let remnants: [AppRemnant]
    var id: UUID { app.id }
    var totalSize: Int64 { app.bundleSize + remnants.reduce(0) { $0 + $1.size } }
}

struct UninstallSummary: Identifiable {
    let id = UUID()
    let removedApps: [String]
    let bytes: Int64
    let permissionDenied: [String]
    let otherErrors: [String]
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(_ text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Macuum Cleaner"
            content.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

@MainActor @Observable
final class AppManagerViewModel {
    var apps: [InstalledApp] = []
    var isLoading = false
    var search = ""
    var sort: AppSortOrder
    var filter: AppFilter = .all
    var selectedID: UUID?
    var checkedIDs: Set<UUID> = []

    var pendingTargets: [UninstallTarget] = []
    var showConfirm = false
    var isUninstalling = false
    var progressText = ""
    var summary: UninstallSummary?
    var runningPrompt: InstalledApp?
    var toast: String?
    var alertMessage: String?

    private var quitDecision: CheckedContinuation<Bool, Never>?
    private let settingsStore: SettingsStore
    private let history: ScanHistory

    init(settingsStore: SettingsStore = SettingsStore(), history: ScanHistory = ScanHistory()) {
        self.settingsStore = settingsStore
        self.history = history
        self.sort = settingsStore.load().appManagerDefaultSort
    }

    private var settings: AppSettings { settingsStore.load() }

    // MARK: Loading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let engine = AppDiscoveryEngine(settings: settings)
        apps = (try? await engine.discoverApps()) ?? []
        checkedIDs.formIntersection(Set(apps.map(\.id)))
        if let sel = selectedID, !apps.contains(where: { $0.id == sel }) { selectedID = nil }
    }

    // MARK: Filtering / sorting

    var visibleApps: [InstalledApp] {
        let threshold = settings.unusedAppThresholdDays
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = apps.filter { app in
            if !q.isEmpty, !app.displayName.lowercased().contains(q), !app.bundleIdentifier.lowercased().contains(q) { return false }
            switch filter {
            case .all: return true
            case .userInstalled: return !app.isSystemApp
            case .system: return app.isSystemApp
            case .large: return app.totalSizeOnDisk > 500_000_000
            case .unused: return !app.isSystemApp && app.isUnused(thresholdDays: threshold)
            }
        }
        func by<T: Comparable>(_ key: @escaping (InstalledApp) -> T?, descending: Bool) -> (InstalledApp, InstalledApp) -> Bool {
            { a, b in
                switch (key(a), key(b)) {
                case let (x?, y?): return descending ? x > y : x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                }
            }
        }
        switch sort {
        case .nameAscending: return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameDescending: return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .sizeDescending: return filtered.sorted { $0.totalSizeOnDisk > $1.totalSizeOnDisk }
        case .lastUsed: return filtered.sorted(by: by({ $0.lastUsedDate }, descending: true))
        case .recentlyInstalled: return filtered.sorted(by: by({ $0.dateAdded }, descending: true))
        }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedID } }
    var totalSize: Int64 { apps.reduce(0) { $0 + $1.totalSizeOnDisk } }
    var checkedApps: [InstalledApp] { apps.filter { checkedIDs.contains($0.id) } }

    func canUninstall(_ app: InstalledApp) -> Bool {
        !app.isSystemApp && app.bundleIdentifier != SafetyValidator.ownBundleIdentifier
    }

    func setChecked(_ on: Bool, _ app: InstalledApp) {
        guard canUninstall(app) else { return }
        if on { checkedIDs.insert(app.id) } else { checkedIDs.remove(app.id) }
    }

    func setRemnant(_ on: Bool, remnantID: UUID, appID: UUID) {
        guard let a = apps.firstIndex(where: { $0.id == appID }),
              let r = apps[a].remnants.firstIndex(where: { $0.id == remnantID }) else { return }
        apps[a].remnants[r].isSelected = on
    }

    func selectedTotal(for app: InstalledApp) -> Int64 {
        app.bundleSize + app.remnants.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    func revealInFinder(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
    }

    // MARK: Uninstall flow

    func requestUninstall(_ app: InstalledApp, includeLeftovers: Bool) {
        guard guardSelf(app) else { return }
        pendingTargets = [UninstallTarget(app: app, remnants: includeLeftovers ? app.remnants.filter(\.isSelected) : [])]
        showConfirm = true
    }

    func requestBatchUninstall() {
        let targets = checkedApps.filter(canUninstall).map { UninstallTarget(app: $0, remnants: $0.remnants.filter(\.isSelected)) }
        guard !targets.isEmpty else { return }
        pendingTargets = targets
        showConfirm = true
    }

    private func guardSelf(_ app: InstalledApp) -> Bool {
        if app.bundleIdentifier == SafetyValidator.ownBundleIdentifier {
            alertMessage = "Macuum Cleaner cannot uninstall itself."
            return false
        }
        return true
    }

    func confirmUninstall() {
        let targets = pendingTargets
        showConfirm = false
        guard !targets.isEmpty, !isUninstalling else { return }
        isUninstalling = true
        let engine = UninstallEngine(validator: SafetyValidator(exclusions: settings.excludedPaths), history: history,
                                     notify: { Notifier.post($0) })
        Task {
            var removed: [String] = [], bytes: Int64 = 0
            var denied: [String] = [], other: [String] = []
            var notFound = false

            for (i, target) in targets.enumerated() {
                progressText = "Uninstalling \(target.app.displayName) (\(i + 1) of \(targets.count))…"
                var attempt = 0
                while attempt < 2 {
                    attempt += 1
                    do {
                        let r = try await engine.uninstall(app: target.app, includeRemnants: target.remnants) { p in
                            Task { @MainActor in self.progressText = "\(p.appName): \(p.currentStep) (\(p.stepIndex)/\(p.totalSteps))" }
                        }
                        if !r.removedItems.isEmpty { removed.append(target.app.displayName) }
                        bytes += r.totalBytesRecovered
                        for f in r.errors {
                            if f.isPermissionDenied { denied.append(f.url.path) } else { other.append("\(f.url.lastPathComponent): \(f.message)") }
                        }
                        break
                    } catch UninstallError.appIsRunning {
                        runningPrompt = target.app
                        let quit = await withCheckedContinuation { quitDecision = $0 }
                        runningPrompt = nil
                        if quit, await engine.quit(app: target.app) { continue }
                        other.append("\(target.app.displayName): still running, skipped")
                        break
                    } catch UninstallError.appNotFound {
                        notFound = true; break
                    } catch {
                        other.append("\(target.app.displayName): \(error.localizedDescription)"); break
                    }
                }
            }
            isUninstalling = false
            progressText = ""
            checkedIDs.removeAll()
            pendingTargets = []
            await load()
            if notFound { showToast("App no longer found") }
            if !removed.isEmpty || !denied.isEmpty || !other.isEmpty {
                summary = UninstallSummary(removedApps: removed, bytes: bytes, permissionDenied: denied, otherErrors: other)
            }
        }
    }

    func answerQuitPrompt(_ quit: Bool) {
        quitDecision?.resume(returning: quit)
        quitDecision = nil
    }

    func showToast(_ text: String) {
        toast = text
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if toast == text { toast = nil } }
    }
}
