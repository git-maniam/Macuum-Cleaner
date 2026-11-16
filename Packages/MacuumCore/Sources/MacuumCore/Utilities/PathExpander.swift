import Foundation

public enum PathExpander {
    /// Expands a leading `~` and `$VAR` / `${VAR}` references. Unknown variables are left untouched.
    public static func expand(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var result = path
        if result == "~" { result = home.path }
        else if result.hasPrefix("~/") { result = home.path + String(result.dropFirst(1)) }

        let pattern = #"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = result as NSString
        var out = ""
        var cursor = 0
        for m in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let nameRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            let name = ns.substring(with: nameRange)
            out += environment[name] ?? ns.substring(with: m.range)
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    public static func url(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        URL(fileURLWithPath: expand(path, home: home))
    }

    /// Expands `*` / `?` wildcards per path component (e.g. `.../Profiles/*/places.sqlite`). Returns existing matches only.
    public static func glob(_ pattern: String, fileManager: FileManager = .default) -> [URL] {
        let comps = (pattern as NSString).pathComponents
        guard let first = comps.first else { return [] }
        var current: [String] = [first]
        for comp in comps.dropFirst() {
            var next: [String] = []
            for base in current {
                if comp.contains("*") || comp.contains("?") {
                    guard let names = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
                    for n in names.sorted() where fnmatch(comp, n, 0) == 0 {
                        next.append((base as NSString).appendingPathComponent(n))
                    }
                } else {
                    let p = (base as NSString).appendingPathComponent(comp)
                    if fileManager.fileExists(atPath: p) { next.append(p) }
                }
            }
            current = next
        }
        return current.map { URL(fileURLWithPath: $0) }
    }
}
