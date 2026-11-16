import Foundation

public enum CleanMethod: Sendable {
    case moveToTrash
    case permanentDelete
}

public struct CleanProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentPath: String
}

public struct CleanFailure: Sendable {
    public let file: JunkFile
    public let message: String
    public let isDiskFull: Bool
}

public struct CleanResult: Sendable {
    public var removed: [JunkFile] = []
    public var failed: [CleanFailure] = []
    /// Files refused by the safety layer or not part of an authorized scan. Never shown as errors.
    public var blocked: [JunkFile] = []
    public var bytesRecovered: Int64 { removed.reduce(0) { $0 + $1.size } }
    public var diskFullEncountered: Bool { failed.contains { $0.isDiskFull } }
}

public enum CleanError: Error, LocalizedError {
    case permanentDeleteDisabled
    public var errorDescription: String? { "Permanent deletion is disabled in Settings." }
}

public actor CleanEngine {
    private let validator: SafetyValidator
    private let history: ScanHistory?
    private let permanentDeleteAllowed: Bool
    private var authorizedPaths = Set<String>()

    public init(validator: SafetyValidator, history: ScanHistory? = nil, permanentDeleteAllowed: Bool = false) {
        self.validator = validator
        self.history = history
        self.permanentDeleteAllowed = permanentDeleteAllowed
    }

    /// Only files produced by a scan can be cleaned: register the result before calling `clean`.
    public func authorize(_ result: ScanResult) {
        for file in result.filesByCategory.values.joined() where file.isFileSystemItem {
            authorizedPaths.insert(Self.key(file.url))
        }
    }

    public func clean(files: [JunkFile], method: CleanMethod,
                      progressHandler: @escaping @Sendable (CleanProgress) -> Void = { _ in }) async throws -> CleanResult {
        if method == .permanentDelete && !permanentDeleteAllowed { throw CleanError.permanentDeleteDisabled }
        var result = CleanResult()
        let fm = FileManager.default

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            progressHandler(CleanProgress(completed: index, total: files.count, currentPath: file.url.path))

            if file.isAdvisoryOnly { result.blocked.append(file); continue }
            if !file.isFileSystemItem {
                await removeNonFileItem(file, into: &result)
                continue
            }
            guard authorizedPaths.contains(Self.key(file.url)) else { result.blocked.append(file); continue }
            let verdict = validator.validate(file.url)
            guard verdict.isAllowed else {
                NSLog("Macuum: blocked %@ (%@)", file.url.path, String(describing: verdict))
                result.blocked.append(file); continue
            }
            if file.category == .tempFiles, await SafetyValidator.isOpenByProcess(file.url) {
                result.failed.append(CleanFailure(file: file, message: "File is in use", isDiskFull: false)); continue
            }

            do {
                // Items already in the Trash can only be emptied, never "trashed" again.
                if method == .permanentDelete || file.category == .trash {
                    try fm.removeItem(at: file.url)
                } else {
                    try fm.trashItem(at: file.url, resultingItemURL: nil)
                }
                result.removed.append(file)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                continue   // vanished during scan/clean: skip silently
            } catch {
                let ns = error as NSError
                let full = ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError
                result.failed.append(CleanFailure(file: file, message: error.localizedDescription, isDiskFull: full))
            }
        }
        progressHandler(CleanProgress(completed: files.count, total: files.count, currentPath: ""))

        await history?.append(HistoryEntry(kind: .clean, itemCount: result.removed.count, bytes: result.bytesRecovered,
                                           permanent: method == .permanentDelete,
                                           samplePaths: result.removed.map(\.url.path)))
        return result
    }

    /// Time Machine snapshots are removed through `tmutil`, keyed by `metadata["snapshotDate"]`.
    private func removeNonFileItem(_ file: JunkFile, into result: inout CleanResult) async {
        guard file.category == .timeMachineSnapshots, let date = file.metadata["snapshotDate"],
              date.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil else {
            result.blocked.append(file); return
        }
        do {
            let r = try await ShellRunner.run("/usr/bin/tmutil", ["deletelocalsnapshots", date], timeout: 120)
            if r.succeeded { result.removed.append(file) }
            else { result.failed.append(CleanFailure(file: file, message: r.stderr, isDiskFull: false)) }
        } catch {
            result.failed.append(CleanFailure(file: file, message: error.localizedDescription, isDiskFull: false))
        }
    }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }
}
