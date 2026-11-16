import Foundation

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let itemCount: Int
    public let bytes: Int64
    public let permanent: Bool
    /// Paths removed (capped to keep the file small).
    public let samplePaths: [String]

    public enum Kind: String, Codable, Sendable { case scan, clean, uninstall }

    public init(kind: Kind, itemCount: Int, bytes: Int64, permanent: Bool = false,
                samplePaths: [String] = [], date: Date = Date()) {
        self.id = UUID(); self.date = date; self.kind = kind; self.itemCount = itemCount
        self.bytes = bytes; self.permanent = permanent; self.samplePaths = Array(samplePaths.prefix(200))
    }
}

/// Persists past scan/clean records as JSON in Application Support.
public actor ScanHistory {
    private let fileURL: URL
    private var entries: [HistoryEntry] = []
    private var loaded = false
    private let maxEntries = 500

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("Macuum Cleaner/history.json")
        }
    }

    public func all() -> [HistoryEntry] { loadIfNeeded(); return entries }

    public func append(_ entry: HistoryEntry) {
        loadIfNeeded()
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        persist()
    }

    public var lastScanDate: Date? {
        loadIfNeeded()
        return entries.last(where: { $0.kind == .scan })?.date
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        entries = (try? dec.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }
}
