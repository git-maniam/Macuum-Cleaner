import Foundation

/// Category 5. History/cookies are never pre-selected; caches are.
public struct BrowserScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .browserData
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    struct Target { let browser: String; let kind: String; let pattern: String }

    static func chromium(_ browser: String, support: String, cache: String) -> [Target] {
        let s = "~/Library/Application Support/\(support)"
        return [
            Target(browser: browser, kind: "Cache", pattern: "~/Library/Caches/\(cache)"),
            Target(browser: browser, kind: "History", pattern: "\(s)/Default/History"),
            Target(browser: browser, kind: "Cookies", pattern: "\(s)/Default/Cookies"),
            Target(browser: browser, kind: "Cookies", pattern: "\(s)/Default/Network/Cookies"),
            Target(browser: browser, kind: "Sessions", pattern: "\(s)/Default/Sessions"),
        ]
    }

    static let targets: [Target] = [
        Target(browser: "Safari", kind: "History", pattern: "~/Library/Safari/History.db"),
        Target(browser: "Safari", kind: "Cookies", pattern: "~/Library/Cookies/Cookies.binarycookies"),
        Target(browser: "Safari", kind: "Cache", pattern: "~/Library/Caches/com.apple.Safari"),
        Target(browser: "Safari", kind: "Downloads list", pattern: "~/Library/Safari/Downloads.plist"),
        Target(browser: "Firefox", kind: "History/Cookies", pattern: "~/Library/Application Support/Firefox/Profiles/*/places.sqlite"),
        Target(browser: "Firefox", kind: "Cache", pattern: "~/Library/Caches/Firefox/Profiles"),
        Target(browser: "Firefox", kind: "Crash Reports", pattern: "~/Library/Application Support/Firefox/Crash Reports"),
    ] + chromium("Chrome", support: "Google/Chrome", cache: "Google/Chrome")
      + chromium("Edge", support: "Microsoft Edge", cache: "Microsoft Edge")
      + chromium("Brave", support: "BraveSoftware/Brave-Browser", cache: "BraveSoftware")
      + chromium("Arc", support: "Arc/User Data", cache: "company.thebrowser.Browser")

    public func scan() async throws -> [JunkFile] {
        var out: [JunkFile] = []
        for t in Self.targets {
            try Task.checkCancellation()
            let expanded = PathExpander.expand(t.pattern, home: context.home)
            for url in PathExpander.glob(expanded) {
                if let f = try ScannerSupport.junkFile(url: url, category: .browserData, context: context,
                                                       displayName: "\(t.browser) \(t.kind)",
                                                       metadata: ["browser": t.browser, "kind": t.kind],
                                                       isSelected: t.kind == "Cache") { out.append(f) }
            }
        }
        return out
    }
}
