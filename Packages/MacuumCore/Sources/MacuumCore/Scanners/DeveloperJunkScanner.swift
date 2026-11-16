import Foundation

/// Category 7 (and the shared path table for Category 17). Sub-items that need a warning are not pre-selected.
public struct DeveloperJunkScanner: ScannerProtocol {
    public let categoryID: JunkCategory
    let context: ScanContext

    public init(context: ScanContext, category: JunkCategory = .developerJunk) {
        precondition(category == .developerJunk || category == .packageManagers)
        self.context = context; self.categoryID = category
    }

    struct Item { let name: String; let path: String; let warn: Bool }

    static let xcode: [Item] = [
        Item(name: "Xcode Derived Data", path: "~/Library/Developer/Xcode/DerivedData", warn: false),
        Item(name: "Xcode Archives", path: "~/Library/Developer/Xcode/Archives", warn: true),
        Item(name: "Xcode iOS Device Support", path: "~/Library/Developer/Xcode/iOS DeviceSupport", warn: false),
        Item(name: "Simulator Caches", path: "~/Library/Developer/CoreSimulator/Caches", warn: false),
        Item(name: "Swift Package Cache", path: "~/Library/Caches/org.swift.swiftpm", warn: false),
    ]
    static let packages: [Item] = [
        Item(name: "Homebrew Cache", path: "~/Library/Caches/Homebrew", warn: false),
        Item(name: "npm Cache", path: "~/.npm/_cacache", warn: false),
        Item(name: "Yarn Cache", path: "~/Library/Caches/Yarn", warn: false),
        Item(name: "Yarn Cache", path: "~/Library/Caches/yarn", warn: false),
        Item(name: "pip Cache", path: "~/Library/Caches/pip", warn: false),
        Item(name: "Gradle Cache", path: "~/.gradle/caches", warn: false),
        Item(name: "CocoaPods Cache", path: "~/Library/Caches/CocoaPods", warn: false),
        Item(name: "Dart/Flutter pub cache", path: "~/.pub-cache", warn: true),
        Item(name: "CocoaPods spec repos", path: "~/.cocoapods/repos", warn: true),
        Item(name: "Maven Repository", path: "~/.m2/repository", warn: true),
        Item(name: "Cargo Registry", path: "~/.cargo/registry", warn: true),
    ]

    public func scan() async throws -> [JunkFile] {
        let items = categoryID == .developerJunk ? Self.xcode + Self.packages : Self.packages.filter { !$0.path.contains(".m2") && !$0.path.contains(".cargo") }
        var out: [JunkFile] = []
        for item in items {
            try Task.checkCancellation()
            let url = PathExpander.url(item.path, home: context.home)
            if let f = try ScannerSupport.junkFile(url: url, category: categoryID, context: context, displayName: item.name,
                                                   metadata: ["subItem": item.name], isSelected: !item.warn) { out.append(f) }
        }
        if categoryID == .developerJunk { out += try staleSimulators() }
        return out
    }

    /// Simulator devices not touched in 90+ days.
    private func staleSimulators() throws -> [JunkFile] {
        let dir = context.library.appendingPathComponent("Developer/CoreSimulator/Devices")
        var out: [JunkFile] = []
        for dev in DirectoryWalker.children(of: dir) where dev.lastPathComponent != "device_set.plist" {
            guard context.now.timeIntervalSince(DirectoryWalker.modificationDate(of: dev)) > 90 * 86_400 else { continue }
            if let f = try ScannerSupport.junkFile(url: dev, category: .developerJunk, context: context,
                                                   displayName: "Unused iOS Simulator \(dev.lastPathComponent.prefix(8))",
                                                   metadata: ["subItem": "iOS Simulator"], isSelected: false) { out.append(f) }
        }
        return out
    }
}
