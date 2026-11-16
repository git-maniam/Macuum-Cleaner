import Foundation

/// Category 22. Large user data: shown with sizes, never pre-selected.
public struct VMDockerScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .vmDockerLeftovers
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    static let targets: [(String, String)] = [
        ("VMware Fusion VMs", "~/Documents/Virtual Machines"),
        ("Parallels VMs", "~/Parallels"),
        ("UTM VMs", "~/Library/Containers/com.utmapp.UTM"),
        ("Docker Desktop data", "~/Library/Containers/com.docker.docker/Data/vms"),
        ("VirtualBox VMs", "~/VirtualBox VMs"),
    ]

    public func scan() async throws -> [JunkFile] {
        try Self.targets.compactMap { name, path in
            try ScannerSupport.junkFile(url: PathExpander.url(path, home: context.home), category: .vmDockerLeftovers,
                                        context: context, displayName: name, isSelected: false)
        }
    }
}
