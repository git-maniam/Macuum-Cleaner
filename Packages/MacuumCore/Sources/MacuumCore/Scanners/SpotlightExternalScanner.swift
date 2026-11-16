import Foundation

/// Category 19. Hidden index folders on external volumes only; never the boot volume.
public struct SpotlightExternalScanner: ScannerProtocol {
    public let categoryID: JunkCategory = .spotlightExternal
    let context: ScanContext
    public init(context: ScanContext) { self.context = context }

    public func scan() async throws -> [JunkFile] {
        var out: [JunkFile] = []
        for vol in ExternalVolumes.list(root: context.volumesRoot) {
            for name in [".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100"] {
                if let f = try ScannerSupport.junkFile(url: vol.appendingPathComponent(name), category: .spotlightExternal, context: context,
                                                       displayName: "\(vol.lastPathComponent)/\(name)") { out.append(f) }
            }
        }
        return out
    }
}
