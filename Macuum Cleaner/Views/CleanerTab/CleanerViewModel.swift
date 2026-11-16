import SwiftUI
import MacuumCore

struct CleanSummary: Identifiable {
    let id = UUID()
    let removedCount: Int
    let bytes: Int64
    let failures: [String]
    let diskFull: Bool
    let permanent: Bool
    let postNotes: [String]
}

/// Throttles high-frequency scanner progress so the UI isn't flooded with updates.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    func shouldPass() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if now.timeIntervalSince(last) > 0.1 { last = now; return true }
        return false
    }
}

@MainActor @Observable
final class CleanerViewModel {
    private(set) var settings: AppSettings
    var result: ScanResult?
    var selectedCategory: JunkCategory?
    var isScanning = false
    var liveCounts: [JunkCategory: Int] = [:]
    var pendingCategories: Set<JunkCategory> = []
    var statusLine = ""
    var lastScanDate: Date?
    var showConfirm = false
    var showFDASheet = false
    var isCleaning = false
    var cleanFraction = 0.0
    var cleanSummary: CleanSummary?

    private let store: SettingsStore
    private let history: ScanHistory
    private var scanTask: Task<Void, Never>?
    private static let fdaPromptKey = "MacuumCleaner.fdaPromptShown"

    init(store: SettingsStore = SettingsStore(), history: ScanHistory = ScanHistory()) {
        self.store = store
        self.history = history
        self.settings = store.load()
        Task { self.lastScanDate = await history.lastScanDate }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        store.save(settings)
    }
    func reloadSettings() { settings = store.load() }

    func isEnabled(_ c: JunkCategory) -> Bool { settings.enabledCategories.contains(c) }
    func setEnabled(_ c: JunkCategory, _ on: Bool) {
        updateSettings { if on { $0.enabledCategories.insert(c) } else { $0.enabledCategories.remove(c) } }
    }

    // MARK: Scanning

    var hasFullDiskAccess: Bool { FullDiskAccess.isGranted() }

    var skippedForFullDiskAccess: Bool {
        guard let r = result else { return false }
        return r.skipped.values.contains("Requires Full Disk Access")
    }

    func startScan() {
        guard !isScanning else { return }
        if !hasFullDiskAccess && !UserDefaults.standard.bool(forKey: Self.fdaPromptKey) {
            showFDASheet = true
            return
        }
        beginScan()
    }

    func fdaSheetDismissed() {
        UserDefaults.standard.set(true, forKey: Self.fdaPromptKey)
        showFDASheet = false
        beginScan()
    }

    private func beginScan() {
        let categories = JunkCategory.allCases.filter(isEnabled)
        guard !categories.isEmpty else { statusLine = "Select at least one category to scan."; return }
        isScanning = true
        result = nil
        liveCounts = [:]
        pendingCategories = Set(categories)
        statusLine = "Starting scan…"
        let context = ScanContext.live(settings: settings)
        let throttle = ProgressThrottle()

        scanTask = Task { [weak self] in
            let engine = ScanEngine(context: context)
            let scan = try? await engine.runAllScans(categories: categories) { progress in
                let isFinal: Bool
                switch progress.phase { case .scanning: isFinal = false; default: isFinal = true }
                guard isFinal || throttle.shouldPass() else { return }
                Task { @MainActor in self?.apply(progress) }
            }
            await self?.finishScan(scan)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        statusLine = "Cancelling…"
    }

    private func apply(_ p: ScanProgress) {
        guard isScanning else { return }
        switch p.phase {
        case .started:
            statusLine = "Scanning \(p.category.displayName)…"
        case .scanning:
            liveCounts[p.category] = p.filesFound
            statusLine = "\(p.category.displayName): \(p.currentPath ?? "")"
        case .finished:
            liveCounts[p.category] = p.filesFound
            pendingCategories.remove(p.category)
        case .skipped, .failed:
            pendingCategories.remove(p.category)
        }
    }

    private func finishScan(_ scan: ScanResult?) async {
        isScanning = false
        pendingCategories = []
        statusLine = ""
        guard let scan else { return }
        result = scan
        lastScanDate = scan.endDate
        selectedCategory = JunkCategory.allCases.first { !(scan.filesByCategory[$0] ?? []).isEmpty }
        await history.append(HistoryEntry(kind: .scan, itemCount: scan.totalFileCount, bytes: scan.totalSize))
    }

    // MARK: Results & selection

    func files(in c: JunkCategory) -> [JunkFile] { result?.filesByCategory[c] ?? [] }

    func setSelected(_ on: Bool, fileID: UUID, in c: JunkCategory) {
        guard let i = result?.filesByCategory[c]?.firstIndex(where: { $0.id == fileID }),
              result?.filesByCategory[c]?[i].isAdvisoryOnly == false else { return }
        result?.filesByCategory[c]?[i].isSelected = on
    }

    func setAll(_ on: Bool, in c: JunkCategory) {
        guard var list = result?.filesByCategory[c] else { return }
        for i in list.indices where !list[i].isAdvisoryOnly { list[i].isSelected = on }
        result?.filesByCategory[c] = list
    }

    var selectedFiles: [JunkFile] { result?.filesByCategory.values.joined().filter(\.isSelected) ?? [] }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    var selectedByCategory: [(JunkCategory, Int, Int64)] {
        JunkCategory.allCases.compactMap { c in
            let sel = files(in: c).filter(\.isSelected)
            return sel.isEmpty ? nil : (c, sel.count, sel.reduce(0) { $0 + $1.size })
        }
    }

    // MARK: Cleaning

    func requestClean() { if !selectedFiles.isEmpty { showConfirm = true } }

    func clean(method: CleanMethod) {
        guard let scan = result, !isCleaning else { return }
        let files = selectedFiles
        showConfirm = false
        isCleaning = true
        cleanFraction = 0
        let engine = CleanEngine(validator: SafetyValidator(exclusions: settings.excludedPaths), history: history,
                                 permanentDeleteAllowed: settings.permanentDeleteEnabled)
        let categories = Set(files.map(\.category))
        Task {
            await engine.authorize(scan)
            let outcome = try? await engine.clean(files: files, method: method) { p in
                Task { @MainActor in self.cleanFraction = p.total == 0 ? 1 : Double(p.completed) / Double(p.total) }
            }
            isCleaning = false
            guard let outcome else { return }
            let removed = Set(outcome.removed.map(\.id))
            for c in JunkCategory.allCases {
                result?.filesByCategory[c]?.removeAll { removed.contains($0.id) }
            }
            cleanSummary = CleanSummary(
                removedCount: outcome.removed.count, bytes: outcome.bytesRecovered,
                failures: outcome.failed.map { "\($0.file.url.lastPathComponent): \($0.message)" },
                diskFull: outcome.diskFullEncountered, permanent: method == .permanentDelete,
                postNotes: categories.compactMap(\.warning).filter { $0.contains("rebuild") || $0.contains("relaunch") })
        }
    }
}
