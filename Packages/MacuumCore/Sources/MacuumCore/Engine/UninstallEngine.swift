import Foundation
import AppKit

public struct UninstallProgress: Sendable {
    public let appName: String
    public let currentStep: String
    public let stepIndex: Int
    public let totalSteps: Int
}

public struct UninstallFailure: Sendable {
    public let url: URL
    public let message: String
    public let isPermissionDenied: Bool
}

public struct UninstallResult: Sendable {
    public let app: InstalledApp
    public let removedItems: [URL]
    public let totalBytesRecovered: Int64
    public let errors: [UninstallFailure]
}

public enum UninstallError: Error, LocalizedError, Equatable {
    case appIsRunning(String)
    case cannotUninstallSelf
    case systemApp(String)
    case appNotFound(String)
    case blocked(String)

    public var errorDescription: String? {
        switch self {
        case .appIsRunning(let n): "Quit \(n) before uninstalling?"
        case .cannotUninstallSelf: "Macuum Cleaner cannot uninstall itself."
        case .systemApp: "System apps cannot be removed."
        case .appNotFound(let n): "\(n) is no longer found."
        case .blocked(let n): "\(n) cannot be removed."
        }
    }
}

public actor UninstallEngine {
    private let validator: SafetyValidator
    private let history: ScanHistory?
    private let isRunning: @Sendable (String) -> Bool
    private let notify: @Sendable (String) -> Void

    public init(validator: SafetyValidator, history: ScanHistory? = nil,
                isRunning: @escaping @Sendable (String) -> Bool = { id in
                    !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty },
                notify: @escaping @Sendable (String) -> Void = { _ in }) {
        self.validator = validator; self.history = history; self.isRunning = isRunning; self.notify = notify
    }

    /// Always moves to Trash; never permanently deletes.
    public func uninstall(app: InstalledApp, includeRemnants: [AppRemnant],
                          progressHandler: @escaping @Sendable (UninstallProgress) -> Void = { _ in }) async throws -> UninstallResult {
        if app.bundleIdentifier == SafetyValidator.ownBundleIdentifier { throw UninstallError.cannotUninstallSelf }
        let path = app.bundleURL.standardizedFileURL.path
        if app.isSystemApp || path.hasPrefix("/System/") || path.hasPrefix("/usr/") { throw UninstallError.systemApp(app.displayName) }
        guard FileManager.default.fileExists(atPath: path) else { throw UninstallError.appNotFound(app.displayName) }
        if isRunning(app.bundleIdentifier) { throw UninstallError.appIsRunning(app.displayName) }

        let fm = FileManager.default
        let total = 1 + includeRemnants.count
        var removed: [URL] = [], errors: [UninstallFailure] = []
        var recovered: Int64 = 0

        func trash(_ url: URL, size: Int64, step: Int, label: String) {
            progressHandler(UninstallProgress(appName: app.displayName, currentStep: label, stepIndex: step, totalSteps: total))
            let verdict = validator.validate(url)
            guard verdict.isAllowed else { NSLog("Macuum: blocked %@ (%@)", url.path, String(describing: verdict)); return }
            guard fm.fileExists(atPath: url.path) || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            else { return }   // already gone: skip silently, don't count its size
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                removed.append(url); recovered += size
            } catch {
                let code = (error as NSError).code
                errors.append(UninstallFailure(url: url, message: error.localizedDescription,
                                               isPermissionDenied: code == NSFileWriteNoPermissionError || code == NSFileReadNoPermissionError))
            }
        }

        trash(app.bundleURL, size: app.bundleSize, step: 1, label: "Removing app bundle…")
        // If the bundle itself couldn't be removed, don't strip its support files.
        if removed.isEmpty, !errors.isEmpty { return UninstallResult(app: app, removedItems: [], totalBytesRecovered: 0, errors: errors) }

        for (i, r) in includeRemnants.enumerated() {
            try Task.checkCancellation()
            trash(r.url, size: r.size, step: i + 2, label: "Removing \(r.kind.rawValue)…")
        }

        let result = UninstallResult(app: app, removedItems: removed, totalBytesRecovered: recovered, errors: errors)
        await history?.append(HistoryEntry(kind: .uninstall, itemCount: removed.count, bytes: recovered, samplePaths: removed.map(\.path)))
        notify("\(app.displayName) has been uninstalled. \(ByteFormatter.string(from: recovered)) moved to Trash.")
        return result
    }

    /// Asks a running app to quit and waits briefly. Returns true once it has exited.
    public func quit(app: InstalledApp, timeout: TimeInterval = 8) async -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if apps.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return apps.allSatisfy(\.isTerminated)
    }

    /// Sequential batch uninstall (never concurrent, to avoid file-system conflicts).
    public func uninstall(batch: [(InstalledApp, [AppRemnant])],
                          progressHandler: @escaping @Sendable (UninstallProgress) -> Void = { _ in }) async -> [Result<UninstallResult, Error>] {
        var results: [Result<UninstallResult, Error>] = []
        for (app, remnants) in batch {
            do { results.append(.success(try await uninstall(app: app, includeRemnants: remnants, progressHandler: progressHandler))) }
            catch { results.append(.failure(error)) }
        }
        return results
    }
}
